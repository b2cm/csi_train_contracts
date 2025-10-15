// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.2;

/**
 * @title TrainProduct - Main insurance contract for train delay protection
 * @notice Handles the complete lifecycle of train delay protection policies
 * @dev Integrates with GIF framework and Chainlink oracles for automated policy management
 * @dev Designed for Mumbai testnet, provides comprehensive train delay coverage
 * @dev Two-phase oracle system: ratings for underwriting, status for claims processing
 */

import "../shared/TransferHelper.sol";

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "@etherisc/gif-interface/contracts/components/Product.sol";
import "../modules/PolicyController.sol";

contract TrainProduct is Product, AccessControl, Initializable {
    /// @notice Product name identifier for the GIF framework
    bytes32 public constant NAME = "TrainDelayChainlink";
    
    /// @notice Product version for tracking contract updates
    bytes32 public constant VERSION = "0.0.1";
    
    /// @notice Policy flow identifier used by GIF framework
    bytes32 public constant POLICY_FLOW = "PolicyDefaultFlow";
    
    /// @notice Role identifier for insurance company operations
    bytes32 public constant INSURER_ROLE = keccak256("INSURER");

    /// @notice Emitted when a train ratings request is sent to oracle
    /// @param requestId Unique identifier for the oracle request
    /// @param customer Address of the policy applicant
    /// @param journey Train journey identifier
    /// @param policyType Policy coverage type (0=small, 1=medium, 2=large)
    event LogRequestTrainRatings(
        uint256 requestId,
        address customer,
        string journey,
        uint256 policyType
    );

    /// @notice Emitted when train ratings oracle responds with risk assessment
    /// @param gifRequestId GIF framework request identifier
    /// @param customer Address of the policy applicant
    /// @param status Risk assessment status code
    /// @param payout Calculated payout amount for potential claims
    event FulfillTrainRatings(
        uint256 gifRequestId,
        address customer,
        uint256 status,
        uint256 payout
    );

    /// @notice Emitted when a new policy is successfully created and underwritten
    /// @param processId GIF framework process identifier
    /// @param customer Address of the policyholder
    /// @param premium Premium amount paid by customer
    /// @param payout Payout amount for delays
    /// @param journey Train journey
    /// @param metaData Additional policy metadata
    event LogPolicyCreated(
        bytes32 processId,
        address customer,
        uint256 premium,
        uint256 payout,
        string journey,
        string metaData
    );

    /// @notice Emitted when a train status check request is scheduled
    /// @param customer Address of the policyholder
    /// @param requestId Unique identifier for the status request
    /// @param journey Train journey identifier
    /// @param arrivalTimestamp Scheduled arrival time for monitoring
    event LogRequestTrainStatus(
        address customer,
        uint256 requestId,
        string journey,
        uint256 arrivalTimestamp
    );

    /// @notice Emitted when train status oracle responds with delay information
    /// @param gifRequestId GIF framework request identifier
    /// @param customer Address of the policyholder
    /// @param status Status code
    /// @param delay Actual delay in minutes
    event FulfillTrainStatus(
        uint256 gifRequestId,
        address customer,
        uint256 status,
        uint256 delay
    );

    /// @notice Emitted when a payout is processed for a delayed train
    /// @param customer Address of the policyholder receiving payout
    /// @param processId GIF framework process identifier
    /// @param claimId Claim identifier within GIF
    /// @param payoutId Payout identifier within GIF
    /// @param amount Payout amount transferred
    /// @param delay Train delay in minutes that triggered payout
    event LogPayoutTransferred(
        address customer,
        bytes32 processId,
        uint256 claimId,
        uint256 payoutId,
        uint256 amount,
        uint256 delay
    );

    /// @notice Emitted when a policy expires without payout (train was on time)
    /// @param customer Address of the policyholder
    /// @param processId GIF framework process identifier
    /// @param delay Actual delay in minutes (below payout threshold)
    event LogPolicyExpiredWithoutPayout(
        address customer,
        bytes32 processId,
        uint256 delay
    );

    /// @notice Time delay after scheduled arrival before checking for delays
    /// @dev Currently 12 hours for pilot testing
    uint256 public constant CHECK_OFFSET = 12 hours; 
    
    /// @notice Frequency of Chainlink Keeper checks for due requests
    /// @dev Keepers check every 2 minutes for requests ready to execute
    uint256 public constant KEEPER_OFFSET = 2 minutes;
    
    /// @notice Minimum delay threshold for payout eligibility (in minutes)
    /// @dev Delays of 60+ minutes qualify for insurance payout
    uint256 public constant DELAY_PAYOUT = 60;

    // Status codes returned by oracles
    /// @notice Successful operation - no issues detected
    uint256 public constant STATUS_OK = 0;
    
    /// @notice Journey contains Rail Replacement Service (RPS) - ineligible for coverage
    uint256 public constant STATUS_SEV = 10;
    
    /// @notice Journey outside allowed timeframe for coverage
    uint256 public constant STATUS_TIME = 20;
    
    /// @notice Risk probability too high (>40%) for coverage
    uint256 public constant STATUS_PROBABILITY = 30;
    
    /// @notice Delay data missing - request should be queued again
    uint256 public constant STATUS_MISSING_DELAY = 40;
    
    /// @notice General error occurred in oracle processing
    uint256 public constant STATUS_ERROR = 100;
    
    /// @notice Scaling factor for ERC-20 token decimal precision
    /// @dev Handles 18-decimal tokens by scaling values appropriately
    uint256 public constant SCALING_FACTOR = 10 ** 18; 

    // Premium pricing tiers for different coverage levels
    /// @notice Premium for small coverage policies (3 tokens)
    uint256 public constant PRICE_SMALL = 3 * SCALING_FACTOR;
    
    /// @notice Premium for medium coverage policies (5 tokens)  
    uint256 public constant PRICE_MEDIUM = 5 * SCALING_FACTOR;
    
    /// @notice Premium for large coverage policies (7 tokens)
    uint256 public constant PRICE_LARGE = 7 * SCALING_FACTOR;

    /// @notice Callback function name for train ratings oracle responses
    string public constant RATINGS_CALLBACK = "trainRatingsCallback";
    
    /// @notice Callback function name for train status oracle responses
    string public constant STATUSES_CALLBACK = "trainStatusCallback";

    /// @notice Counter for generating unique risk identifiers
    /// @dev Incremented for each new policy application
    uint256 public nonce;

    /// @notice Structure containing all risk-related data for a policy
    struct Risk {
        address customer;           // Address of the policyholder
        uint256 policyType;         // Coverage level: 0=small, 1=medium, 2=large
        uint256 price;              // Premium amount based on policy type
        string journey;             // Encoded journey information from customer
        uint256 arrivalTimestamp;   // Scheduled arrival time for monitoring
        uint256 payout;             // Calculated payout amount for qualifying delays
        uint256 delay;              // Actual delay in minutes (set after arrival)
        bool delayed;               // Whether delay qualifies for payout (>=60min)
    }

    /// @dev Maps risk IDs to their corresponding risk data
    mapping(bytes32 => Risk) public risks;
    
    /// @dev Maps process IDs to active policy status for quick lookup
    mapping(bytes32 => bool) public activePolicy;
    
    /// @dev Maps customer addresses to their policy process IDs
    mapping(address => bytes32[]) public addressToProcessId;
    
    /// @dev Maps customer addresses to total number of policies purchased
    mapping(address => uint256) public addressToPolicyCount;

    /// @notice Oracle ID for train ratings/risk assessment requests
    uint256 public ratingsOracleId;
    
    /// @notice Oracle ID for train status/delay monitoring requests
    uint256 public statusesOracleId;
    
    /// @notice ERC20 token contract used for premium payments and payouts
    IERC20 public token;
    
    /// @notice Treasury address that receives premium payments
    address public treasury;

    /**
     * @notice Constructor to initialize the TrainProduct contract
     * @param _registry Address of the GIF registry contract
     * @param _token Address of the ERC20 token for payments (e.g., EuroCoin)
     * @param _treasury Address that will receive premium payments
     * @param _riskpoolId ID of the risk pool that will back policies
     * @param _insurer Address granted insurer role permissions
     * @param _ratingsOracleId ID of oracle for risk assessment/ratings
     * @param _statusesOracleId ID of oracle for train status monitoring
     */
    constructor(
        address _registry,
        address _token,
        address _treasury,
        uint256 _riskpoolId,
        address _insurer,
        uint256 _ratingsOracleId,
        uint256 _statusesOracleId
    ) Product(NAME, _token, POLICY_FLOW, _riskpoolId, _registry) {
        // Set oracle IDs for risk assessment and status monitoring
        ratingsOracleId = _ratingsOracleId;
        statusesOracleId = _statusesOracleId;

        // Initialize risk ID counter
        nonce = 0;

        // Set payment token and treasury addresses
        token = IERC20(_token);
        treasury = _treasury;

        // Setup access control roles
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(INSURER_ROLE, _insurer);
    }

    /**
     * @notice Initiates a train delay insurance policy application
     * @dev Starts the two-phase process: risk assessment then policy creation
     * @param _journey Encoded journey information (route, train, time details)
     * @param _policyType Coverage level: 0=small, 1=medium, 2=large
     * @param _arrivalTimestamp Scheduled arrival time for delay monitoring
     * @param _metaData Additional metadata for the policy
     */
    function applyForPolicy(
        string memory _journey,
        uint256 _policyType,
        uint256 _arrivalTimestamp,
        string memory _metaData
    ) external {
        // Validate policy type (must be 0, 1, or 2)
        require(
            _policyType == 0 || _policyType == 1 || _policyType == 2,
            "ERR: invalid policy type"
        );

        // Determine premium based on coverage level
        uint256 price;
        if (_policyType == 0) {
            price = PRICE_SMALL;        // 3 tokens
        } else if (_policyType == 1) {
            price = PRICE_MEDIUM;       // 5 tokens
        } else if (_policyType == 2) {
            price = PRICE_LARGE;        // 7 tokens
        }

        // Verify customer has approved sufficient token allowance
        require(
            token.allowance(msg.sender, treasury) >= price,
            "ERR: missing customer allowance for erc20 token"
        );

        // Create unique risk identifier and store initial risk data
        bytes32 riskId = keccak256(abi.encode(nonce));
        Risk storage risk = risks[riskId];
        nonce++;

        // Initialize risk data
        if (
            keccak256(abi.encodePacked(risk.journey)) ==
            keccak256(abi.encodePacked(("")))
        ) {
            risk.customer = msg.sender;
            risk.policyType = _policyType;
            risk.price = price;
            risk.journey = _journey;
            risk.arrivalTimestamp = _arrivalTimestamp;
        }

        // Create temporary application for risk assessment phase
        bytes memory metaData = abi.encode(_metaData);
        bytes memory applicationData = abi.encode(riskId);

        // Create dummy application to trigger oracle request
        bytes32 dummyProcessId = _newApplication(
            msg.sender,     // policy holder
            1,              // premium (dummy value for assessment phase)
            2,              // sumInsured (dummy value for assessment phase)
            metaData,
            applicationData
        );

        // Request risk assessment from ratings oracle
        uint256 requestId = _request(
            dummyProcessId,
            abi.encode(_journey, _policyType),
            RATINGS_CALLBACK,
            ratingsOracleId
        );

        emit LogRequestTrainRatings(
            requestId,
            msg.sender,
            _journey,
            _policyType
        );
    }
    }

    /**
     * @notice Callback function for train ratings oracle responses
     * @dev Processes risk assessment results and creates final policy if approved
     * @dev Called by ratings oracle after evaluating journey risk
     * @param _requestId Oracle request identifier
     * @param _dummyProcessId Temporary process ID from assessment phase
     * @param _response Encoded oracle response (status, payout)
     */
    function trainRatingsCallback(
        uint256 _requestId,
        bytes32 _dummyProcessId,
        bytes calldata _response
    ) external onlyOracle {
        // Retrieve application data from assessment phase
        IPolicy.Application memory application = _getApplication(
            _dummyProcessId
        );

        // Extract risk data using stored risk ID
        bytes32 riskId = abi.decode(application.data, (bytes32));
        Risk storage risk = risks[riskId];

        // Get metadata from assessment application
        IPolicy.Metadata memory metaDataDummy = _getMetadata(_dummyProcessId);
        string memory metaDataString = abi.decode(metaDataDummy.data, (string));

        // Decode oracle response: status code and payout amount
        (uint256 status, uint256 payout) = abi.decode(
            _response,
            (uint256, uint256)
        );

        // Store calculated payout amount (scale to 18 decimals)
        risk.payout = payout * SCALING_FACTOR; 

        // Process risk assessment results
        if (status == STATUS_SEV) {
            revert("ERR: journey contains RPS");
        }
        else if (status == STATUS_TIME) {
            revert("ERR: journey out of timeframe");
        }
        else if (status == STATUS_PROBABILITY) {
            revert("ERR: probability too high (> 40%)");
        }
        else if (status == STATUS_ERROR) {
            revert("ERR: something went wrong in rating oracle");
        }

        // Require successful risk assessment
        require(
            status == STATUS_OK,
            "ERR: something went wrong in rating oracle"
        );

        // Clean up assessment phase
        _decline(_dummyProcessId);

        // Create final policy application with real values
        bytes memory metaData = "";
        bytes memory applicationData = abi.encode(riskId);

        bytes32 processId = _newApplication(
            risk.customer,  // policyholder address
            risk.price,     // actual premium amount
            risk.payout,    // calculated payout amount
            metaData,
            applicationData // contains riskId for lookup
        );

        // access application and meta data
        // IPolicy.Application memory application = _getApplication(_processId);
        // IPolicy.Metadata memory metadata = _getMetadata(_processId); // other attributes

        // ACCEPT OR DENY policy
        // for now accept every policy (i.e. _underwrite)
        // deny if e.g. probability too high (i.e. _decline)

        _underwrite(processId); // policy is accepted and now active, underwrite collects the premium

        emit FulfillTrainRatings(_requestId, risk.customer, status, payout);

        // Verify premium payment was successful
        IPolicy.Policy memory policy = _getPolicy(processId);
        require(
            policy.premiumPaidAmount == risk.price,
            "ERR: missing payment for policy"
        );

        emit LogPolicyCreated(
            processId,
            risk.customer,
            risk.price,
            risk.payout,
            risk.journey,
            metaDataString
        );

        // Update customer tracking data
        addressToProcessId[risk.customer].push(processId);
        addressToPolicyCount[risk.customer] += 1;
        activePolicy[processId] = true;

        // Schedule train status monitoring request
        uint256 requestId = _request(
            processId,
            abi.encode(
                roundUpOffset(risk.arrivalTimestamp + CHECK_OFFSET), // Check after arrival + offset
                risk.journey
            ),
            STATUSES_CALLBACK,
            statusesOracleId
        );

        emit LogRequestTrainStatus(
            risk.customer,
            requestId,
            risk.journey,
            risk.arrivalTimestamp
        );
    }

    /**
     * @notice Callback function for train status oracle responses
     * @dev Processes actual delay data and handles claim/payout if delay qualifies
     * @dev Called by status oracle after monitoring train arrival
     * @param _requestId Oracle request identifier
     * @param _processId Policy process ID
     * @param _response Encoded oracle response (status, delay in minutes)
     */
    function trainStatusCallback(
        uint256 _requestId,
        bytes32 _processId,
        bytes calldata _response
    ) external onlyOracle {
        // Decode oracle response: status code and delay in minutes
        (uint256 status, uint256 delay) = abi.decode(
            _response,
            (uint256, uint256)
        );

        // Retrieve risk data for this policy
        IPolicy.Application memory application = _getApplication(_processId);
        bytes32 riskId = abi.decode(application.data, (bytes32));
        Risk storage risk = risks[riskId];

        // Store actual delay for record keeping
        risk.delay = delay;

        emit FulfillTrainStatus(_requestId, risk.customer, status, delay);

        // Handle error statuses from oracle
        if (status == STATUS_MISSING_DELAY) {
            // TODO: Implement request queuing for retry
            revert("ERR: missing delay");
        }
        if (status == STATUS_ERROR) {
            revert("ERR: something went wrong in status oracle");
        }

        // Require successful status check
        require(
            status == STATUS_OK,
            "ERR: something went wrong in status oracle"
        );

        // Process delay results and determine payout eligibility
        if (delay >= DELAY_PAYOUT) {
            // Delay qualifies for payout (>=60 minutes)
            risk.delayed = true;

            // Initialize claims process through GIF framework
            uint256 claimAmount = risk.payout;
            uint256 claimId = _newClaim(_processId, claimAmount, "");

            // Confirm claim and process payout
            uint256 payoutAmount = claimAmount;
            _confirmClaim(_processId, claimId, payoutAmount);

            uint256 payoutId = _newPayout(
                _processId,
                claimId,
                payoutAmount,
                ""
            );
            _processPayout(_processId, payoutId);

            // @todo Check payoutAmount - Was everything paid?

            emit LogPayoutTransferred(
                risk.customer,
                _processId,
                claimId,
                payoutId,
                payoutAmount,
                delay
            );
        } else {
            // Train was on time or delay below threshold
            risk.delayed = false;
            emit LogPolicyExpiredWithoutPayout(
                risk.customer,
                _processId,
                delay
            );
        }

        // Finalize policy lifecycle
        _expire(_processId);
        _close(_processId);
        activePolicy[_processId] = false;
    }

    /**
     * @notice Rounds up a timestamp to the next Keeper check interval
     * @dev Ensures status requests align with Chainlink Keeper automation schedule
     * @param _time Input timestamp to round up
     * @return Rounded timestamp aligned to KEEPER_OFFSET boundaries
     */
    function roundUpOffset(uint256 _time) public pure returns (uint256) {
        return _time + (KEEPER_OFFSET - (_time % KEEPER_OFFSET));
    }
}

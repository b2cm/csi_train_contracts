// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

/**
 * @title TrainStatusOracle - Oracle for querying train status and delay information
 * @notice This contract requests train status data from TrainAPI using Chainlink oracles
 * @dev Designed for Mumbai testnet, integrates with Chainlink Keepers for automated execution
 * @dev Implements GIF Oracle interface and Chainlink automation for scheduled requests
 */

import "@openzeppelin/contracts/utils/Strings.sol";
import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";
import "@etherisc/gif-interface/contracts/components/Oracle.sol";
import "@chainlink/contracts/src/v0.8/AutomationCompatible.sol";

contract TrainStatusOracle is
    Oracle,
    ChainlinkClient,
    AutomationCompatibleInterface
{
    using Chainlink for Chainlink.Request;

    /// @dev Maps Chainlink request IDs to GIF request IDs
    mapping(bytes32 => uint256) public gifRequests;
    
    /// @notice Chainlink job ID for train status requests
    bytes32 public jobId;
    
    /// @notice Payment amount in LINK tokens for each Chainlink request
    uint256 public payment;

    /// @notice Time interval for Chainlink Keeper automation (2 minutes)
    uint256 public constant KEEPER_OFFSET = 2 minutes;

    /// @notice Structure to store queued oracle requests
    struct QueuedRequest {
        uint256 executionTime;  // Timestamp when the request should be executed
        string journey;         // Journey identifier for the train status query
    }

    /// @dev Maps GIF request IDs to their queued request details
    mapping(uint256 => QueuedRequest) public queuedRequests;
    
    /// @dev Tracks which request IDs are currently queued
    mapping(uint256 => bool) public isQueuedRequest;
    
    /// @dev Maps execution timestamps to arrays of request IDs scheduled for that time
    mapping(uint256 => uint256[]) public schedule;
    
    /// @notice ID of the most recently queued request
    uint256 public lastQueuedRequest;

    /// @notice Emitted when a new request is queued for future execution
    /// @param gifRequestId The GIF request identifier
    /// @param checkAtTime Timestamp when the request should be executed
    /// @param journey The journey identifier for the train
    event RequestQueued(
        uint256 gifRequestId,
        uint256 checkAtTime,
        string journey
    );

    /// @notice Emitted when a Chainlink request is sent for execution
    /// @param chainlinkRequestId The Chainlink request identifier
    /// @param gifRequestId The corresponding GIF request identifier
    /// @param checkAtTime Timestamp when the request was executed
    /// @param journey The journey identifier for the train
    event Request(
        bytes32 chainlinkRequestId,
        uint256 gifRequestId,
        uint256 checkAtTime,
        string journey
    );

    /**
     * @notice Constructor to initialize the TrainStatusOracle
     * @param _name Name of the oracle component
     * @param _registry Address of the GIF registry
     * @param _chainLinkToken Address of the LINK token contract
     * @param _chainLinkOperator Address of the Chainlink operator node
     * @param _jobId Chainlink job ID for train status requests
     * @param _payment Payment amount in LINK tokens per request
     */
    constructor(
        bytes32 _name,
        address _registry,
        address _chainLinkToken,
        address _chainLinkOperator,
        bytes32 _jobId,
        uint256 _payment
    ) Oracle(_name, _registry) {
        updateRequestDetails(
            _chainLinkToken,
            _chainLinkOperator,
            _jobId,
            _payment
        );
    }

    /**
     * @notice Updates Chainlink configuration parameters
     * @dev Only callable by contract owner
     * @param _chainLinkToken Address of the LINK token contract
     * @param _chainLinkOperator Address of the Chainlink operator
     * @param _jobId New Chainlink job ID
     * @param _payment New payment amount in LINK tokens
     */
    function updateRequestDetails(
        address _chainLinkToken,
        address _chainLinkOperator,
        bytes32 _jobId,
        uint256 _payment
    ) public onlyOwner {
        if (_chainLinkToken != address(0)) {
            setChainlinkToken(_chainLinkToken);
        }
        if (_chainLinkOperator != address(0)) {
            setChainlinkOracle(_chainLinkOperator);
        }

        jobId = _jobId;
        payment = _payment;
    }

    /**
     * @notice Queues a new oracle request for future execution
     * @dev Called by GIF framework to schedule train status queries
     * @param _gifRequestId Unique identifier for the GIF request
     * @param _input Encoded parameters (executionTime, journey)
     */
    function request(uint256 _gifRequestId, bytes calldata _input)
        external
        override
        onlyQuery
    {
        // Decode input parameters
        (uint256 executionTime, string memory journey) = abi.decode(
            _input,
            (uint256, string)
        );

        // Schedule the request for execution at the specified time
        schedule[executionTime].push(_gifRequestId);

        // Store request details
        QueuedRequest memory queued = QueuedRequest(executionTime, journey);
        queuedRequests[_gifRequestId] = queued;
        isQueuedRequest[_gifRequestId] = true;

        // Update last queued request counter
        if (_gifRequestId > lastQueuedRequest)
            lastQueuedRequest = _gifRequestId;

        emit RequestQueued(_gifRequestId, executionTime, journey);
    }

    /**
     * @notice Chainlink Keeper function to check if upkeep is needed
     * @dev Called by Chainlink Keepers to determine if any requests are due for execution
     * @return upkeepNeeded True if there are requests scheduled for the current time window
     * @return performData Encoded timestamp for the requests to execute
     */
    function checkUpkeep(
        bytes calldata /* checkData */
    )
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        uint256 timestamp = roundOffOffset(block.timestamp);
        upkeepNeeded = schedule[timestamp].length > 0;
        performData = abi.encode(timestamp);
        return (upkeepNeeded, performData);
    }

    /**
     * @notice Chainlink Keeper function to execute scheduled requests
     * @dev Called by Chainlink Keepers when upkeep is needed
     * @param performData Encoded timestamp containing requests to execute
     */
    function performUpkeep(bytes calldata performData) external override {
        // Decode the timestamp from performData
        uint256 timestamp = abi.decode(performData, (uint256));

        // Execute all queued requests for this timestamp
        executeQueuedRequests(schedule[timestamp]);

        // Clean up the schedule entry
        delete schedule[timestamp];
    }

    /**
     * @notice Executes multiple queued oracle requests by sending Chainlink requests
     * @dev Validates each request and sends corresponding Chainlink API calls
     * @param _gifRequestIds Array of GIF request IDs to execute
     */
    function executeQueuedRequests(uint256[] memory _gifRequestIds) public {
        for (uint256 idx = 0; idx < _gifRequestIds.length; idx++) {
            require(
                isQueuedRequest[_gifRequestIds[idx]],
                "ERROR:NO_QUEUED_REQUEST"
            );
            QueuedRequest memory queued = queuedRequests[_gifRequestIds[idx]];

            // Verify that the request is due for execution
            require(
                queued.executionTime > 0 && queued.executionTime <= block.timestamp,
                "ERROR:QUEUED_REQUEST_NOT_DUE"
            );

            // Build Chainlink request with the fulfill callback
            Chainlink.Request memory req = buildChainlinkRequest(
                jobId,
                address(this),
                this.fulfill.selector
            );

            // Add journey parameter to the request
            req.add("journey", string(queued.journey));

            // Send the request
            bytes32 chainlinkRequestId = sendChainlinkRequest(req, payment);
            gifRequests[chainlinkRequestId] = _gifRequestIds[idx];

            // Clean up storage to prevent re-execution
            delete queuedRequests[_gifRequestIds[idx]];
            delete isQueuedRequest[_gifRequestIds[idx]];

            emit Request(
                chainlinkRequestId,
                _gifRequestIds[idx],
                queued.executionTime,
                queued.journey
            );
        }
    }

    /**
     * @notice Callback function for Chainlink oracle responses
     * @dev Called by Chainlink node when train status data is received
     * @param _chainlinkRequestId The Chainlink request identifier
     * @param _status Status code
     * @param _delay Delay amount in minutes (0 if on-time)
     */
    function fulfill(
        bytes32 _chainlinkRequestId,
        uint256 _status,
        uint256 _delay
    ) public recordChainlinkFulfillment(_chainlinkRequestId) {
        // Send response back to GIF framework
        _respond(
            gifRequests[_chainlinkRequestId],
            abi.encodePacked(_status, _delay)
        );
        // Clean up the request mapping
        delete gifRequests[_chainlinkRequestId];
    }

    /**
     * @notice Rounds down a timestamp to the nearest KEEPER_OFFSET interval
     * @dev Used to align request execution times with Keeper automation intervals
     * @param _time The timestamp to round down
     * @return The rounded timestamp aligned to KEEPER_OFFSET boundaries
     */
    function roundOffOffset(uint256 _time) public pure returns (uint256) {
        return _time - (_time % KEEPER_OFFSET);
    }

    /**
     * @notice Returns the number of requests scheduled for a specific timestamp
     * @dev Useful for monitoring and debugging the request schedule
     * @param _key The timestamp to check
     * @return The number of requests scheduled for execution at that time
     */
    function getScheduleLength(uint256 _key) public view returns (uint256) {
        return schedule[_key].length;
    }

    /**
     * @notice Cancels a pending oracle request (not implemented)
     * @dev Required by Oracle interface but not implemented in this version
     * @param requestId The request ID to cancel
     */
    function cancel(uint256 requestId) external override onlyOwner {
        // TODO: Implement request cancellation logic if needed
    }
}

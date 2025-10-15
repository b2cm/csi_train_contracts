// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

/**
 * @title TrainRatingsOracle - Oracle for querying train route ratings and risk assessment
 * @notice This contract requests train route risk ratings from TrainAPI using Chainlink oracles
 * @dev Designed for Mumbai testnet, provides risk assessment data for insurance pricin
 * @dev Different from TrainStatusOracle - this focuses on route risk ratings rather than real-time status
 */

import "@openzeppelin/contracts/utils/Strings.sol";
import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";
import "@etherisc/gif-interface/contracts/components/Oracle.sol";

contract TrainRatingsOracle is Oracle, ChainlinkClient {
    using Chainlink for Chainlink.Request;

    /// @dev Maps Chainlink request IDs to GIF request IDs for response tracking
    mapping(bytes32 => uint256) public gifRequests;
    
    /// @notice Chainlink job ID for train ratings requests
    bytes32 public jobId;
    
    /// @notice Payment amount in LINK tokens for each Chainlink request
    uint256 public payment;

    /// @notice Emitted when a new train ratings request is sent to Chainlink
    /// @param jobId The Chainlink job ID used for the request
    /// @param chainlinkRequestId The unique Chainlink request identifier
    /// @param gifRequestId The corresponding GIF request identifier
    /// @param journey The train journey identifier being rated
    /// @param policyType The policy type category (small, medium, large)
    event Request(
        bytes32 jobId,
        bytes32 chainlinkRequestId,
        uint256 gifRequestId,
        string journey,
        string policyType
    );

    /**
     * @notice Constructor to initialize the TrainRatingsOracle
     * @param _name Name of the oracle component
     * @param _registry Address of the GIF registry
     * @param _chainLinkToken Address of the LINK token contract
     * @param _chainLinkOperator Address of the Chainlink operator node
     * @param _jobId Chainlink job ID for train ratings requests
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
     * @param _chainLinkToken Address of the LINK token contract (pass 0x0 to skip update)
     * @param _chainLinkOperator Address of the Chainlink operator (pass 0x0 to skip update)
     * @param _jobId New Chainlink job ID for ratings requests
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
     * @notice Requests train route ratings from the external API
     * @dev Called by GIF framework to get risk assessment data for pricing
     * @param _gifRequestId Unique identifier for the GIF request
     * @param _input Encoded parameters (journey, policyType)
     */
    function request(uint256 _gifRequestId, bytes calldata _input)
        external
        override
        onlyQuery
    {
        // Build Chainlink request with the fulfill callback
        Chainlink.Request memory req = buildChainlinkRequest(
            jobId,
            address(this),
            this.fulfill.selector
        );

        // Decode input parameters: journey identifier and policy type
        (string memory journey, uint256 policyType) = abi.decode(
            _input,
            (string, uint256)
        );

        // Convert numeric policy type to string for API compatibility
        string memory policyTypeString;
        if (policyType == 0) {
            policyTypeString = "small";
        } else if (policyType == 1) {
            policyTypeString = "medium";
        } else if (policyType == 2) {
            policyTypeString = "large";
        }

        // Add request parameters for the TrainAPI
        req.add("journey", journey);
        req.add("type", policyTypeString);

        // Send request and map response tracking
        bytes32 chainlinkRequestId = sendChainlinkRequest(req, payment);
        gifRequests[chainlinkRequestId] = _gifRequestId;

        emit Request(jobId, chainlinkRequestId, _gifRequestId, journey, policyTypeString);
    }

    /**
     * @notice Callback function for Chainlink oracle responses with ratings data
     * @dev Called by Chainlink node when train route ratings are received
     * @param _chainlinkRequestId The Chainlink request identifier
     * @param _status Status code
     * @param _payout Paymout amount
     */
    function fulfill(
        bytes32 _chainlinkRequestId,
        uint256 _status,
        uint256 _payout
    ) public recordChainlinkFulfillment(_chainlinkRequestId) {
        // Send ratings response back to GIF framework
        _respond(
            gifRequests[_chainlinkRequestId],
            abi.encodePacked(_status, _payout)
        );
        // Clean up the request mapping
        delete gifRequests[_chainlinkRequestId];
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

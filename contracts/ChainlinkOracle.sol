// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

/**
 * @title ChainlinkOracle - Abstract base contract for Chainlink-based oracles
 * @notice Provides common Chainlink functionality for oracle implementations
 * @dev Designed for Mumbai testnet with hardcoded LINK token address
 * @dev Concrete implementations should inherit from this and implement specific oracle logic
 */

import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@etherisc/gif-interface/contracts/components/Oracle.sol";

abstract contract ChainlinkOracle is Ownable, Oracle, ChainlinkClient {

    /// @notice Chainlink job ID for oracle requests
    bytes32 public jobId;
    
    /// @notice Payment amount in LINK tokens for each request
    uint256 public payment;

    /// @dev Maps Chainlink request IDs to internal request IDs for response tracking
    mapping(bytes32 => uint256) public requests;

    /**
     * @notice Constructor to initialize the ChainlinkOracle base contract
     * @param _chainLinkOracle Address of the Chainlink oracle node
     * @param _registry Address of the GIF registry contract
     * @param _oracleName Unique name identifier for this oracle
     * @param _jobId Chainlink job ID for requests
     * @param _payment Payment amount in LINK tokens per request
     */
    constructor(
        address _chainLinkOracle,
        address _registry,
        bytes32 _oracleName,
        bytes32 _jobId,
        uint256 _payment
    )
    Oracle( _oracleName, _registry)
    {    
        // Set LINK token address for Mumbai testnet
        // Mumbai LINK token: 0x326C977E6efc84E512bB9C30f76E30c160eD06FB
        setChainlinkToken(0x326C977E6efc84E512bB9C30f76E30c160eD06FB);
        
        // Initialize Chainlink configuration
        _updateRequestDetails(_chainLinkOracle, _jobId, _payment);
    }

    /**
     * @notice Updates Chainlink oracle configuration parameters
     * @dev Only callable by contract owner
     * @param _oracle Address of the new Chainlink oracle node
     * @param _jobId New Chainlink job ID
     * @param _payment New payment amount in LINK tokens
     */
    function updateRequestDetails(
        address _oracle,
        bytes32 _jobId,
        uint256 _payment
    ) external onlyOwner() {
        _updateRequestDetails(_oracle, _jobId, _payment);
    }

    /**
     * @notice Internal function to update Chainlink configuration
     * @dev Private helper to avoid code duplication between constructor and public update
     * @param _oracle Address of the Chainlink oracle node
     * @param _jobId Chainlink job ID for requests
     * @param _payment Payment amount in LINK tokens per request
     */
    function _updateRequestDetails(
        address _oracle,
        bytes32 _jobId,
        uint256 _payment
    ) private {
        setChainlinkOracle(_oracle);
        jobId = _jobId;
        payment = _payment;
    }

    /**
     * @notice Returns the address of the LINK token contract
     * @dev Wrapper around Chainlink's chainlinkTokenAddress() for external access
     * @return Address of the LINK token contract
     */
    function getChainlinkToken() public view returns (address) {
        return chainlinkTokenAddress();
    }

    /**
     * @notice Returns the address of the current Chainlink oracle
     * @dev Wrapper around Chainlink's chainlinkOracleAddress() for external access
     * @return Address of the configured Chainlink oracle node
     */
    function getChainlinkOracle() public view returns (address) {
        return chainlinkOracleAddress();
    }

    /**
     * @notice Withdraws all LINK tokens from the contract to the owner
     * @dev Emergency function to recover LINK tokens, only callable by owner
     * @dev Transfers the entire LINK balance of this contract to the caller
     */
    function withdrawLink() public onlyOwner() {
        LinkTokenInterface link = LinkTokenInterface(chainlinkTokenAddress());
        require(
            link.transfer(msg.sender, link.balanceOf(address(this))), 
            "ERROR:UNABLE_TO_TRANSFER"
        );
    }

    /**
     * @notice Cancels a pending Chainlink request
     * @dev Only callable by contract owner, useful for stuck or expired requests
     * @param _requestId The Chainlink request ID to cancel
     * @param _payment The payment amount that was sent with the request
     * @param _callbackFunctionId The callback function selector that was specified
     * @param _expiration The expiration time that was set for the request
     */
    function cancelRequest(
        bytes32 _requestId,
        uint256 _payment,
        bytes4 _callbackFunctionId,
        uint256 _expiration
    )
    public
    onlyOwner()
    {
        cancelChainlinkRequest(_requestId, _payment, _callbackFunctionId, _expiration);
    }
}
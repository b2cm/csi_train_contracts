// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.2;

import "@openzeppelin/contracts/access/AccessControl.sol";

import "@etherisc/gif-interface/contracts/components/BasicRiskpool.sol";
import "@etherisc/gif-interface/contracts/modules/IBundle.sol";
import "@etherisc/gif-interface/contracts/modules/IPolicy.sol";

/**
 * @title TrainRiskpool - Risk pool for train delay insurance policies
 * @notice This contract manages the risk pool for train delay insurance, handling investor funds and policy coverage
 * @dev Extends BasicRiskpool with role-based access control for investors
 * @dev Uses AccessControl for managing investor permissions and fund management
 */
contract TrainRiskpool is 
    BasicRiskpool,
    AccessControl
{
    /// @notice Role identifier for investors who can create bundles and provide capital
    bytes32 public constant INVESTOR_ROLE = keccak256("INVESTOR");

    /// @notice Maximum total sum insured that can be secured by this risk pool
    /// @dev Set to 10^24 wei (1 million ETH with 18 decimals) to cap total exposure
    uint256 public constant SUM_OF_SUM_INSURED_CAP = 10**24;

    /**
     * @notice Constructor to initialize the TrainRiskpool
     * @dev Sets up the risk pool with specified parameters and grants admin role to deployer
     * @param name Unique identifier for the risk pool
     * @param collateralization Collateralization ratio (e.g., 20000 = 200% = 2.0x)
     * @param erc20Token Address of the ERC20 token used for payments (e.g., USDC, DAI)
     * @param wallet Address that will receive fees and manage funds
     * @param registry Address of the GIF registry contract
     */
    constructor(
        bytes32 name,
        uint256 collateralization,
        address erc20Token,
        address wallet,
        address registry
    )
        BasicRiskpool(name, collateralization, SUM_OF_SUM_INSURED_CAP, erc20Token, wallet, registry)
    {
        // Grant admin role to the contract deployer
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }


    /**
     * @notice Grants investor role to a new address
     * @dev Only the contract owner can grant investor roles
     * @dev Investors can create bundles and provide capital to the risk pool
     * @param investor Address to grant investor role to
     */
    function grantInvestorRole(address investor)
        external
        onlyOwner
    {
        _setupRole(INVESTOR_ROLE, investor);
    }


    /**
     * @notice Creates a new investment bundle in the risk pool
     * @dev Only addresses with INVESTOR_ROLE can create bundles
     * @dev Bundles represent investor capital that backs insurance policies
     * @param filter Encoded filter criteria for policies this bundle will cover
     * @param initialAmount Initial capital amount to deposit into the bundle
     * @return bundleId Unique identifier for the created bundle
     */
    function createBundle(bytes memory filter, uint256 initialAmount) 
        public override
        onlyRole(INVESTOR_ROLE)
        returns(uint256 bundleId)
    {
        bundleId = super.createBundle(filter, initialAmount);
    }


    /**
     * @notice Determines if a bundle can cover a specific policy application
     * @dev Currently implements a simple strategy: all bundles match all applications
     * @dev In production, this could include more sophisticated matching logic based on:
     *      - Route risk profiles, premium amounts, coverage types, etc.
     * @param bundle The investment bundle to check
     * @param application The policy application to match against
     * @return isMatching Always returns true in this implementation
     */
    function bundleMatchesApplication(
        IBundle.Bundle memory bundle, 
        IPolicy.Application memory application
    ) 
        public override
        pure
        returns(bool isMatching) 
    {
        // Simple matching strategy: all bundles can cover all applications
        // TODO: Implement more sophisticated matching logic if needed
        isMatching = true;
    }
}
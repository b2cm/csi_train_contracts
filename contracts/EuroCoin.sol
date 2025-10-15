// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.2;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title EuroCoin - Mock EUR token for train insurance payments
 * @notice A simple ERC20 token representing Euro currency for testing and development
 * @dev This is a mock token used in the train insurance system for premium payments and payouts
 */
contract EuroCoin is ERC20 {

    /// @notice Full name of the token
    string public constant NAME = "EURO";
    
    /// @notice Symbol used for the token
    string public constant SYMBOL = "EUR";

    /// @notice Initial supply of tokens minted to deployer (1 trillion EUR)
    /// @dev Set to 10^24 to provide sufficient liquidity for testing scenarios
    uint256 public constant INITIAL_SUPPLY = 10**24;

    /**
     * @notice Constructor that creates the EuroCoin token
     * @dev Mints the entire initial supply to the contract deployer
     * @dev Uses OpenZeppelin's ERC20 implementation with custom name and symbol
     */
    constructor()
        ERC20(NAME, SYMBOL)
    {
        // Mint initial supply to the contract deployer
        _mint(
            _msgSender(),
            INITIAL_SUPPLY
        );
    }

}
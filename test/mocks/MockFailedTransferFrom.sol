// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MockFailedTransferFrom
 * @notice Mock ERC20 token that simulates failed transferFrom operations
 * @dev Designed for testing scenarios where token transfers from other accounts fail.
 *      Inherits from ERC20Burnable and Ownable, with transferFrom always returning false.
 */
contract MockFailedTransferFrom is ERC20Burnable, Ownable {
    /*/////////////////////////////////////////////////////////////
                                ERRORS
    /////////////////////////////////////////////////////////////*/
    error DecentralizedStableCoin__AmountMustBeMoreThanZero();
    error DecentralizedStableCoin__BurnAmountExceedsBalance();
    error DecentralizedStableCoin__NotZeroAddress();

    /*/////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    /////////////////////////////////////////////////////////////*/
    constructor() ERC20("DecentralizedStableCoin", "DSC") Ownable(msg.sender) {}

    /*/////////////////////////////////////////////////////////////
                            CORE FUNCTIONS
    /////////////////////////////////////////////////////////////*/

    /**
     * @notice Burns tokens from owner's balance
     * @param _amount Amount of tokens to burn
     * @dev Only owner can burn tokens, with amount validation
     */
    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);

        if (_amount <= 0)
            revert DecentralizedStableCoin__AmountMustBeMoreThanZero();
        if (balance < _amount)
            revert DecentralizedStableCoin__BurnAmountExceedsBalance();

        super.burn(_amount);
    }

    /**
     * @notice Mints new tokens
     * @param account Recipient address
     * @param amount Amount to mint
     */
    function mint(address account, uint256 amount) public {
        _mint(account, amount);
    }

    /*/////////////////////////////////////////////////////////////
                            MOCK TRANSFER FUNCTION
    /////////////////////////////////////////////////////////////*/

    /**
     * @notice Mock transferFrom that always fails
     * @dev Overrides ERC20 transferFrom to always return false
     * @return Always returns false to simulate failed transferFrom
     */
    function transferFrom(
        address /* sender */,
        address /* recipient */,
        uint256 /* amount */
    ) public pure override returns (bool) {
        return false;
    }
}

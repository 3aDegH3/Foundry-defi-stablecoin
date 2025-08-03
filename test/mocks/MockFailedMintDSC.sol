// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MockFailedMintDSC
 * @notice Mock stablecoin contract that intentionally fails mint operations
 * @dev This contract simulates a failed mint scenario for testing purposes.
 *      It inherits from ERC20Burnable and Ownable, and always returns false on mint attempts.
 */
contract MockFailedMintDSC is ERC20Burnable, Ownable {
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
                            BURN FUNCTION
    /////////////////////////////////////////////////////////////*/

    /**
     * @notice Burns tokens from owner's balance
     * @param _amount Amount of tokens to burn
     * @dev Only callable by owner with valid amount
     */
    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);

        if (_amount <= 0) {
            revert DecentralizedStableCoin__AmountMustBeMoreThanZero();
        }
        if (balance < _amount) {
            revert DecentralizedStableCoin__BurnAmountExceedsBalance();
        }

        super.burn(_amount);
    }

    /*/////////////////////////////////////////////////////////////
                            MINT FUNCTION
    /////////////////////////////////////////////////////////////*/

    /**
     * @notice Mock mint function that always fails
     * @param _to Recipient address
     * @param _amount Amount to mint
     * @return Always returns false to simulate failed mint
     * @dev Only callable by owner, performs validation but intentionally fails
     */
    function mint(
        address _to,
        uint256 _amount
    ) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert DecentralizedStableCoin__NotZeroAddress();
        }
        if (_amount <= 0) {
            revert DecentralizedStableCoin__AmountMustBeMoreThanZero();
        }

        _mint(_to, _amount);
        return false; // Intentionally fail by returning false
    }
}

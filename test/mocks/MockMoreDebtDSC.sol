// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MockV3Aggregator} from "./MockV3Aggregator.sol";

/**
 * @title MockMoreDebtDSC
 * @notice Mock stablecoin contract that simulates debt scenarios by crashing prices
 * @dev This contract is designed for testing scenarios where burning tokens causes
 *      price crashes. It inherits from ERC20Burnable and Ownable.
 *
 * Key Features:
 * - Collateral: Exogenous
 * - Minting: Decentralized (Algorithmic)
 * - Value: Anchored (Pegged to USD)
 * - Collateral Type: Crypto
 *
 * This contract is meant to be owned by DSCEngine for testing purposes.
 */
contract MockMoreDebtDSC is ERC20Burnable, Ownable {
    /*/////////////////////////////////////////////////////////////
                                ERRORS
    /////////////////////////////////////////////////////////////*/
    error DecentralizedStableCoin__AmountMustBeMoreThanZero();
    error DecentralizedStableCoin__BurnAmountExceedsBalance();
    error DecentralizedStableCoin__NotZeroAddress();

    /*/////////////////////////////////////////////////////////////
                            STATE VARIABLES
    /////////////////////////////////////////////////////////////*/
    address private immutable i_mockAggregator;

    /*/////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    /////////////////////////////////////////////////////////////*/
    constructor(
        address mockAggregator
    ) ERC20("DecentralizedStableCoin", "DSC") Ownable(msg.sender) {
        i_mockAggregator = mockAggregator;
    }

    /*/////////////////////////////////////////////////////////////
                            BURN FUNCTION
    /////////////////////////////////////////////////////////////*/

    /**
     * @notice Burns tokens and crashes the price
     * @param _amount Amount of tokens to burn
     * @dev Only owner can burn, intentionally crashes price to 0
     */
    function burn(uint256 _amount) public override onlyOwner {
        // Crash the price before burning
        MockV3Aggregator(i_mockAggregator).updateAnswer(0);

        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0)
            revert DecentralizedStableCoin__AmountMustBeMoreThanZero();
        if (balance < _amount)
            revert DecentralizedStableCoin__BurnAmountExceedsBalance();

        super.burn(_amount);
    }

    /*/////////////////////////////////////////////////////////////
                            MINT FUNCTION
    /////////////////////////////////////////////////////////////*/

    /**
     * @notice Mints new tokens
     * @param _to Recipient address
     * @param _amount Amount to mint
     * @return bool Always returns true
     * @dev Only owner can mint, with input validation
     */
    function mint(
        address _to,
        uint256 _amount
    ) external onlyOwner returns (bool) {
        if (_to == address(0)) revert DecentralizedStableCoin__NotZeroAddress();
        if (_amount <= 0)
            revert DecentralizedStableCoin__AmountMustBeMoreThanZero();

        _mint(_to, _amount);
        return true;
    }

    /*/////////////////////////////////////////////////////////////
                            GETTER FUNCTIONS
    /////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the mock aggregator address
     * @return address The mock price aggregator address
     */
    function getMockAggregator() external view returns (address) {
        return i_mockAggregator;
    }
}

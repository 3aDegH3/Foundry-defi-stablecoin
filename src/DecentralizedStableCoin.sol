    // SPDX-License-Identifier: MIT

    // This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volatility coin

    // Layout of Contract:
    // version
    // imports
    // interfaces, libraries, contracts
    // errors
    // Type declarations
    // State variables
    // Events
    // Modifiers
    // Functions
    // Layout of Functions:
    // constructor
    // receive function (if exists)
    // fallback function (if exists)
    // external
    // public
    // internal
    // private
    // view & pure functions
    
    pragma solidity ^0.8.18;

/// @title DecentralizedStableCoin (DSC)
/// @author Sadegh Jafri
/// @notice A decentralized, overcollateralized stablecoin pegged to the USD
/// @dev This contract is intended to be governed and controlled by the DSCEngine contract
///
/// @custom:collateral ETH & BTC (exogenous collateral)
/// @custom:minting Algorithmic (minted via logic, not direct asset backing)
/// @custom:stability Pegged to USD (1 DSC ≈ 1 USD)

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract DecentralizedStableCoin is ERC20Burnable, Ownable {
    error DecentralizedStableCoin_MustMorethenZero();
    error DecentralizedStableCoin_BurnAmountExceedsBalance();
    error DecentralizedStableCoin_NotZeroAddress();

    constructor() ERC20("DecentralizedStableCoin", "DSC") Ownable(msg.sender) {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount == 0) {
            revert DecentralizedStableCoin_MustMorethenZero();
        }
        if (_amount > balance) {
            revert DecentralizedStableCoin_BurnAmountExceedsBalance();
        }
        super.burn(_amount);
    }

    function mint(address account, uint256 amount) public onlyOwner {
        if (account == address(0)) {
            revert DecentralizedStableCoin_NotZeroAddress();
        }
        if (amount == 0) {
            revert DecentralizedStableCoin_MustMorethenZero();
        }

        _mint(account, amount);
    }
}

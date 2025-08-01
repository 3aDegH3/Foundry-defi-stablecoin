// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title Decentralized Stablecoin (DSC)
/// @notice Over-collateralized USD-pegged token governed by DSCEngine
contract DecentralizedStableCoin is ERC20Burnable, Ownable {
    // Errors
    error ZeroAmount();
    error InsufficientBalance();
    error ZeroAddress();

    /// @notice Initialize DSC with name and symbol, set owner
    constructor() ERC20("Decentralized Stablecoin", "DSC") {
        transferOwnership(msg.sender);
    }

    /// @notice Mint DSC to an account
    /// @param to Recipient address (non-zero)
    /// @param amount Number of tokens to mint (>0)
    function mint(address to, uint256 amount) external onlyOwner {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        _mint(to, amount);
    }

    /// @notice Burn DSC from owner
    /// @param amount Number of tokens to burn (>0, <= balance)
    function burn(uint256 amount) public override onlyOwner {
        if (amount == 0) revert ZeroAmount();
        uint256 bal = balanceOf(msg.sender);
        if (amount > bal) revert InsufficientBalance();
        super.burn(amount);
    }
}

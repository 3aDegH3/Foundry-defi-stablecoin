// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title ERC20Mock
 * @notice Mock ERC20 token for testing purposes
 * @dev This contract extends the standard ERC20 implementation with additional test functions
 *      that expose internal methods and provide mint/burn capabilities.
 */
contract ERC20Mock is ERC20 {
    /**
     * @notice Initialize the mock token
     * @param name Token name
     * @param symbol Token symbol
     * @param initialAccount Address to receive initial supply
     * @param initialBalance Initial token amount to mint
     */
    constructor(
        string memory name,
        string memory symbol,
        address initialAccount,
        uint256 initialBalance
    ) ERC20(name, symbol) {
        _mint(initialAccount, initialBalance);
    }

    /*/////////////////////////////////////////////////////////////
                            TEST FUNCTIONS
    /////////////////////////////////////////////////////////////*/

    /**
     * @notice Mint new tokens (test function)
     * @param account Recipient address
     * @param amount Amount to mint
     */
    function mint(address account, uint256 amount) public {
        _mint(account, amount);
    }

    /**
     * @notice Burn tokens (test function)
     * @param account Address whose tokens will be burned
     * @param amount Amount to burn
     */
    function burn(address account, uint256 amount) public {
        _burn(account, amount);
    }

    /**
     * @notice Internal transfer exposed for testing
     * @param from Sender address
     * @param to Recipient address
     * @param value Transfer amount
     */
    function transferInternal(address from, address to, uint256 value) public {
        _transfer(from, to, value);
    }

    /**
     * @notice Internal approval exposed for testing
     * @param owner Token owner
     * @param spender Spender address
     * @param value Allowance amount
     */
    function approveInternal(address owner, address spender, uint256 value) public {
        _approve(owner, spender, value);
    }
}
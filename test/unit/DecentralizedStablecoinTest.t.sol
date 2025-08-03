// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

/**
 * @title DecentralizedStablecoinTest
 * @notice Test contract for DecentralizedStableCoin functionality
 * @dev Tests minting, burning, and validation logic of the stablecoin
 */
contract DecentralizedStablecoinTest is StdCheats, Test {
    DecentralizedStableCoin private dsc;

    /*/////////////////////////////////////////////////////////////
                            SETUP
    /////////////////////////////////////////////////////////////*/
    function setUp() public {
        dsc = new DecentralizedStableCoin();
    }

    /*/////////////////////////////////////////////////////////////
                            MINT TESTS
    /////////////////////////////////////////////////////////////*/

    /// @dev Test that minting zero amount reverts
    function testMustMintMoreThanZero() public {
        vm.prank(dsc.owner());
        vm.expectRevert();
        dsc.mint(address(this), 0);
    }

    /// @dev Test that minting to zero address reverts
    function testCantMintToZeroAddress() public {
        vm.startPrank(dsc.owner());
        vm.expectRevert();
        dsc.mint(address(0), 100);
        vm.stopPrank();
    }

    /*/////////////////////////////////////////////////////////////
                            BURN TESTS
    /////////////////////////////////////////////////////////////*/

    /// @dev Test that burning zero amount reverts
    function testMustBurnMoreThanZero() public {
        vm.startPrank(dsc.owner());
        dsc.mint(address(this), 100);
        vm.expectRevert();
        dsc.burn(0);
        vm.stopPrank();
    }

    /// @dev Test that burning more than balance reverts
    function testCantBurnMoreThanYouHave() public {
        vm.startPrank(dsc.owner());
        dsc.mint(address(this), 100);
        vm.expectRevert();
        dsc.burn(101);
        vm.stopPrank();
    }

    /*/////////////////////////////////////////////////////////////
                            POSITIVE TESTS
    /////////////////////////////////////////////////////////////*/

    /// @dev Test successful mint operation
    function testSuccessfulMint() public {
        uint256 mintAmount = 100;
        vm.prank(dsc.owner());
        dsc.mint(address(this), mintAmount);

        assertEq(dsc.balanceOf(address(this)), mintAmount);
    }

    /// @dev Test successful burn operation
    function testSuccessfulBurn() public {
        uint256 mintAmount = 100;
        uint256 burnAmount = 50;

        vm.startPrank(dsc.owner());
        dsc.mint(address(this), mintAmount);
        dsc.burn(burnAmount);
        vm.stopPrank();

        assertEq(dsc.balanceOf(address(this)), mintAmount - burnAmount);
    }
}

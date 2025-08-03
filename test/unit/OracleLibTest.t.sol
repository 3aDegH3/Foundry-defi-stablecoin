// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {Test} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {OracleLib, AggregatorV3Interface} from "../../src/libraries/OracleLib.sol";

/**
 * @title OracleLibTest
 * @notice Test contract for OracleLib functionality
 * @dev Tests price feed staleness checks and timeout values
 */
contract OracleLibTest is StdCheats, Test {
    using OracleLib for AggregatorV3Interface;

    /*/////////////////////////////////////////////////////////////
                            CONSTANTS
    /////////////////////////////////////////////////////////////*/
    uint8 public constant DECIMALS = 8;
    int256 public constant INITIAL_PRICE = 2000 ether;
    uint256 public constant EXPECTED_TIMEOUT = 3 hours;

    /*/////////////////////////////////////////////////////////////
                            STATE VARIABLES
    /////////////////////////////////////////////////////////////*/
    MockV3Aggregator public aggregator;

    /*/////////////////////////////////////////////////////////////
                            SETUP
    /////////////////////////////////////////////////////////////*/
    function setUp() public {
        aggregator = new MockV3Aggregator(DECIMALS, INITIAL_PRICE);
    }

    /*/////////////////////////////////////////////////////////////
                            TIMEOUT TESTS
    /////////////////////////////////////////////////////////////*/

    /// @dev Test that the timeout value is correctly returned
    function testGetTimeout() public view {
        uint256 actualTimeout = OracleLib.getTimeout(
            AggregatorV3Interface(address(aggregator))
        );
        assertEq(actualTimeout, EXPECTED_TIMEOUT);
    }

    /*/////////////////////////////////////////////////////////////
                            STALENESS TESTS
    /////////////////////////////////////////////////////////////*/

    /// @dev Test that stale price data reverts after timeout period
    function testPriceRevertsOnStaleCheck() public {
        // Fast forward past the timeout threshold
        vm.warp(block.timestamp + EXPECTED_TIMEOUT + 1);
        vm.roll(block.number + 1);

        vm.expectRevert(OracleLib.OracleLib__StalePrice.selector);
        AggregatorV3Interface(address(aggregator)).staleCheckLatestRoundData();
    }

    /// @dev Test that bad answeredInRound data reverts
    function testPriceRevertsOnBadAnsweredInRound() public {
        // Set up bad round data
        uint80 roundId = 0;
        int256 answer = 0;
        uint256 timestamp = 0;
        uint256 startedAt = 0;
        aggregator.updateRoundData(roundId, answer, timestamp, startedAt);

        vm.expectRevert(OracleLib.OracleLib__StalePrice.selector);
        AggregatorV3Interface(address(aggregator)).staleCheckLatestRoundData();
    }

    /*/////////////////////////////////////////////////////////////
                            POSITIVE TESTS
    /////////////////////////////////////////////////////////////*/

    /// @dev Test that fresh price data is accepted
    function testAcceptsFreshPriceData() public {
        // Should not revert with fresh data
        AggregatorV3Interface(address(aggregator)).staleCheckLatestRoundData();
    }
}

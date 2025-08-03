// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AggregatorV3Interface} from "lib/chainlink-brownie-contracts/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title OracleLib
 * @notice Library for verifying Chainlink Oracle data freshness
 * @dev This library provides functions to check for stale price data from Chainlink oracles.
 *      If stale data is detected, it will revert to protect the protocol from using outdated prices.
 *      The library enforces a strict timeout policy to ensure price data remains current.
 */
library OracleLib {
    /*/////////////////////////////////////////////////////////////
                                ERRORS
    /////////////////////////////////////////////////////////////*/
    error OracleLib__StalePrice();

    /*/////////////////////////////////////////////////////////////
                            CONSTANTS
    /////////////////////////////////////////////////////////////*/
    uint256 private constant TIMEOUT = 3 hours;

    /*/////////////////////////////////////////////////////////////
                            FUNCTIONS
    /////////////////////////////////////////////////////////////*/

    /**
     * @notice Checks the latest round data for staleness
     * @dev Reverts if the price data is stale based on timestamp or round ID
     * @param chainlinkFeed The Chainlink price feed to check
     * @return roundId The round ID
     * @return answer The current price
     * @return startedAt When the round started
     * @return updatedAt When the round was last updated
     * @return answeredInRound The round in which the answer was computed
     */
    function staleCheckLatestRoundData(AggregatorV3Interface chainlinkFeed)
        public
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        (roundId, answer, startedAt, updatedAt, answeredInRound) = 
            chainlinkFeed.latestRoundData();

        // Check for stale data conditions
        if (updatedAt == 0 || answeredInRound < roundId) {
            revert OracleLib__StalePrice();
        }

        // Verify data freshness
        uint256 secondsSinceUpdate = block.timestamp - updatedAt;
        if (secondsSinceUpdate > TIMEOUT) {
            revert OracleLib__StalePrice();
        }

        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }

    /**
     * @notice Returns the timeout duration for considering data stale
     * @dev This is a constant value across all feeds
     * @return The timeout duration in seconds
     */
    function getTimeout(AggregatorV3Interface /* chainlinkFeed */) 
        public 
        pure 
        returns (uint256) 
    {
        return TIMEOUT;
    }
}
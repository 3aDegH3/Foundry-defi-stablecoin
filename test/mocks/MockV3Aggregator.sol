// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

/**
 * @title MockV3Aggregator
 * @notice Simulates Chainlink Price Feed Aggregator for testing purposes
 * @dev Provides mock price data that can be manually updated for testing contracts
 * that interact with price feeds. Based on the FluxAggregator contract design.
 */
contract MockV3Aggregator {
    /*/////////////////////////////////////////////////////////////
                                CONSTANTS
    /////////////////////////////////////////////////////////////*/
    uint256 public constant version = 0;
    string public constant description = "v0.6/tests/MockV3Aggregator.sol";

    /*/////////////////////////////////////////////////////////////
                            STATE VARIABLES
    /////////////////////////////////////////////////////////////*/
    uint8 public immutable decimals;
    int256 public latestAnswer;
    uint256 public latestTimestamp;
    uint256 public latestRound;

    mapping(uint256 => int256) public getAnswer;
    mapping(uint256 => uint256) public getTimestamp;
    mapping(uint256 => uint256) private getStartedAt;

    /*/////////////////////////////////////////////////////////////
                                EVENTS
    /////////////////////////////////////////////////////////////*/
    event AnswerUpdated(
        int256 indexed current,
        uint256 indexed roundId,
        uint256 updatedAt
    );

    /*/////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    /////////////////////////////////////////////////////////////*/
    constructor(uint8 _decimals, int256 _initialAnswer) {
        decimals = _decimals;
        updateAnswer(_initialAnswer);
    }

    /*/////////////////////////////////////////////////////////////
                        DATA UPDATE FUNCTIONS
    /////////////////////////////////////////////////////////////*/

    /**
     * @notice Update the current price answer
     * @param _answer The new price answer
     */
    function updateAnswer(int256 _answer) public {
        latestAnswer = _answer;
        latestTimestamp = block.timestamp;
        latestRound++;

        getAnswer[latestRound] = _answer;
        getTimestamp[latestRound] = block.timestamp;
        getStartedAt[latestRound] = block.timestamp;

        emit AnswerUpdated(_answer, latestRound, block.timestamp);
    }

    /**
     * @notice Update round data for a specific round
     * @param _roundId The round ID to update
     * @param _answer The price answer
     * @param _timestamp The update timestamp
     * @param _startedAt The round start timestamp
     */
    function updateRoundData(
        uint80 _roundId,
        int256 _answer,
        uint256 _timestamp,
        uint256 _startedAt
    ) public {
        latestRound = _roundId;
        latestAnswer = _answer;
        latestTimestamp = _timestamp;

        getAnswer[_roundId] = _answer;
        getTimestamp[_roundId] = _timestamp;
        getStartedAt[_roundId] = _startedAt;

        emit AnswerUpdated(_answer, _roundId, _timestamp);
    }

    /*/////////////////////////////////////////////////////////////
                        DATA RETRIEVAL FUNCTIONS
    /////////////////////////////////////////////////////////////*/

    /**
     * @notice Get data for a specific round
     * @param _roundId The round ID to query
     * @return roundId The round ID
     * @return answer The price answer
     * @return startedAt The round start timestamp
     * @return updatedAt The update timestamp
     * @return answeredInRound The round ID in which the answer was computed
     */
    function getRoundData(
        uint80 _roundId
    )
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (
            _roundId,
            getAnswer[_roundId],
            getStartedAt[_roundId],
            getTimestamp[_roundId],
            _roundId
        );
    }

    /**
     * @notice Get the latest round data
     * @return roundId The latest round ID
     * @return answer The latest price answer
     * @return startedAt The latest round start timestamp
     * @return updatedAt The latest update timestamp
     * @return answeredInRound The round ID in which the answer was computed
     */
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (
            uint80(latestRound),
            getAnswer[latestRound],
            getStartedAt[latestRound],
            getTimestamp[latestRound],
            uint80(latestRound)
        );
    }
}

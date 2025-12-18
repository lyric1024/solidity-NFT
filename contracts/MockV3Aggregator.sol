// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

contract MockV3Aggregator {
    int256 public answer;
    uint256 public updatedAt;

    constructor(int256 _initialAnswer) {
        answer = _initialAnswer;
        updatedAt = block.timestamp;
    }

    function latestRoundData()
        external
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        return (0, answer, 0, updatedAt, 0);
    }

    function setAnswer(int256 _answer) external {
        answer = _answer;
        updatedAt = block.timestamp;
    }
}

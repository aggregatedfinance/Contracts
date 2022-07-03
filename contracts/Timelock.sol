// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./@openzeppelin/governance/TimelockController.sol";

contract AggregatedFinanceTimelock is TimelockController {
    constructor(uint256 minDelay, address[] memory proposers, address[] memory executors)
      TimelockController(minDelay, proposers, executors)
    {}
}

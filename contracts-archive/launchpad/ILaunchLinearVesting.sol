// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "../interfaces/ISignataRight.sol";
import "../@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ILaunchLinearVesting {
    function initialize(
        IERC20 _stakeToken,
        IERC20 _offeringToken,
        uint256 _startBlock,
        uint256 _endBlockOffset,
        uint256 _vestingBlockOffset, // Block offset between vesting distributions
        uint256 _offeringAmount,
        uint256 _raisingAmount,
        address _adminAddress,
        ISignataRight _signataRight,
        uint256 _schemaId,
        bool _requireSchemaForLaunch,
        bool _requireSchemaForDeposits
    ) external;
}

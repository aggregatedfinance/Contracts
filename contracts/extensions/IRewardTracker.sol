// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./IERC20.sol";
import "./IUniswapV2Router02.sol";

interface IRewardTracker is IERC20 {
    event RewardsDistributed(address indexed from, uint256 weiAmount);
    event RewardWithdrawn(address indexed to, uint256 weiAmount);
    event ExcludeFromRewards(address indexed account, bool excluded);
    event Claim(address indexed account, uint256 amount);
    event Compound(address indexed account, uint256 amount, uint256 tokens);
    event LogErrorString(string message);

    struct AccountInfo {
        address account;
        uint256 withdrawableRewards;
        uint256 totalRewards;
        uint256 lastClaimTime;
    }

    receive() external payable;

    function distributeRewards() external payable;

    function setBalance(address payable account, uint256 newBalance) external;

    function excludeFromRewards(address account, bool excluded) external;

    function isExcludedFromRewards(address account) external view returns (bool);

    function manualSendReward(uint256 amount, address holder) external;

    function processAccount(address payable account) external returns (bool);

    function compoundAccount(address payable account) external returns (bool);

    function withdrawableRewardOf(address account) external view returns (uint256);

    function withdrawnRewardOf(address account) external view returns (uint256);
    
    function accumulativeRewardOf(address account) external view returns (uint256);

    function getAccountInfo(address account) external view returns (address, uint256, uint256, uint256, uint256);

    function getLastClaimTime(address account) external view returns (uint256);

    function name() external pure returns (string memory);

    function symbol() external pure returns (string memory);

    function decimals() external pure returns (uint8);

    function totalSupply() external view override returns (uint256);

    function balanceOf(address account) external view override returns (uint256);

    function transfer(address, uint256) external pure override returns (bool);

    function allowance(address, address) external pure override returns (uint256);

    function approve(address, uint256) external pure override returns (bool);

    function transferFrom(address, address, uint256) external pure override returns (bool);
}
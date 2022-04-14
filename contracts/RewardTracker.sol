// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./extensions/Ownable.sol";
import "./extensions/IRewardTracker.sol";
import "./extensions/IUniswapV2Router02.sol";

contract RewardTracker is IRewardTracker, Ownable {
    address immutable UNISWAPROUTER;

    string private constant _name = "AGFI_RewardTracker";
    string private constant _symbol = "AGFI_RewardTracker";

    uint256 public lastProcessedIndex;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;

    uint256 private constant magnitude = 2**128;
    uint256 public immutable minTokenBalanceForRewards;
    uint256 private magnifiedRewardPerShare;
    uint256 public totalRewardsDistributed;
    uint256 public totalRewardsWithdrawn;

    address public immutable tokenAddress;

    mapping(address => bool) public excludedFromRewards;
    mapping(address => int256) private magnifiedRewardCorrections;
    mapping(address => uint256) private withdrawnRewards;
    mapping(address => uint256) private lastClaimTimes;

    constructor(address _tokenAddress, address _uniswapRouter) {
        minTokenBalanceForRewards = 1 * (10**9);
        tokenAddress = _tokenAddress;
        UNISWAPROUTER = _uniswapRouter;
    }

    receive() external override payable {
        distributeRewards();
    }

    function distributeRewards() public override payable {
        require(_totalSupply > 0, "Total supply invalid");
        if (msg.value > 0) {
            magnifiedRewardPerShare =
                magnifiedRewardPerShare +
                ((msg.value * magnitude) / _totalSupply);
            emit RewardsDistributed(msg.sender, msg.value);
            totalRewardsDistributed += msg.value;
        }
    }

    function setBalance(address payable account, uint256 newBalance)
        external
        override
        onlyOwner
    {
        if (excludedFromRewards[account]) {
            return;
        }
        if (newBalance >= minTokenBalanceForRewards) {
            _setBalance(account, newBalance);
        } else {
            _setBalance(account, 0);
        }
    }

    function excludeFromRewards(address account, bool excluded)
        external
        override
        onlyOwner
    {
        require(
            excludedFromRewards[account] != excluded,
            "AGFI_RewardTracker: account already set to requested state"
        );
        excludedFromRewards[account] = excluded;
        if (excluded) {
            _setBalance(account, 0);
        } else {
            uint256 newBalance = IERC20(tokenAddress).balanceOf(account);
            if (newBalance >= minTokenBalanceForRewards) {
                _setBalance(account, newBalance);
            } else {
                _setBalance(account, 0);
            }
        }
        emit ExcludeFromRewards(account, excluded);
    }

    function isExcludedFromRewards(address account) public override view returns (bool) {
        return excludedFromRewards[account];
    }

    function manualSendReward(uint256 amount, address holder)
        external
        override
        onlyOwner
    {
        uint256 contractETHBalance = address(this).balance;
        (bool success, ) = payable(holder).call{
            value: amount > 0 ? amount : contractETHBalance
        }("");
        require(success, "Manual send failed.");
    }

    function _setBalance(address account, uint256 newBalance) internal {
        uint256 currentBalance = _balances[account];
        if (newBalance > currentBalance) {
            uint256 addAmount = newBalance - currentBalance;
            _mint(account, addAmount);
        } else if (newBalance < currentBalance) {
            uint256 subAmount = currentBalance - newBalance;
            _burn(account, subAmount);
        }
    }

    function _mint(address account, uint256 amount) private {
        require(
            account != address(0),
            "AGFI_RewardTracker: mint to the zero address"
        );
        _totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);
        magnifiedRewardCorrections[account] =
            magnifiedRewardCorrections[account] -
            int256(magnifiedRewardPerShare * amount);
    }

    function _burn(address account, uint256 amount) private {
        require(
            account != address(0),
            "AGFI_RewardTracker: burn from the zero address"
        );
        uint256 accountBalance = _balances[account];
        require(
            accountBalance >= amount,
            "AGFI_RewardTracker: burn amount exceeds balance"
        );
        _balances[account] = accountBalance - amount;
        _totalSupply -= amount;
        emit Transfer(account, address(0), amount);
        magnifiedRewardCorrections[account] =
            magnifiedRewardCorrections[account] +
            int256(magnifiedRewardPerShare * amount);
    }

    function processAccount(address payable account)
        public
        override
        onlyOwner
        returns (bool)
    {
        uint256 amount = _withdrawRewardOfUser(account);
        if (amount > 0) {
            lastClaimTimes[account] = block.timestamp;
            emit Claim(account, amount);
            return true;
        }
        return false;
    }

    function _withdrawRewardOfUser(address payable account)
        private
        returns (uint256)
    {
        uint256 _withdrawableReward = withdrawableRewardOf(account);
        if (_withdrawableReward > 0) {
            withdrawnRewards[account] += _withdrawableReward;
            totalRewardsWithdrawn += _withdrawableReward;
            (bool success, ) = account.call{value: _withdrawableReward}("");
            if (!success) {
                withdrawnRewards[account] -= _withdrawableReward;
                totalRewardsWithdrawn -= _withdrawableReward;
                emit LogErrorString("Withdraw failed");
                return 0;
            }
            emit RewardWithdrawn(account, _withdrawableReward);
            return _withdrawableReward;
        }
        return 0;
    }

    function compoundAccount(address payable account)
        public
        override
        onlyOwner
        returns (bool)
    {
        (uint256 amount, uint256 tokens) = _compoundRewardOfUser(account);
        if (amount > 0) {
            lastClaimTimes[account] = block.timestamp;
            emit Compound(account, amount, tokens);
            return true;
        }
        return false;
    }

    function _compoundRewardOfUser(address payable account)
        private
        returns (uint256, uint256)
    {
        uint256 _withdrawableReward = withdrawableRewardOf(account);
        if (_withdrawableReward > 0) {
            withdrawnRewards[account] += _withdrawableReward;
            totalRewardsWithdrawn += _withdrawableReward;

            IUniswapV2Router02 uniswapV2Router = IUniswapV2Router02(
                UNISWAPROUTER
            );

            address[] memory path = new address[](2);
            path[0] = uniswapV2Router.WETH();
            path[1] = address(tokenAddress);

            bool success;
            uint256 tokens;

            uint256 initTokenBal = IERC20(tokenAddress).balanceOf(account);
            try
                uniswapV2Router
                    .swapExactETHForTokensSupportingFeeOnTransferTokens{
                    value: _withdrawableReward
                }(0, path, address(account), block.timestamp)
            {
                success = true;
                tokens = IERC20(tokenAddress).balanceOf(account) - initTokenBal;
            } catch Error(
                string memory /*err*/
            ) {
                success = false;
            }

            if (!success) {
                withdrawnRewards[account] -= _withdrawableReward;
                totalRewardsWithdrawn -= _withdrawableReward;
                emit LogErrorString("Withdraw failed");
                return (0, 0);
            }

            emit RewardWithdrawn(account, _withdrawableReward);
            return (_withdrawableReward, tokens);
        }
        return (0, 0);
    }

    function withdrawableRewardOf(address account)
        public
        override
        view
        returns (uint256)
    {
        return accumulativeRewardOf(account) - withdrawnRewards[account];
    }

    function withdrawnRewardOf(address account) public view returns (uint256) {
        return withdrawnRewards[account];
    }

    function accumulativeRewardOf(address account)
        public
        override
        view
        returns (uint256)
    {
        int256 a = int256(magnifiedRewardPerShare * balanceOf(account));
        int256 b = magnifiedRewardCorrections[account]; // this is an explicit int256 (signed)
        return uint256(a + b) / magnitude;
    }

    function getAccountInfo(address account)
        public
        override
        view
        returns (
            address,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        AccountInfo memory info;
        info.account = account;
        info.withdrawableRewards = withdrawableRewardOf(account);
        info.totalRewards = accumulativeRewardOf(account);
        info.lastClaimTime = lastClaimTimes[account];
        return (
            info.account,
            info.withdrawableRewards,
            info.totalRewards,
            info.lastClaimTime,
            totalRewardsWithdrawn
        );
    }

    function getLastClaimTime(address account) public override view returns (uint256) {
        return lastClaimTimes[account];
    }

    function name() public override pure returns (string memory) {
        return _name;
    }

    function symbol() public override pure returns (string memory) {
        return _symbol;
    }

    function decimals() public override pure returns (uint8) {
        return 9;
    }

    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    function transfer(address, uint256) public pure override returns (bool) {
        revert("AGFI_RewardTracker: method not implemented");
    }

    function allowance(address, address)
        public
        pure
        override
        returns (uint256)
    {
        revert("AGFI_RewardTracker: method not implemented");
    }

    function approve(address, uint256) public pure override returns (bool) {
        revert("AGFI_RewardTracker: method not implemented");
    }

    function transferFrom(
        address,
        address,
        uint256
    ) public pure override returns (bool) {
        revert("AGFI_RewardTracker: method not implemented");
    }
}
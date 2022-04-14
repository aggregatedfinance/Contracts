// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./extensions/IRewardTracker.sol";
import "./RewardTracker.sol";
import "./extensions/ERC20.sol";
import "./extensions/ERC20Burnable.sol";
import "./extensions/ERC20Snapshot.sol";
import "./extensions/Ownable.sol";
import "./extensions/draft-ERC20Permit.sol";
import "./extensions/ERC20Votes.sol";
import "./IUniswapV2Factory.sol";

/// @custom:security-contact team@aggregated.finance
contract AggregatedFinance is ERC20, ERC20Burnable, ERC20Snapshot, Ownable, ERC20Permit, ERC20Votes {
    address constant UNISWAPROUTER = address(0x10ED43C718714eb63d5aA57B78B54704E256024E);
    // address constant DEAD = 0x000000000000000000000000000000000000dEaD;
    // address constant ZERO = 0x0000000000000000000000000000000000000000;

    IRewardTracker public rewardTracker;
    IUniswapV2Router02 public immutable uniswapV2Router;
    address public immutable uniswapV2Pair;

    mapping (address => uint256) private _balances;
    mapping (address => mapping(address => uint256)) private _allowances;
    mapping (address => bool) private _blacklist;
    mapping (address => bool) private _isExcludedFromFees;
    mapping (address => bool) public _isExcludedMaxTransactionAmount;
    mapping (address => bool) private _isExcludedFromMaxWallet;
    mapping (address => uint256) private _holderLastTransferTimestamp; 
    mapping (address => uint256) private _holderFirstBuyTimestamp;
    mapping (address => bool) public automatedMarketMakerPairs;

    bool public limitsInEffect = true;
    bool public transferDelayEnabled = true;
    bool private swapping;
    bool private isCompounding;
    bool public taxEnabled = true;
    bool public transferTaxEnabled = false;
    bool public swapEnabled = false;
    bool public compoundingEnabled = true;

    uint256 public swapTokensAtAmount = 500000000 * (1e9); // 500 million default threshold
    uint256 public lastSwapTime;
    bool swapAllToken = true;

    uint256 public maxTransactionAmount;
    uint256 public maxWallet;
    uint256 private launchedAt;

    // Fee channel definitions. Enable each individually, and define tax rates for each.
    bool public buyFeeC1Enabled;
    bool public buyFeeC2Enabled;
    bool public buyFeeC3Enabled;
    bool public buyFeeC4Enabled;
    bool public buyFeeC5Enabled;

    bool public sellFeeC1Enabled;
    bool public sellFeeC2Enabled;
    bool public sellFeeC3Enabled;
    bool public sellFeeC4Enabled;
    bool public sellFeeC5Enabled;

    bool public c1LiquidityEnabled = true;
    bool public c2BurningEnabled = true;
    bool public c3RewardsEnabled = true;

    address public liquidityWallet;
    uint256 public tokensForC1;
    uint256 public tokensForC2;
    uint256 public tokensForC3;
    uint256 public tokensForC4;
    uint256 public tokensForC5;

    address public c1Wallet;
    address public c2Wallet;
    address public c3Wallet;
    address public c4Wallet;
    address public c5Wallet;

    uint256 public buyTotalFees;
    uint256 public buyC1Fee;
    uint256 public buyC2Fee;
    uint256 public buyC3Fee;
    uint256 public buyC4Fee;
    uint256 public buyC5Fee;
 
    uint256 public sellTotalFees;
    uint256 public sellC1Fee;
    uint256 public sellC2Fee;
    uint256 public sellC3Fee;
    uint256 public sellC4Fee;
    uint256 public sellC5Fee;

    event LogErrorString(string message);
    event SwapEnabled(bool enabled);
    event TaxEnabled(bool enabled);
    event TransferTaxEnabled(bool enabled);
    event CompoundingEnabled(bool enabled);
    event MaxTxnUpdated(uint256 amount);
    event MaxWalletUpdated(uint256 amount);
    event ChangeSwapTokensAtAmount(uint256 amount);
    event LimitsReinstated();
    event LimitsRemoved();
    event C1LiquidityModified(bool enabled);
    event C2BurningModified(bool enabled);
    event C3RewardsModified(bool enabled);
    event ChannelWalletsModified(address indexed newAddress, uint8 idx);

    event BoughtEarly(address indexed sniper);
    event ExcludeFromFees(address indexed account, bool isExcluded);
    event ExcludeFromMaxTransaction(address indexed account, bool isExcluded);
    event ExcludeFromMaxWallet(address account);
    event UpdateUniswapV2Router(address indexed newAddress, address indexed oldAddress);
    event SetAutomatedMarketMakerPair(address indexed pair, bool indexed value);
    event FeesUpdated();
    event SendChannel1(uint256 tokensSwapped, uint256 amount);
    event SendChannel2(uint256 tokensSwapped, uint256 amount);
    event SendChannel3(uint256 tokensSwapped, uint256 amount);
    event SendChannel4(uint256 tokensSwapped, uint256 amount);
    event SendChannel5(uint256 tokensSwapped, uint256 amount);
    event TokensBurned(uint256 amountBurned);
    event SwapAndAddLiquidity(
        uint256 tokensSwapped,
        uint256 nativeReceived,
        uint256 tokensIntoLiquidity
    );

    constructor()
        ERC20("Aggregated Finance", "AGFI")
        ERC20Permit("Aggregated Finance")
    {

        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(UNISWAPROUTER);
        excludeFromMaxTransaction(address(_uniswapV2Router), true);
        uniswapV2Router = _uniswapV2Router;

        rewardTracker = new RewardTracker(address(this), UNISWAPROUTER);

        rewardTracker.excludeFromRewards(address(rewardTracker), true);
        rewardTracker.excludeFromRewards(address(this), true);
        rewardTracker.excludeFromRewards(owner(), true);
        rewardTracker.excludeFromRewards(address(_uniswapV2Router), true);

        uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory()).createPair(address(this), _uniswapV2Router.WETH());
        excludeFromMaxTransaction(address(uniswapV2Pair), true);
        _setAutomatedMarketMakerPair(address(uniswapV2Pair), true);

        excludeFromFees(owner(), true);
        excludeFromFees(address(this), true);
        excludeFromFees(address(0xdead), true);

        excludeFromMaxTransaction(owner(), true);
        excludeFromMaxTransaction(address(this), true);
        excludeFromMaxTransaction(address(0xdead), true);

        excludeFromMaxWallet(owner(), true);
        excludeFromMaxWallet(address(this), true);
        excludeFromMaxWallet(address(rewardTracker), true);

        _mint(msg.sender, 1000000000000 * (10 ** 9));
    }

    receive() external payable {}

    function decimals() override public pure returns (uint8) {
        return 9;
    }

    function excludeFromMaxTransaction(address account, bool excluded) public onlyOwner {
        _isExcludedMaxTransactionAmount[account] = excluded;
        emit ExcludeFromMaxTransaction(account, excluded);
    }

    function excludeFromFees(address account, bool excluded) public onlyOwner {
        _isExcludedFromFees[account] = excluded;
        emit ExcludeFromFees(account, excluded);
    }

    function excludeFromMaxWallet(address account, bool excluded) public onlyOwner {
        _isExcludedFromMaxWallet[account] = excluded;
        emit ExcludeFromMaxWallet(account);
    }

    function isExcludedFromMaxWallet(address account) public view returns (bool) {
        return _isExcludedFromMaxWallet[account];
    }

    function isExcludedFromFees(address account) public view returns(bool) {
        return _isExcludedFromFees[account];
    }

    function blacklistAccount(address account, bool isBlacklisted) public onlyOwner {
        _blacklist[account] = isBlacklisted;
    }

    function setAutomatedMarketMakerPair(address pair, bool enabled) public onlyOwner {
        require(pair != uniswapV2Pair, "The pair cannot be removed from automatedMarketMakerPairs");
        _setAutomatedMarketMakerPair(pair, enabled);
    }

    function _setAutomatedMarketMakerPair(address pair, bool enabled) private {
        automatedMarketMakerPairs[pair] = enabled;
        emit SetAutomatedMarketMakerPair(pair, enabled);
    }

    function claim() public {
        rewardTracker.processAccount(payable(_msgSender()));
    }

    function compound() public {
        require(compoundingEnabled, "AGFI: compounding is not enabled");
        isCompounding = true;
        rewardTracker.compoundAccount(payable(_msgSender()));
        isCompounding = false;
    }

    function withdrawableRewardOf(address account)
        public
        view
        returns (uint256)
    {
        return rewardTracker.withdrawableRewardOf(account);
    }

    function withdrawnRewardOf(address account) public view returns (uint256) {
        return rewardTracker.withdrawnRewardOf(account);
    }

    function accumulativeRewardOf(address account) public view returns (uint256) {
        return rewardTracker.accumulativeRewardOf(account);
    }

    function getAccountInfo(address account)
        public
        view
        returns (
            address,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        return rewardTracker.getAccountInfo(account);
    }

    function enableTrading() external onlyOwner {
        swapEnabled = true;
        launchedAt = block.number;
    }

    function getLastClaimTime(address account) public view returns (uint256) {
        return rewardTracker.getLastClaimTime(account);
    }

    function setCompoundingEnabled(bool enabled) external onlyOwner {
        compoundingEnabled = enabled;
        emit CompoundingEnabled(enabled);
    }

    function setSwapTokensAtAmount(uint256 amount) external onlyOwner {
        swapTokensAtAmount = amount;
        emit ChangeSwapTokensAtAmount(amount);
    }

    function setSwapEnabled(bool enabled) external onlyOwner {
        swapEnabled = enabled;
        emit SwapEnabled(enabled);
    }

    function setTaxEnabled(bool enabled) external onlyOwner {
        taxEnabled = enabled;
        emit TaxEnabled(enabled);
    }

    function setTransferTaxEnabled(bool enabled) external onlyOwner {
        transferTaxEnabled = enabled;
        emit TransferTaxEnabled(enabled);
    }

    function updateMaxTxnAmount(uint256 newNum) external onlyOwner {
        maxTransactionAmount = newNum * (1e9);
        emit MaxTxnUpdated(newNum);
    }

    function updateMaxWalletAmount(uint256 newNum) external onlyOwner {
        maxWallet = newNum * (1e9);
        emit MaxWalletUpdated(newNum);
    }

    function removeLimits() external onlyOwner {
        limitsInEffect = false;
        emit LimitsRemoved();
    }

    function reinstateLimits() external onlyOwner {
        limitsInEffect = true;
        emit LimitsReinstated();
    }

    function modifyC1Liquidity(bool enabled) external onlyOwner {
        c1LiquidityEnabled = enabled;
        emit C1LiquidityModified(enabled);
    }

    function modifyC2Burning(bool enabled) external onlyOwner {
        c2BurningEnabled = enabled;
        emit C2BurningModified(enabled);
    }

    function modifyC3Rewards(bool enabled) external onlyOwner {
        c3RewardsEnabled = enabled;
        emit C3RewardsModified(enabled);
    }

    function modifyChannelWallet(address newAddress, uint8 idx) external onlyOwner {        
        if (idx == 1) {
            c1Wallet = newAddress;
        } else if (idx == 2) {
            c2Wallet = newAddress;
        } else if (idx == 3) {
            c3Wallet = newAddress;
        } else if (idx == 4) {
            c4Wallet = newAddress;
        } else if (idx == 5) {
            c5Wallet = newAddress;
        }

        emit ChannelWalletsModified(newAddress, idx);
    }

    // disable Transfer delay - cannot be reenabled
    function disableTransferDelay() external onlyOwner returns (bool) {
        transferDelayEnabled = false;
        // not bothering with an event emission, as it's only called once
        return true;
    }

    function updateBuyFees(
        bool _enableC1,
        uint256 _c1Fee,
        bool _enableC2,
        uint256 _c2Fee,
        bool _enableC3,
        uint256 _c3Fee,
        bool _enableC4,
        uint256 _c4Fee,
        bool _enableC5,
        uint256 _c5Fee
    ) external onlyOwner {
        buyFeeC1Enabled = _enableC1;
        buyC1Fee = _c1Fee;
        buyFeeC2Enabled = _enableC2;
        buyC2Fee = _c2Fee;
        buyFeeC3Enabled = _enableC3;
        buyC3Fee = _c3Fee;
        buyFeeC4Enabled = _enableC4;
        buyC4Fee = _c4Fee;
        buyFeeC5Enabled = _enableC5;
        buyC5Fee = _c5Fee;

        buyTotalFees = _c1Fee + _c2Fee + _c3Fee + _c4Fee + _c5Fee;
        require(buyTotalFees <= 30, "Must keep fees at 30% or less");
        emit FeesUpdated();
    }
 
    function updateSellFees(
        bool _enableC1,
        uint256 _c1Fee,
        bool _enableC2,
        uint256 _c2Fee,
        bool _enableC3,
        uint256 _c3Fee,
        bool _enableC4,
        uint256 _c4Fee,
        bool _enableC5,
        uint256 _c5Fee
    ) external onlyOwner {
        sellFeeC1Enabled = _enableC1;
        sellC1Fee = _c1Fee;
        sellFeeC2Enabled = _enableC2;
        sellC2Fee = _c2Fee;
        sellFeeC3Enabled = _enableC3;
        sellC3Fee = _c3Fee;
        sellFeeC4Enabled = _enableC4;
        sellC4Fee = _c4Fee;
        sellFeeC5Enabled = _enableC5;
        sellC5Fee = _c5Fee;

        sellTotalFees = _c1Fee + _c2Fee + _c3Fee + _c4Fee + _c5Fee;
        require(sellTotalFees <= 30, "Must keep fees at 30% or less");
        emit FeesUpdated();
    }

    function snapshot() public onlyOwner {
        _snapshot();
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override(ERC20, ERC20Snapshot) {
        super._beforeTokenTransfer(from, to, amount);
    }

    function _afterTokenTransfer(address from, address to, uint256 amount) internal override(ERC20, ERC20Votes) {
        super._afterTokenTransfer(from, to, amount);
    }

    function _mint(address to, uint256 amount) internal override(ERC20, ERC20Votes) {
        super._mint(to, amount);
    }

    function _burn(address account, uint256 amount) internal override(ERC20, ERC20Votes) {
        super._burn(account, amount);
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(from != address(0), "_transfer: transfer from the zero address");
        require(to != address(0), "_transfer: transfer to the zero address");
        require(!_blacklist[from], "_transfer: Sender is blacklisted");
        require(!_blacklist[to], "_transfer: Recipient is blacklisted");

         if (amount == 0) {
            super._transfer(from, to, 0);
            return;
        }
 
        if (limitsInEffect) {
            if (
                from != owner() &&
                to != owner() &&
                to != address(0) &&
                to != address(0xdead) &&
                !swapping
            ) {
                if (!swapEnabled) {
                    require(_isExcludedFromFees[from] || _isExcludedFromFees[to], "Trading is not active.");
                }
 
                // at launch if the transfer delay is enabled, ensure the block timestamps for purchasers is set -- during launch.  
                if (transferDelayEnabled){
                    if (to != owner() && to != address(uniswapV2Router) && to != address(uniswapV2Pair)) {
                        require(_holderLastTransferTimestamp[tx.origin] < block.number, "_transfer: Transfer Delay enabled.  Only one purchase per block allowed.");
                        _holderLastTransferTimestamp[tx.origin] = block.number;
                    }
                }
 
                //when buy
                if (automatedMarketMakerPairs[from] && !_isExcludedMaxTransactionAmount[to]) {
                        require(amount <= maxTransactionAmount, "Buy transfer amount exceeds the maxTransactionAmount.");
                        require(amount + balanceOf(to) <= maxWallet, "Max wallet exceeded");
                }
 
                //when sell
                else if (automatedMarketMakerPairs[to] && !_isExcludedMaxTransactionAmount[from]) {
                        require(amount <= maxTransactionAmount, "Sell transfer amount exceeds the maxTransactionAmount.");
                }
                else if(!_isExcludedMaxTransactionAmount[to]){
                    require(amount + balanceOf(to) <= maxWallet, "Max wallet exceeded");
                }
            }
        }
        
        _beforeTokenTransfer(from, to, amount);
 
        // anti bot logic
        if (block.number <= (launchedAt + 1) && 
            to != uniswapV2Pair && 
            to != address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D)
        ) {
            _blacklist[to] = true;
            emit BoughtEarly(to);
        }
 
        uint256 contractTokenBalance = balanceOf(address(this));

        bool canSwap = contractTokenBalance >= swapTokensAtAmount;

        if (
            swapEnabled && // True
            canSwap && // true
            !swapping && // swapping=false !false true
            !automatedMarketMakerPairs[from] && // no swap on remove liquidity step 1 or DEX buy
            from != address(uniswapV2Router) && // no swap on remove liquidity step 2
            from != owner() &&
            to != owner()
        ) {
            swapping = true;

            if (!swapAllToken) {
                contractTokenBalance = swapTokensAtAmount;
            }
            _executeSwap(contractTokenBalance, address(this).balance);

            lastSwapTime = block.timestamp;
            swapping = false;
        }

        bool takeFee;

        if (
            from == address(uniswapV2Pair) ||
            to == address(uniswapV2Pair) ||
            automatedMarketMakerPairs[to] ||
            automatedMarketMakerPairs[from] ||
            transferTaxEnabled
        ) {
            takeFee = true;
        }

        if (_isExcludedFromFees[from] || _isExcludedFromFees[to]) {
            takeFee = false;
        }

        if (swapping || isCompounding || !taxEnabled) {
            takeFee = false;
        }
 
        // only take fees on buys/sells, do not take on wallet transfers
        if (takeFee) {
            uint256 fees;
            // on sell
            if (automatedMarketMakerPairs[to] && sellTotalFees > 0) {
                fees = (amount * sellTotalFees) / 100;
                if (sellFeeC1Enabled) {
                    tokensForC1 += fees * sellC1Fee / sellTotalFees;
                }
                if (sellFeeC2Enabled) {
                    tokensForC2 += fees * sellC2Fee / sellTotalFees;
                }
                if (sellFeeC3Enabled) {
                    tokensForC3 += fees * sellC3Fee / sellTotalFees;
                }
                if (sellFeeC4Enabled) {
                    tokensForC4 += fees * sellC4Fee / sellTotalFees;
                }
                if (sellFeeC5Enabled) {
                    tokensForC5 += fees * sellC5Fee / sellTotalFees;
                }
            // on buy
            } else if (automatedMarketMakerPairs[from] && buyTotalFees > 0) {
                fees = (amount * buyTotalFees) / 100;

                if (buyFeeC1Enabled) {
                    tokensForC1 += fees * buyC1Fee / buyTotalFees;
                }
                if (buyFeeC2Enabled) {
                    tokensForC2 += fees * buyC1Fee / buyTotalFees;
                }
                if (buyFeeC3Enabled) {
                    tokensForC3 += fees * buyC1Fee / buyTotalFees;
                }
                if (buyFeeC4Enabled) {
                    tokensForC4 += fees * buyC1Fee / buyTotalFees;
                }
                if (buyFeeC5Enabled) {
                    tokensForC5 += fees * buyC1Fee / buyTotalFees;
                }
            }
 
            if (fees > 0){    
                super._transfer(from, address(this), fees);
            }
 
            amount -= fees;
        }
 
        super._transfer(from, to, amount);

        rewardTracker.setBalance(payable(from), balanceOf(from));
        rewardTracker.setBalance(payable(to), balanceOf(to));

        _afterTokenTransfer(from, to, amount);
    }

    function _executeSwap(uint256 tokens, uint256 native) private {
        if (tokens <= 0) {
            return;
        }

        uint256 swapTokensTotal;
        // channel 1 (liquidity, then treasury)
        // if c1 add liquidity enabled, swap for liquidity and send to c1 wallet
        // otherwise just send to c1 wallet
        uint256 swapTokensC1;
        uint256 addTokensC1;
        if (address(c1Wallet) != address(0)) {

            if (c1LiquidityEnabled) {
                swapTokensC1 = tokensForC1 / 2; // halve it as half has to go to liquidity
                addTokensC1 = tokensForC1 - swapTokensC1;
            } else {
                swapTokensC1 = tokensForC1;
            }
            swapTokensTotal += swapTokensC1;
        }

        // channel 2 (burning)
        // if c2 burn enabled, burn the tokens
        // otherwise just send to the c2 wallet
        uint256 swapTokensC2;
        if (address(c2Wallet) != address(0)) {
            if (c2BurningEnabled) {
                // burn them now, don't add to the swap amount
                _burn(address(this), tokensForC2);
                emit TokensBurned(tokensForC2);
            } else {
                swapTokensC2 = tokensForC2;
                swapTokensTotal += swapTokensC2;
            }
        }

        // channel 3 (rewards)
        // if c3 rewards enabled, send to rewards wallet
        // otherwise just send to the c3 address
        uint256 swapTokensC3;
        if (address(c3Wallet) != address(0)) {
            if (c3RewardsEnabled) {
                // just send the tokens now
                super._transfer(address(this), c3Wallet, tokensForC3);
                emit SendChannel3(swapTokensC3, swapTokensC3);
            } else {
                swapTokensC3 = tokensForC3;
                swapTokensTotal += swapTokensC3;
            }
        }

        // channel 4 (staking rewards)
        // just send to the c4 address
        uint256 swapTokensC4;
        if (address(c4Wallet) != address(0)) {
            swapTokensC4 = tokensForC4;
            swapTokensTotal += swapTokensC4;
        }

        // channel 5 (operations funds)
        // just send to the c5 address
        uint256 swapTokensC5;
        if (address(c5Wallet) != address(0)) {
            swapTokensC5 = tokensForC5;
            swapTokensTotal += swapTokensC5;
        }

        
        uint256 initNativeBal = address(this).balance;
        swapTokensForNative(swapTokensTotal);
        uint256 nativeSwapped = (address(this).balance - initNativeBal) + native;

        // reset the saved channel amounts
        tokensForC1 = 0;
        tokensForC2 = 0;
        tokensForC3 = 0;
        tokensForC4 = 0;
        tokensForC5 = 0;

        // set the eth conversion amounts
        uint256 nativeForC2 = (nativeSwapped * swapTokensC2) / swapTokensTotal;
        uint256 nativeForC3 = (nativeSwapped * swapTokensC3) / swapTokensTotal;
        uint256 nativeForC4 = (nativeSwapped * swapTokensC4) / swapTokensTotal;
        uint256 nativeForC5 = (nativeSwapped * swapTokensC5) / swapTokensTotal;
        uint256 nativeForC1;

        if (c1LiquidityEnabled) {
            nativeForC1 = nativeSwapped - nativeForC2 - nativeForC3 - nativeForC4 - nativeForC5;
        } else {
            nativeForC1 = (nativeSwapped * swapTokensC1) / swapTokensTotal;
        }

        if (nativeForC1 > 0 && !c1LiquidityEnabled) {
            (bool success, ) = payable(c1Wallet).call{
                value: nativeForC1
            }("");
            if (success) {
                emit SendChannel1(swapTokensC1, nativeForC1);
            } else {
                emit LogErrorString("Wallet failed to receive channel 1 tokens");
            }
        }
        if (nativeForC2 > 0 && !c2BurningEnabled) {
            (bool success, ) = payable(c2Wallet).call{
                value: nativeForC2
            }("");
            if (success) {
                emit SendChannel2(swapTokensC2, nativeForC2);
            } else {
                emit LogErrorString("Wallet failed to receive channel 2 tokens");
            }
        }
        if (nativeForC3 > 0 && !c3RewardsEnabled) {
            (bool success, ) = payable(c3Wallet).call{
                value: nativeForC3
            }("");
            if (success) {
                emit SendChannel3(swapTokensC3, nativeForC3);
            } else {
                emit LogErrorString("Wallet failed to receive channel 3 tokens");
            }
        }
        if (nativeForC4 > 0) {
            (bool success, ) = payable(c4Wallet).call{
                value: nativeForC4
            }("");
            if (success) {
                emit SendChannel4(swapTokensC4, nativeForC4);
            } else {
                emit LogErrorString("Wallet failed to receive channel 4 tokens");
            }
        }
        if (nativeForC5 > 0) {
            (bool success, ) = payable(c5Wallet).call{
                value: nativeForC5
            }("");
            if (success) {
                emit SendChannel5(swapTokensC5, nativeForC5);
            } else {
                emit LogErrorString("Wallet failed to receive channel 5 tokens");
            }
        }
        if (addTokensC1 > 0 && c1LiquidityEnabled) {
            addLiquidity(addTokensC1, nativeForC1);
            emit SwapAndAddLiquidity(
                swapTokensC1,
                nativeForC1,
                addTokensC1
            );
        }
    }

    // swap the tokens back to ETH
    function swapTokensForNative(uint256 tokens) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();
        _approve(address(this), address(uniswapV2Router), tokens);
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokens,
            0, // accept any amount of native
            path,
            address(this),
            block.timestamp
        );
    }

    function addLiquidity(uint256 tokens, uint256 native) private {
        _approve(address(this), address(uniswapV2Router), tokens);
        uniswapV2Router.addLiquidityETH{value: native}(
            address(this),
            tokens,
            0, // slippage unavoidable
            0, // slippage unavoidable
            liquidityWallet,
            block.timestamp
        );
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./interfaces/IUniswapV2Router02.sol";
import "./interfaces/IUniswapV2Factory.sol";

contract Momento is IERC20Metadata, Ownable {
    struct User {
        uint256 buy;
        uint256 sell;
    }

    address public marketingAddress = 0x07c013fba1bB7CA3a3eb1dc0666De5bB0bF8D7d9;
    address public teamAddress = 0x6aEC062a363e4cFCC6A369Df2981Dc66cf4Bb8Ed;
    address public constant deadAddress = 0x000000000000000000000000000000000000dEaD;

    uint256 private _rTeamLock;

    uint256 public teamUnlockTime;
    uint8 public teamUnlockCount;
    uint256 private _rTeamUnlockTokenCount;

    uint256 private _rBurnLock;

    uint256 private _rBuyBackTokenCount;
    uint256 private _buyBackETHCount;

    mapping(address => User) private _cooldown;

    mapping (address => uint256) private _rOwned;
    mapping (address => uint256) private _tOwned;
    mapping (address => mapping (address => uint256)) private _allowances;

    mapping (address => bool) private _isUniswapV2Pair;

    mapping (address => bool) private _isExcluded;
    address[] private _excluded;

    uint256 private _holderCount;
    uint256 private _lastMaxHolderCount = 99;
   
    uint256 private constant MAX = ~uint256(0);
    uint256 private _tTotal = 1000000000000 * 10**9;
    uint256 private _rTotal = (MAX - (MAX % _tTotal));
    uint256 private _tFeeTotal;

    string private _name = "Momento";
    string private _symbol = "MOMENTO";
    
    uint256 public _taxFee = 4;
    uint256 private _previousTaxFee = _taxFee;
    
    uint256 public _liquidityFee = 3;
    uint256 private _previousLiquidityFee = _liquidityFee;

    uint256 public _marketingFee = 1;
    uint256 private _previousMarketingFee = _marketingFee;
    
    uint256 public _buyBackFee = 4;
    uint256 private _previousBuyBackFee = _buyBackFee;

    IUniswapV2Router02 public immutable uniswapV2Router;
    address public uniswapV2Pair;
    
    bool inSwapAndLiquify;
    bool public swapAndLiquifyEnabled = true;
    
    uint256 public _maxTxAmount = 5000000000 * 10**9;
    uint256 private numTokensSellToAddToLiquidity = 500000000 * 10**9;
    
    event MinTokensBeforeSwapUpdated(uint256 minTokensBeforeSwap);
    event SwapAndLiquifyEnabledUpdated(bool enabled);
    event SwapAndLiquify(uint256 tokensSwapped, uint256 ethReceived, uint256 tokensIntoLiqudity);
    event SwapETHForTokens(uint256 amountIn, address[] path);
    
    modifier lockTheSwap {
        inSwapAndLiquify = true;
        _;
        inSwapAndLiquify = false;
    }
    
    constructor() {
        // 1% of total reflection supply
        uint256 onePercentR = _rTotal / 100;
        // 1% of total t supply
        uint256 onePercentT = _tTotal / 100;

        // add 60% of tokens to owner(for adding to liquidity pool)
        _rOwned[_msgSender()] = onePercentR * 60;
        // add 5% of tokens to marketing address
        _rOwned[marketingAddress] = onePercentR * 5;
        // lock 10% of tokens for burning further
        _rBurnLock = onePercentR * 10;
        // lock 3% of tokens for team for 6 months and vested over 18 months
        _rTeamLock = onePercentR * 3;

        _rTeamUnlockTokenCount = _rTeamLock / 18;

        teamUnlockTime = block.timestamp + 180 days;

        // burning 22% of totalsupply
        _rTotal = onePercentR * 78;
        _tTotal = onePercentT * 78;


        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        // Create a uniswap pair for this new token
        uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory()).createPair(address(this), _uniswapV2Router.WETH());

        // set the rest of the contract variables
        uniswapV2Router = _uniswapV2Router;

        _holderCount = 3;
        
        _isUniswapV2Pair[uniswapV2Pair] = true;

        emit Transfer(address(0), _msgSender(), onePercentT * 60);
        emit Transfer(address(0), marketingAddress, onePercentT * 5);
        emit Transfer(deadAddress, address(0), onePercentT * 22);
    }

    function unlockTeam() public {
        require(_msgSender() == teamAddress, "Function can be called only with team address");
        require(block.timestamp > teamUnlockTime, "Fucntion can be called only if teamUnlockTime has passed");
        require(teamUnlockCount < 18, "You are already unlocked all tokens");
        uint256 difference = block.timestamp - teamUnlockTime;
        uint256 monthCount = difference / 30 days;
        uint8 remainingMonths = 18 - teamUnlockCount;
        if (monthCount > remainingMonths) monthCount = remainingMonths;
        uint amountToTransfer = monthCount * _rTeamUnlockTokenCount;
        _rOwned[teamAddress] += amountToTransfer;
        teamUnlockCount += uint8(monthCount);
        teamUnlockTime += monthCount * 30 days;
        emit Transfer(address(0), teamAddress, tokenFromReflection(amountToTransfer));
    }

    function setMarketingAddress(address _markeingAddress) public onlyOwner {
        marketingAddress = _markeingAddress;
    }

    function setTeamAddress(address _teamAddress) public onlyOwner {
        teamAddress = _teamAddress;
    }

    function _burnTenPercent() private {
        if (_rBurnLock != 0) {
            uint256 rBurnCount = _rBurnLock / 10;
            if (rBurnCount == 0) {
                rBurnCount = _rBurnLock;
            }
            _rBurnLock -= rBurnCount;
            uint256 tBurnCount = tokenFromReflection(rBurnCount);
            _tTotal -= tBurnCount;
            _rTotal -= rBurnCount;
            emit Transfer(deadAddress, address(0), tBurnCount);
        }
    }

    function name() public view override returns (string memory) {
        return _name;
    }

    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    function decimals() public pure override returns (uint8) {
        return 9;
    }

    function totalSupply() public view override returns (uint256) {
        return _tTotal;
    }

    function balanceOf(address account) public view override returns (uint256) {
        if (_isExcluded[account]) return _tOwned[account];
        return tokenFromReflection(_rOwned[account]);
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), _allowances[sender][_msgSender()] - amount);
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender] + addedValue);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender] - subtractedValue);
        return true;
    }

    function isExcludedFromReward(address account) public view returns (bool) {
        return _isExcluded[account];
    }

    function totalFees() public view returns (uint256) {
        return _tFeeTotal;
    }

    function deliver(uint256 tAmount) public {
        address sender = _msgSender();
        require(!_isExcluded[sender], "Excluded addresses cannot call this function");
        uint256 rAmount = tAmount * _getRate();
        _rOwned[sender] -= rAmount;
        _rTotal -= rAmount;
        _tFeeTotal += tAmount;
    }

    function reflectionFromToken(uint256 tAmount, bool deductTransferFee) public view returns(uint256) {
        require(tAmount <= _tTotal, "Amount must be less than supply");
        uint256 currentRate = _getRate();
        if (!deductTransferFee) {
            return tAmount * currentRate;
        } else {
            uint256[5] memory tValues = _getTValues(tAmount);
            return tValues[0] * currentRate;
        }
    }

    function tokenFromReflection(uint256 rAmount) public view returns(uint256) {
        require(rAmount <= _rTotal, "Amount must be less than total reflections");
        uint256 currentRate = _getRate();
        return rAmount / currentRate;
    }

    function excludeFromReward(address account) public onlyOwner() {
        // require(account != 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D, 'We can not exclude Uniswap router.');
        require(!_isExcluded[account], "Account is already excluded");
        require(account != marketingAddress, "marketingAddress cannot be excluded");
        require(account != deadAddress, "deadAddress cannot be excluded");
        if(_rOwned[account] > 0) {
            _tOwned[account] = tokenFromReflection(_rOwned[account]);
        }
        _isExcluded[account] = true;
        _excluded.push(account);
    }

    function includeInReward(address account) external onlyOwner() {
        require(_isExcluded[account], "Account is already excluded");
        for (uint256 i = 0; i < _excluded.length; i++) {
            if (_excluded[i] == account) {
                _excluded[i] = _excluded[_excluded.length - 1];
                _tOwned[account] = 0;
                _isExcluded[account] = false;
                _excluded.pop();
                break;
            }
        }
    }

    function addUniswapV2PairAddress(address account) public onlyOwner {
        _isUniswapV2Pair[account] = true;
    }
    
    function removeUniswapV2PairAddress(address account) public onlyOwner {
        _isUniswapV2Pair[account] = false;
    }
    
    function setTaxFeePercent(uint256 taxFee) external onlyOwner() {
        _taxFee = taxFee;
    }
    
    function setLiquidityFeePercent(uint256 liquidityFee) external onlyOwner() {
        _liquidityFee = liquidityFee;
    }

    function setMaxTxPercent(uint256 maxTxPercent) external onlyOwner() {
        _maxTxAmount = _tTotal * maxTxPercent / 100;
    }

    function setSwapAndLiquifyEnabled(bool _enabled) public onlyOwner {
        swapAndLiquifyEnabled = _enabled;
        emit SwapAndLiquifyEnabledUpdated(_enabled);
    }
    
    //to recieve ETH from uniswapV2Router when swaping
    receive() external payable {}

    function _reflectFee(uint256 tFee, uint256 rFee) private {
        _rTotal -= rFee;
        _tFeeTotal += tFee;
    }

    function _getTValues(uint256 tAmount) private view returns (uint256[5] memory) {
        uint256[5] memory tValues;
        tValues[1] = calculateTaxFee(tAmount); // tFee
        tValues[2] = calculateLiquidityFee(tAmount); // tLiquidity
        tValues[3] = calculateMarketingFee(tAmount); // tMarketing
        tValues[4] = calculateBuyBackFee(tAmount); // tBuyBack
        tValues[0] = tAmount - tValues[1] - tValues[2] - tValues[3] - tValues[4]; // tTrasnferAmount
        return tValues;
    }

    function _getRate() private view returns(uint256) {
        (uint256 rSupply, uint256 tSupply) = _getCurrentSupply();
        return rSupply / tSupply;
    }

    function _getCurrentSupply() private view returns(uint256, uint256) {
        uint256 rSupply = _rTotal;
        uint256 tSupply = _tTotal;
        for (uint256 i = 0; i < _excluded.length; i++) {
            if (_rOwned[_excluded[i]] > rSupply || _tOwned[_excluded[i]] > tSupply) return (_rTotal, _tTotal);
            rSupply -= _rOwned[_excluded[i]];
            tSupply -= _tOwned[_excluded[i]];
        }
        if (rSupply < _rTotal / _tTotal) return (_rTotal, _tTotal);
        return (rSupply, tSupply);
    }
    
    function _takeLiquidity(uint256 tLiquidity, uint256 rLiquidity) private {
        _rOwned[address(this)] += rLiquidity;
        if(_isExcluded[address(this)]) {
            _tOwned[address(this)] += tLiquidity;
        }
    }
    
    function calculateTaxFee(uint256 _amount) private view returns (uint256) {
        return _amount * _taxFee / 100;
    }

    function calculateLiquidityFee(uint256 _amount) private view returns (uint256) {
        return _amount * _liquidityFee / 100;
    }

    function calculateMarketingFee(uint256 _amount) private view returns(uint256) {
        return _amount * _marketingFee / 100;
    }

    function calculateBuyBackFee(uint256 _amount) private view returns(uint256) {
        return _amount * _buyBackFee / 100;
    }
    
    function removeAllFee() private {
        if(_taxFee == 0 && _liquidityFee == 0 && _marketingFee == 0 && _buyBackFee == 0) return;
        
        _previousTaxFee = _taxFee;
        _previousLiquidityFee = _liquidityFee;
        _previousMarketingFee = _marketingFee;
        _previousBuyBackFee = _buyBackFee;
        
        _taxFee = 0;
        _liquidityFee = 0;
        _marketingFee = 0;
        _buyBackFee = 0;
    }
    
    function restoreAllFee() private {
        _taxFee = _previousTaxFee;
        _liquidityFee = _previousLiquidityFee;
        _marketingFee = _previousMarketingFee;
        _buyBackFee = _previousBuyBackFee;
    }
    
    function isUniswapV2PairAddress(address account) public view returns(bool) {
        return _isUniswapV2Pair[account];
    }

    function _approve(address owner, address spender, uint256 amount) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _transfer(address from, address to, uint256 amount) private {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");
        if(from != owner() && to != owner()) {
            require(amount <= _maxTxAmount, "Transfer amount exceeds the maxTxAmount.");
        }


        // if balance of recipient is 0 then holder count is increased
        // and if sender balance is equal to amount then holder count decreased
        if (balanceOf(to) == 0) _holderCount++;
        if (balanceOf(from) == amount) _holderCount--;

        // is the token balance of this contract address over the min number of
        // tokens that we need to initiate a swap + liquidity lock?
        // also, don't get caught in a circular liquidity event.
        // also, don't swap & liquify if sender is uniswap pair.
        uint256 contractTokenBalance = balanceOf(address(this));
        
        if (contractTokenBalance >= _maxTxAmount) {
            contractTokenBalance = _maxTxAmount;
        }
        
        bool overMinTokenBalance = contractTokenBalance >= numTokensSellToAddToLiquidity;
        if (
            overMinTokenBalance &&
            !inSwapAndLiquify &&
            !_isUniswapV2Pair[from] &&
            swapAndLiquifyEnabled
        ) {
            contractTokenBalance = numTokensSellToAddToLiquidity;
            //add liquidity
            swapAndLiquify(contractTokenBalance);
        }
        
        // indicates if fee should be deducted from transfer
        bool takeFee;
        
        // take fee only in buying or selling operation
        if (from != address(this) && to != address(this)) {
            // buy
            if (_isUniswapV2Pair[from] && to != address(uniswapV2Router)) {
                takeFee = true;
                uint256 timestamp = block.timestamp;
                require(_cooldown[from].buy < timestamp, "You can transfer tokens once in 15 seconds");
                _cooldown[from].buy = timestamp + 30;
            } 
            // sell 
            else {
                // if holderCount increases by 100 then 10% of 
                // burnlock tokens burned
                if (_holderCount > _lastMaxHolderCount) {
                    _burnTenPercent();
                    _lastMaxHolderCount += 100;
                }
                if (_isUniswapV2Pair[to]) {
                    takeFee = true;
                    // if ETH from buy back is more or equal than 0.2 ether
                    // then we buyBack tokens and burn
                    if (_buyBackETHCount >= 0.2 ether) {
                        _buyBackAndBurn(_buyBackETHCount);
                        _buyBackETHCount = 0;
                    }
                    uint256 timestamp = block.timestamp;
                    require(_cooldown[to].sell < timestamp, "You can transfer tokens once in 15 seconds");
                    _cooldown[to].sell = timestamp + 30;
                }
            }
        }

        // if sender is owner or recipient is owner or recipient is deadAddress
        // then fee does not taken
        if (from == owner() || to == owner() || to == deadAddress) {
            takeFee = false;
        }
        
        // transfer amount, it will take tax, burn, liquidity, marketing fee
        _tokenTransfer(from, to, amount, takeFee);
    }

    function _buyBackAndBurn(uint256 amount) private lockTheSwap {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = uniswapV2Router.WETH();
        path[1] = address(this);

        // make the swap
        uniswapV2Router.swapExactETHForTokensSupportingFeeOnTransferTokens{ value: amount }(
            0, // accept any amount of Tokens
            path,
            deadAddress, // Burn address
            block.timestamp
        );

        emit SwapETHForTokens(amount, path);

        // burn
        uint256 balance = balanceOf(deadAddress);
        if (balance > 0) {
            _rTotal -= _rOwned[deadAddress];
            _tTotal -= balance;
            _rOwned[deadAddress] = 0;
            emit Transfer(deadAddress, address(0), balance);
        }
    }

    function swapAndLiquify(uint256 contractTokenBalance) private lockTheSwap {
        // split the contract balance into halves
        uint256 half = contractTokenBalance / 2;
        uint256 otherHalf = contractTokenBalance - half;

        // capture the contract's current ETH balance.
        // this is so that we can capture exactly the amount of ETH that the
        // swap creates, and not make the liquidity event include any ETH that
        // has been manually sent to the contract
        uint256 initialBalance = address(this).balance;

        // swap tokens for ETH
        swapTokensForEth(half); // <- this breaks the ETH -> HATE swap when swap+liquify is triggered

        // how much ETH did we just swap into?
        uint256 newBalance = address(this).balance - initialBalance;

        // add liquidity to uniswap
        addLiquidity(otherHalf, newBalance);
        
        emit SwapAndLiquify(half, newBalance, otherHalf);
    }

    function swapTokensForEth(uint256 tokenAmount) private {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // make the swap
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );
    }

    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {
        // approve token transfer to cover all possible scenarios
        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // add the liquidity
        uniswapV2Router.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            owner(),
            block.timestamp
        );
    }

    //this method is responsible for taking all fee, if takeFee is true
    function _tokenTransfer(address sender, address recipient, uint256 tAmount, bool takeFee) private {
        if(!takeFee) {
            removeAllFee();
        }

        // tValues[0] -> tTransferAmount -> transfer amount
        // tValues[1] -> tFee -> holders fee amount
        // tValues[2] -> tLiquidity -> liquidity fee amount
        // tValues[3] -> tMarketing -> marketing fee amount
        // tValues[4] -> tBuyBack -> buyBack fee amount
        uint256[5] memory tValues = _getTValues(tAmount);
        uint256 currentRate = _getRate();
        if (takeFee) {
            _rBuyBackTokenCount += (tValues[4] * currentRate);
            if (!_isUniswapV2Pair[sender] && _rBuyBackTokenCount > 0) {
                uint256 _tBuyBackTokenCount = _rBuyBackTokenCount / currentRate;
                address contractAddress = address(this);
                _rOwned[contractAddress] += _rBuyBackTokenCount;
                emit Transfer(sender, contractAddress, _tBuyBackTokenCount);
                uint256 balanceBefore = contractAddress.balance;
                swapTokensForEth(_tBuyBackTokenCount);
                uint256 balanceAfter = contractAddress.balance;
                _buyBackETHCount += balanceAfter - balanceBefore;
                _rBuyBackTokenCount = 0;
            }
            _rOwned[marketingAddress] += (tValues[3] * currentRate);
            _takeLiquidity(tValues[2], tValues[2] * currentRate);
            _reflectFee(tValues[1], tValues[1] * currentRate);
            emit Transfer(sender, marketingAddress, tValues[3]);
        }
        _rOwned[sender] -= (tAmount * currentRate);
        _rOwned[recipient] += (tValues[0] * currentRate);
        if (_isExcluded[sender]) {
            _tOwned[sender] -= tAmount;
        }
        if (_isExcluded[recipient]) {
            _tOwned[recipient] += tValues[0];
        }
        emit Transfer(sender, recipient, tValues[0]);
        
        if(!takeFee) {
            restoreAllFee();
        }
    }
}
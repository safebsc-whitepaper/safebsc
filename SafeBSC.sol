SPDX-License-Identifier: MIT */

pragma solidity 0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

contract SafeBSC is ERC20, Ownable(msg.sender) {
    IUniswapV2Router02 public uniswapV2Router;
    address public uniswapV2Pair;

    mapping (address => bool) private _isExcludedFromFees;

    uint256 public  feeOnBuy;
    uint256 public  feeOnSell;

    uint256 public  feeOnTransfer;

    address public  feeReceiver;

    uint256 public  swapTokensAtAmount;
    uint256 public  maxFeeSwap;
    bool    public  feeSwapEnabled;

    bool    private swapping;

    bool    public  tradingEnabled;

    error TradingNotEnabled();
    error TradingAlreadyEnabled();
    error FeeSetupError();
    error InvalidAddress(address invalidAddress);
    error NotAllowed(address token, address sender);
    error FeeTooHigh(uint256 feeOnBuy, uint256 feeOnSell, uint256 feeOnTransfer);
    error ZeroAddress(address feeReceiver);

    event TradingEnabled();
    event ExcludedFromFees(address indexed account, bool isExcluded);
    event FeeReceiverChanged(address feeReceiver);

    constructor () ERC20("SafeBSC", "SafeBSC") {
        address router;
        address pinkLock;
        
        if (block.chainid == 56) {
            router = 0x10ED43C718714eb63d5aA57B78B54704E256024E;
            pinkLock = 0x407993575c91ce7643a4d4cCACc9A98c36eE1BBE; 
        } else if (block.chainid == 97) {
            router = 0xD99D1c33F9fC3444f8101754aBC46c52416550D1;
            pinkLock = 0x5E5b9bE5fd939c578ABE5800a90C566eeEbA44a5;
        } else if (block.chainid == 1 || block.chainid == 5) {
            router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
            pinkLock = 0x71B5759d73262FBb223956913ecF4ecC51057641;
        } else {
            revert();
        }

        uniswapV2Router = IUniswapV2Router02(router);
        uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory())
            .createPair(address(this), uniswapV2Router.WETH());

        _approve(address(this), address(uniswapV2Router), type(uint256).max);

        feeOnBuy  = 5;
        feeOnSell = 5;

        feeOnTransfer = 0;

        feeReceiver = 0x2460CA21442A23483f66d4E586A378a7075C5402;

        _isExcludedFromFees[owner()] = true;
        _isExcludedFromFees[address(0xdead)] = true;
        _isExcludedFromFees[address(this)] = true;
        _isExcludedFromFees[pinkLock] = true;

        uint256 totalSupply = 420e9 * (10 ** decimals());
    
        maxFeeSwap = totalSupply / 1_000; 
        swapTokensAtAmount = totalSupply / 5_000;

        feeSwapEnabled = false;

        super._update(address(0), owner(), totalSupply);
    }

    receive() external payable {}

    function _update(address from, address to, uint256 value) internal override {        
        bool isExcluded = _isExcludedFromFees[from] || _isExcludedFromFees[to];

        if (!isExcluded && !tradingEnabled) {
            revert TradingNotEnabled();
        }

        if (!swapping && from != uniswapV2Pair && feeSwapEnabled) {
            uint256 contractTokenBalance = balanceOf(address(this));
            bool canSwap = contractTokenBalance >= swapTokensAtAmount;

            if (canSwap) {
                swapping = true;

                swapAndSendFee(contractTokenBalance);

                swapping = false;
            }
        }

        uint256 _totalFees = 0;
        if (!isExcluded && !swapping) {
            if (from == uniswapV2Pair) {
                _totalFees = feeOnBuy;
            } else if (to == uniswapV2Pair) {
                _totalFees = feeOnSell;
            } else {
                _totalFees = feeOnTransfer;
            }
        }

        if (_totalFees > 0) {
            uint256 fees = (value * _totalFees) / 100;
            value -= fees;
            super._update(from, address(this), fees);
        }

        super._update(from, to, value);
    }

    function swapAndSendFee(uint256 amount) internal returns (bool) {
        if (amount > maxFeeSwap){
            amount = maxFeeSwap;
        }

        uint256 initialBalance = address(this).balance;

        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        try uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            amount,
            0,
            path,
            address(this),
            block.timestamp
        ) {
            uint256 newBalance = address(this).balance - initialBalance;
            (bool success, ) = payable(feeReceiver).call{value: newBalance}("");
            return success;    
        } catch {
            return false;
        }
    }

    function enableTrading() external onlyOwner {
        if (tradingEnabled) {
            revert TradingAlreadyEnabled();
        }

        tradingEnabled = true;
        feeSwapEnabled = true;

        emit TradingEnabled();
    }

    function setFeeSwapSettings(
        uint256 _swapTokensAtAmount, 
        uint256 _maxFeeSwap, 
        bool _feeSwapEnabled
    ) external onlyOwner {
        uint256 decimalsToAdd = 10 ** decimals();

        maxFeeSwap = _maxFeeSwap * decimalsToAdd;
        swapTokensAtAmount = _swapTokensAtAmount * decimalsToAdd;
        feeSwapEnabled = _feeSwapEnabled;

        if (swapTokensAtAmount > totalSupply() || maxFeeSwap < swapTokensAtAmount){
            revert FeeSetupError();
        }
    }

    function excludeFromFees(address account, bool excluded) external onlyOwner{
        _isExcludedFromFees[account] = excluded;

        emit ExcludedFromFees(account, excluded);
    }

    function isExcludedFromFees(address account) public view returns(bool) {
        return _isExcludedFromFees[account];
    }

    function changeFeeReceiver(address _feeReceiver) external onlyOwner{
        if (_feeReceiver == address(0)){
            revert ZeroAddress(_feeReceiver);
        }

        feeReceiver = _feeReceiver;

        emit FeeReceiverChanged(feeReceiver);
    }

    function recoverStuckTokens(address token) external {
        if (token == address(this) || (msg.sender != owner() && msg.sender != feeReceiver)){
            revert NotAllowed(token, msg.sender);
        }

        if (token == address(0x0)) {
            payable(msg.sender).transfer(address(this).balance);
            return;
        }

        IERC20 ERC20token = IERC20(token);
        uint256 balance = ERC20token.balanceOf(address(this));
        ERC20token.transfer(msg.sender, balance);
    }
}
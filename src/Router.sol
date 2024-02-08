// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol"; 

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { Vault } from  "./Vault.sol";

import { IWrappedETH } from "./interfaces/IWrappedETH.sol";
import { ISwapRouter } from "./interfaces/uniswap/ISwapRouter.sol";
import { IQuoterV2 } from "./interfaces/uniswap/IQuoterV2.sol";
import { IUniswapV3Factory } from "./interfaces/uniswap/IUniswapV3Factory.sol";
import { IUniswapV3Pool } from "./interfaces/uniswap/IUniswapV3Pool.sol";
import { IPool } from "../src/interfaces/aave/IPool.sol";


contract Router {
    using SafeERC20 for IERC20;

    uint24 public constant FEE = 3000;
    uint256 public constant SEARCH_TOLERANCE = 1e9;

    Vault public immutable vault;
    IWrappedETH public immutable weth;

    // Uniswap
    IUniswapV3Factory public immutable uniswapV3Factory;
    ISwapRouter public immutable swapRouter;
    IQuoterV2 public immutable quoterV2;

    // Aave
    IPool public immutable aavePool;

    constructor(address vault_,
                address weth_,
                address uniswapV3Factory_,
                address swapRouter_,
                address quoterV2_,
                address aavePool_) {

        vault = Vault(vault_);
        weth = IWrappedETH(weth_);
        uniswapV3Factory = IUniswapV3Factory(uniswapV3Factory_);
        swapRouter = ISwapRouter(swapRouter_);
        quoterV2 = IQuoterV2(quoterV2_);
        aavePool = IPool(aavePool_);
    }

    function _min(uint256 x, uint256 y) internal pure returns (uint256) {
        return x < y ? x : y;
    }

    function pool(uint192 strike) public view returns (address) {
        IERC20 hodlToken = IERC20(vault.deployments(strike));
        (address token0, address token1) = address(hodlToken) < address(weth)
            ? (address(hodlToken), address(weth))
            : (address(weth), address(hodlToken));

        return uniswapV3Factory.getPool(token0, token1, FEE);
    }

    function previewHodl(uint192 strike, uint256 amount) public returns (uint256) {
        IERC20 token = IERC20(vault.deployments(strike));
        require(address(token) != address(0), "no deployed ERC20");
        address uniPool = pool(strike);
        require(uniPool != address(0), "no uni pool");

        IQuoterV2.QuoteExactInputSingleParams memory params = IQuoterV2.QuoteExactInputSingleParams({
            tokenIn: address(weth),
            tokenOut: address(token),
            amountIn: amount,
            fee: FEE,
            sqrtPriceLimitX96: 0 });

        (uint256 amountOut, , ,) = quoterV2.quoteExactInputSingle(params);

        return amountOut;
    }

    function hodl(uint192 strike, uint256 minOut) public payable returns (uint256, uint32) {
        IERC20 token = IERC20(vault.deployments(strike));
        require(address(token) != address(0), "no deployed ERC20");
        address uniPool = pool(strike);
        require(uniPool != address(0), "no uni pool");

        weth.deposit{value: msg.value}();

        IERC20(address(weth)).approve(address(address(swapRouter)), 0);
        IERC20(address(weth)).approve(address(address(swapRouter)), msg.value);

        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: address(weth),
                tokenOut: address(token),
                fee: FEE,
                recipient: address(this),
                deadline: block.timestamp + 1,
                amountIn: msg.value,
                amountOutMinimum: minOut,
                sqrtPriceLimitX96: 0 });

        uint256 out = swapRouter.exactInputSingle(params);

        uint32 stakeId = vault.hodlStake(strike, out, msg.sender);

        return (out, stakeId);
    }

    function _searchLoanSize(uint192 strike,
                             uint256 value,
                             uint256 lo,
                             uint256 hi,
                             uint256 n) private returns (uint256) {

        if (n == 0) {
            return 0;
        }

        IERC20 hodl = IERC20(vault.deployments(strike));
        address uniPool = pool(strike);
        uint256 loan = (hi + lo) / 2;
        uint256 fee = _flashLoanFee(loan);
        uint256 debt = loan + fee;

        IQuoterV2.QuoteExactInputSingleParams memory params = IQuoterV2.QuoteExactInputSingleParams({
            tokenIn: address(hodl),
            tokenOut: address(weth),
            amountIn: value + loan,
            fee: FEE,
            sqrtPriceLimitX96: 0 });

        (uint256 out, , ,) = quoterV2.quoteExactInputSingle(params);

        if (out > debt) {

            // Output is enough to payoff loan + fee, can take larger loan
            uint256 diff = out - debt;
            if (diff < SEARCH_TOLERANCE) {
                return loan;
            }

            return _searchLoanSize(strike, value, loan, hi, n -1);
        } else {

            // Output to small to payoff loan + fee, reduce loan size
            return _searchLoanSize(strike, value, lo, loan, n - 1);
        }
    }

    function _flashLoanFee(uint256 loan) private view returns (uint256) {
        uint256 percent = aavePool.FLASHLOAN_PREMIUM_TOTAL();
        return loan * percent / 10_000;
    }

    function previewY(uint192 strike, uint256 value) public returns (uint256, uint256) {
        IERC20 hodl = IERC20(vault.deployments(strike));
        require(address(hodl) != address(0), "no deployed ERC20");
        address uniPool = pool(strike);
        require(uniPool != address(0), "no uni pool");

        uint256 loan = _searchLoanSize(strike, value, 0, 1000 * value, 64);

        // Amount of y tokens output
        uint256 out = value + loan;

        return (out, loan);
    }

    function y(uint192 strike, uint256 loan) public payable {
        console.log("msg.sender y", msg.sender);
        uint256 value = msg.value;
        bytes memory data = abi.encode(msg.sender, strike, value + loan);
        aavePool.flashLoanSimple(address(this), address(weth), loan, data, 0);
    }

    function executeOperation(
        address,
        uint256 loan,
        uint256 fee,
        address,
        bytes calldata params
    ) external payable returns (bool) {

        console.log("flash loan success, in exec op");

        (address user, uint192 strike, uint256 amount) = abi.decode(params, (address, uint192, uint256));

        IERC20 hodl = IERC20(vault.deployments(strike));
        require(address(hodl) != address(0), "no deployed ERC20");

        /* uint256 debt = loan + fee; */
        console.log("amount is:", amount);
        /* console.log("debt is:  ", debt); */

        // mint hodl + y tokens
        console.log("withdrawing weth:", loan);
        weth.withdraw(loan);

        require(address(this).balance == amount, "expected balance == amount");
        console.log("my balance:", address(this).balance);
        console.log("amount:    ", amount);
        vault.mint{value: amount}(strike);

        // sell hodl tokens to repay debt
        {
            IERC20(address(hodl)).approve(address(address(swapRouter)), 0);
            IERC20(address(hodl)).approve(address(address(swapRouter)), amount);

            ISwapRouter.ExactInputSingleParams memory params =
                ISwapRouter.ExactInputSingleParams({
                    tokenIn: address(hodl),
                    tokenOut: address(weth),
                    fee: FEE,
                    recipient: address(this),
                    deadline: block.timestamp + 1,
                    amountIn: amount,
                    amountOutMinimum: loan + fee,
                    sqrtPriceLimitX96: 0 });
            uint256 out = swapRouter.exactInputSingle(params);
            console.log("hodl sale got out:", out);
            console.log("loan is:          ", loan);
            console.log("debt is:          ", loan + fee);
            console.log("fee is:           ", fee);

            // approve repayment
            IERC20(address(weth)).approve(address(aavePool), loan + fee);

            // transfer y tokens to buyer
            console.log("y multi balance", vault.yMulti().balanceOf(address(this), strike));
            console.log("         amount", amount);
            amount = _min(amount,
                          vault.yMulti().balanceOf(address(this), strike));
            vault.yMulti().safeTransferFrom(address(this),
                                            user,
                                            strike,
                                            amount,
                                            "");
        }

        return true;
    }

    function onERC1155Received(address, address, uint256, uint256, bytes memory) public virtual returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] memory, uint256[] memory, bytes memory) public virtual returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }

    receive() external payable {}

    fallback() external payable {}
}

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


contract Router {
    using SafeERC20 for IERC20;

    uint24 public constant FEE = 3000;

    Vault public immutable vault;
    IWrappedETH public immutable weth;

    // Uniswap
    IUniswapV3Factory public immutable uniswapV3Factory;
    ISwapRouter public immutable swapRouter;
    IQuoterV2 public immutable quoterV2;

    constructor(address vault_,
                address weth_,
                address uniswapV3Factory_,
                address swapRouter_,
                address quoterV2_) {
        require(vault_ != address(0));
        require(weth_ != address(0));

        vault = Vault(vault_);
        weth = IWrappedETH(weth_);
        uniswapV3Factory = IUniswapV3Factory(uniswapV3Factory_);
        swapRouter = ISwapRouter(swapRouter_);
        quoterV2 = IQuoterV2(quoterV2_);
    }

    function pool(uint256 strike) public view returns (address) {
        IERC20 hodlToken = IERC20(vault.deployments(strike));
        (address token0, address token1) = address(hodlToken) < address(weth)
            ? (address(hodlToken), address(weth))
            : (address(weth), address(hodlToken));

        return uniswapV3Factory.getPool(token0, token1, FEE);
    }

    function previewHodl(uint256 strike, uint256 amount) public returns (uint256) {
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

    function hodl(uint256 strike, uint256 minOut) public payable returns (uint256, uint32) {
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

    function onERC1155Received(address, address, uint256, uint256, bytes memory) public virtual returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] memory, uint256[] memory, bytes memory) public virtual returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol"; 

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IStEth } from "../src/interfaces/IStEth.sol";

import { Vault } from  "../src/Vault.sol";
import { Router } from  "../src/Router.sol";
import { HodlToken } from  "../src/single/HodlToken.sol";
import { UniswapV3LiquidityPool } from "../src/liquidity/UniswapV3LiquidityPool.sol";
import { ILiquidityPool } from "../src/interfaces/ILiquidityPool.sol";

// Uniswap interfaces
import { IUniswapV3Pool } from "../src/interfaces/uniswap/IUniswapV3Pool.sol";
import { IUniswapV3Factory } from "../src/interfaces/uniswap/IUniswapV3Factory.sol";
import { IWrappedETH } from "../src/interfaces/IWrappedETH.sol";
import { INonfungiblePositionManager } from "../src/interfaces/uniswap/INonfungiblePositionManager.sol";

// Aave interfaces
import { IPool } from "../src/interfaces/aave/IPool.sol";

import { BaseTest } from  "./BaseTest.sol";
import { FakeOracle } from  "./helpers/FakeOracle.sol";

contract RouterTest is BaseTest {
    Vault public vault;
    Router public router;
    FakeOracle public oracle;

    // Tokens
    address public weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public steth = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address public wsteth = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

    // Uniswap
    address public uniswapV3Factory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address public nonfungiblePositionManager = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    address public swapRouter = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address public quoterV2 = 0x61fFE014bA17989E743c5F6cB21bF9697530B21e;

    // Aave
    address public aavePool = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;

    UniswapV3LiquidityPool public pool;
    IUniswapV3Pool public uniswapV3Pool;
    INonfungiblePositionManager public manager;

    uint192 strike1 = 2000_00000000;

    function setUp() public {
        init();
    }

    function initRouter() public {
        // Set up: deploy vault, mint some hodl for alice, make it redeemable
        oracle = new FakeOracle();
        vault = new Vault(steth, address(oracle));
        oracle.setPrice(strike1 - 1);
        address hodl1 = vault.deployERC20(strike1);
        vm.startPrank(alice);
        vault.mint{value: 3 ether}(strike1);
        vm.stopPrank();
        oracle.setPrice(strike1 + 1);

        // Set up the pool
        (address token0, address token1) = hodl1 < weth
            ? (hodl1, weth)
            : (weth, hodl1);
        uniswapV3Pool = IUniswapV3Pool(IUniswapV3Factory(uniswapV3Factory).getPool(token0, token1, 3000));

        if (address(uniswapV3Pool) == address(0)) {
            uniswapV3Pool = IUniswapV3Pool(IUniswapV3Factory(uniswapV3Factory).createPool(token0, token1, 3000));
            IUniswapV3Pool(uniswapV3Pool).initialize(79228162514264337593543950336);
        }

        vm.deal(alice, 10 ether);

        vm.startPrank(alice);
        IWrappedETH(address(weth)).deposit{value: 10 ether}();
        vm.stopPrank();

        uint256 token0Amount = 0.5 ether;
        uint256 token1Amount = 0.5 ether;

        // Add initial liquidity
        manager = INonfungiblePositionManager(nonfungiblePositionManager);
        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: token0,
            token1: token1,
            fee: 3000,
            tickLower: -1800,
            tickUpper: 2220,
            amount0Desired: token0Amount,
            amount1Desired: token1Amount,
            amount0Min: 0,
            amount1Min: 0,
            recipient: alice,
            deadline: block.timestamp + 1 });

        vm.startPrank(alice);
        IERC20(params.token0).approve(address(manager), token0Amount);
        IERC20(params.token1).approve(address(manager), token1Amount);
        manager.mint(params);
        vm.stopPrank();

        router = new Router(address(vault),
                            address(weth),
                            address(steth),
                            address(wsteth),
                            uniswapV3Factory,
                            swapRouter,
                            quoterV2,
                            aavePool);
    }

    function testBuys() public {
        initRouter();

        uint256 previewOut = router.previewHodl(strike1, 0.2 ether);

        vm.deal(alice, 1 ether);
        vm.startPrank(alice);
        (uint256 out, uint32 stakeId) = router.hodl{value: 0.2 ether}(strike1, 0);
        vm.stopPrank();

        assertEq(out, 191381783398625730);
        assertEq(previewOut, 191381783398625730);

        vm.expectRevert("redeem user");
        vault.redeem(strike1, out, stakeId);

        uint256 before = IERC20(steth).balanceOf(alice);

        vm.startPrank(alice);
        vault.redeem(strike1, out, stakeId);
        vm.stopPrank();

        uint256 delta = IERC20(steth).balanceOf(alice) - before;
        assertEq(delta, out - 1);

        (uint256 amountY, uint256 loan) = router.previewY(strike1, 0.2 ether);
        assertEq(amountY, 808707991341361773);
        assertEq(loan, 608707991341361773);

        oracle.setPrice(strike1 - 1);

        assertEq(vault.yMulti().balanceOf(alice, strike1), 0);

        vm.startPrank(alice);
        (uint256 outY, uint32 stake1) = router.y{value: 0.2 ether}(strike1, loan);
        vm.stopPrank();

        assertClose(outY, amountY, 1);
        {
            ( , , , uint256 stakeY, , ) = vault.yStakes(stake1);
            assertClose(stakeY, amountY, 10);
        }
    }

    function testSells() public {
        initRouter();

        uint256 previewOut = router.previewHodlSell(strike1, 0.2 ether);

        IERC20 token = IERC20(vault.deployments(strike1));

        {
            uint256 before = IERC20(address(weth)).balanceOf(alice);

            vm.startPrank(alice);
            token.approve(address(router), 0.2 ether);
            (uint256 out) = router.hodlSell(strike1, 0.2 ether, previewOut);
            vm.stopPrank();

            uint256 delta = IERC20(address(weth)).balanceOf(alice) - before;

            assertEq(out, 191381783398625730);
            assertEq(previewOut, 191381783398625730);
            assertEq(delta, 191381783398625730);
        }

        {
            (uint256 loan, uint256 previewProfit) = router.previewYSell(strike1, 0.2 ether);
            console.log("");
            console.log("previewY loan  ", loan);
            console.log("previewY profit", previewProfit);
            console.log("alice y balance", vault.yMulti().balanceOf(alice, strike1));

            uint256 before = IERC20(address(weth)).balanceOf(alice);

            vm.startPrank(alice);
            vault.yMulti().setApprovalForAll(address(router), true);
            uint256 out = router.ySell(strike1, loan, 0.2 ether);
            vm.stopPrank();

            uint256 delta = IERC20(address(weth)).balanceOf(alice) - before;

            console.log("out  ", out);
            console.log("delta", delta);

            assertEq(previewProfit, 7164532291331987);
            assertClose(out, 7164532291331987, 1);
            assertClose(delta, 7164532291331987, 1);
        }

        /* vm.startPrank(alice); */
        /* (uint256 outY, uint32 stake1) = router.(strike1, 0.2 ether); */
        /* vm.stopPrank(); */
    }
}

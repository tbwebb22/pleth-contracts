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

import { BaseTest } from  "./BaseTest.sol";
import { FakeOracle } from  "./helpers/FakeOracle.sol";

contract VaultTest is BaseTest {
    Vault vault;

    address stEth = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    address uniswapV3Factory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address nonfungiblePositionManager = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    address swapRouter = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address quoterV2 = 0x61fFE014bA17989E743c5F6cB21bF9697530B21e;

    UniswapV3LiquidityPool pool;
    IUniswapV3Pool uniswapV3Pool;
    INonfungiblePositionManager manager;

    FakeOracle oracle;

    uint192 strike1 = 2000_00000000;
    uint192 strike2 = 3000_00000000;
    uint192 strike3 = 4000_00000000;

    function setUp() public {
        init();
    }

    function initVault() public {
        oracle = new FakeOracle();
        oracle.setPrice(1999_00000000);
        vault = new Vault(stEth, address(oracle));
    }

    function testVault() public {
        initVault();

        // mint hodl tokens
        vm.startPrank(alice);
        uint256 epoch1 = vault.nextId();
        vault.mint{value: 3 ether}(strike1);
        vm.stopPrank();

        vm.startPrank(bob);
        uint256 epoch2 = vault.nextId();
        vault.mint{value: 4 ether}(strike2);
        vm.stopPrank();

        vm.startPrank(chad);
        uint256 epoch3 = vault.nextId();
        vault.mint{value: 8 ether}(strike3);
        vm.stopPrank();

        assertEq(vault.hodlMulti().balanceOf(alice, strike1), 3 ether - 1);
        assertEq(vault.hodlMulti().balanceOf(bob, strike1), 0);
        assertEq(vault.hodlMulti().balanceOf(chad, strike1), 0);
        assertEq(vault.yMulti().balanceOf(alice, strike1), 3 ether - 1);
        assertEq(vault.yMulti().balanceOf(bob, strike1), 0);
        assertEq(vault.yMulti().balanceOf(chad, strike1), 0);

        assertEq(vault.hodlMulti().balanceOf(alice, strike2), 0);
        assertEq(vault.hodlMulti().balanceOf(bob, strike2), 4 ether);
        assertEq(vault.hodlMulti().balanceOf(chad, strike2), 0);
        assertEq(vault.yMulti().balanceOf(alice, strike2), 0);
        assertEq(vault.yMulti().balanceOf(bob, strike2), 4 ether);
        assertEq(vault.yMulti().balanceOf(chad, strike2), 0);

        assertEq(vault.hodlMulti().balanceOf(alice, strike3), 0);
        assertEq(vault.hodlMulti().balanceOf(bob, strike3), 0);
        assertEq(vault.hodlMulti().balanceOf(chad, strike3), 8 ether - 1);
        assertEq(vault.yMulti().balanceOf(alice, strike3), 0);
        assertEq(vault.yMulti().balanceOf(bob, strike3), 0);
        assertEq(vault.yMulti().balanceOf(chad, strike3), 8 ether - 1);

        // stake hodl tokens, receive y tokens
        vm.startPrank(alice);
        uint32 stake1 = vault.hodlStake(strike1, 2 ether, alice);
        vm.stopPrank();

        vm.startPrank(bob);
        uint32 stake2 = vault.hodlStake(strike2, 4 ether, bob);
        vm.stopPrank();

        vm.startPrank(chad);
        uint32 stake3 = vault.hodlStake(strike3, 8 ether - 1, chad);
        vm.stopPrank();

        assertEq(vault.hodlMulti().balanceOf(alice, strike1), 1 ether - 1);
        assertEq(vault.yMulti().balanceOf(alice, strike1), 3 ether - 1);

        assertEq(vault.hodlMulti().balanceOf(bob, strike2), 0);
        assertEq(vault.yMulti().balanceOf(bob, strike2), 4 ether);

        assertEq(vault.hodlMulti().balanceOf(chad, strike3), 0);
        assertEq(vault.yMulti().balanceOf(chad, strike3), 8 ether - 1);

        // stake y token
        vm.startPrank(alice);
        uint32 stake4 = vault.yStake(strike1, 1 ether);
        vm.stopPrank();

        vm.startPrank(bob);
        uint32 stake5 = vault.yStake(strike2, 4 ether);
        vm.stopPrank();

        vm.startPrank(chad);
        uint32 stake6 = vault.yStake(strike3, 8 ether - 1);
        vm.stopPrank();

        assertEq(vault.yMulti().balanceOf(alice, strike1), 2 ether - 1);
        assertEq(vault.yMulti().balanceOf(bob, strike2), 0);
        assertEq(vault.yMulti().balanceOf(chad, strike3), 0);

        assertEq(vault.yStakedTotal(), 13 ether - 1);

        // simulate yield, stETH balance grows, verify y token receives yield
        simulateYield(0.13 ether + 1);

        assertEq(vault.totalCumulativeYield(), 0.13 ether + 1);
        assertEq(vault.cumulativeYield(epoch1), 0.01 ether);
        assertEq(vault.cumulativeYield(epoch2), 0.04 ether);
        assertEq(vault.cumulativeYield(epoch3), 0.08 ether - 1);

        // verify claimable yields + claim
        assertEq(vault.claimable(stake4), 0.01 ether);
        assertEq(vault.claimable(stake5), 0.04 ether);
        assertEq(vault.claimable(stake6), 0.08 ether - 1);

        vm.expectRevert("y claim user");
        vault.claim(stake4);

        claimAndVerify(stake4, alice, 0.01 ether, true);
        claimAndVerify(stake5, bob, 0.04 ether, true);
        claimAndVerify(stake6, chad, 0.08 ether - 1, true);

        // move price above strike1, verify redeem via hodl token

        vm.startPrank(alice);
        vm.expectRevert("cannot redeem");
        vault.redeem(strike1, 1 ether, stake1);
        vm.stopPrank();

        oracle.setPrice(strike1 + 1);

        assertClose(IERC20(stEth).balanceOf(alice), 0 ether, 10);

        vm.startPrank(alice);
        vault.redeem(strike1, 1 ether, stake1);
        vm.stopPrank();

        assertEq(vault.yStakedTotal(), 12 ether - 1);

        // unstaked y tokens should be burned

        assertEq(vault.yMulti().balanceOf(alice, strike1), 0);

        assertClose(IERC20(stEth).balanceOf(alice), 1 ether, 10);
        assertClose(IERC20(stEth).balanceOf(bob), 0, 10);
        assertClose(IERC20(stEth).balanceOf(chad), 0, 10);

        // simulate more yield, verify only epoch2 and epoch3 get it

        simulateYield(0.12 ether);

        assertEq(vault.cumulativeYield(epoch1), 0.01 ether);
        assertEq(vault.cumulativeYield(epoch2), 0.08 ether);
        assertEq(vault.cumulativeYield(epoch3), 0.16 ether - 1);

        // move price above both strike2 and strike3, but only strike3 claims

        oracle.setPrice(strike3 + 1);

        assertClose(IERC20(stEth).balanceOf(chad), 0 ether, 10);

        assertEq(vault.yStaked(epoch1), 0);
        assertEq(vault.yStaked(epoch2), 4 ether);
        assertEq(vault.yStaked(epoch3), 8 ether - 1);
        assertEq(vault.yStakedTotal(), 12 ether - 1);

        vm.startPrank(chad);
        vault.redeem(strike3, 4 ether, stake3);
        vm.stopPrank();

        assertEq(vault.yStaked(epoch1), 0);
        assertEq(vault.yStaked(epoch2), 4 ether);
        assertEq(vault.yStaked(epoch3), 0);
        assertEq(vault.yStakedTotal(), 4 ether);

        assertClose(IERC20(stEth).balanceOf(alice), 1 ether, 10);
        assertClose(IERC20(stEth).balanceOf(bob), 0, 10);
        assertClose(IERC20(stEth).balanceOf(chad), 4 ether, 10);

        simulateYield(0.08 ether);

        assertEq(vault.cumulativeYield(epoch1), 0.01 ether);
        assertEq(vault.cumulativeYield(epoch2), 0.16 ether - 4);  // not redeemed, gets all the increase
        assertEq(vault.cumulativeYield(epoch3), 0.16 ether - 1);  // [strike3] redeemed, so no increase

        // can mint at strike3 again, but only once price goes down
        vm.startPrank(chad);
        vm.expectRevert("strike too low");
        vault.mint{value: 4 ether}(strike3);
        vm.stopPrank();

        oracle.setPrice(strike3 - 1);

        vm.startPrank(chad);
        uint256 epoch4 = vault.nextId();
        vault.mint{value: 8 ether}(strike3);
        assertEq(vault.hodlMulti().balanceOf(chad, strike3), 8 ether);
        vm.stopPrank();

        // epoch for strike3 unchanged until redeem
        assertEq(vault.cumulativeYield(epoch3), 0.16 ether - 1);

        // degen gets some yield, verify address level accounting
        
        simulateYield(0.08 ether);

        assertEq(vault.yStaked(epoch1), 0);
        assertEq(vault.yStaked(epoch2), 4 ether);
        assertEq(vault.yStaked(epoch3), 0);

        assertEq(vault.cumulativeYield(epoch1), 0.01 ether);
        assertEq(vault.cumulativeYield(epoch2), 0.24 ether - 8);
        assertEq(vault.cumulativeYield(epoch3), 0.16 ether - 1);  // [strike3] redeemed, so no increase
        assertEq(vault.cumulativeYield(epoch4), 0);  // [strike3] unstaked, so no yield

        // transfer y tokens, verify address level accounting

        vm.startPrank(chad);
        assertEq(vault.yMulti().balanceOf(chad, strike3), 8 ether);
        uint32 stake7 = vault.hodlStake(strike3, 8 ether, chad);
        vault.yMulti().safeTransferFrom(chad, degen, strike3, 4 ether, "");
        assertEq(vault.yMulti().balanceOf(chad, strike3), 4 ether);
        assertEq(vault.yMulti().balanceOf(degen, strike3), 4 ether);
        vm.stopPrank();

        assertEq(vault.cumulativeYield(epoch4), 0);  // [strike3] unstaked, so no yield

        // simulate yield after y token transfer, verify address level accounting
        vm.startPrank(degen);
        uint32 stake8 = vault.yStake(strike3, 4 ether);
        vm.stopPrank();

        assertEq(vault.yStakedTotal(), 8 ether);

        assertEq(vault.cumulativeYield(epoch4), 0);  // [strike3] unstaked, so no yield

        simulateYield(0.08 ether);

        assertEq(vault.yStaked(epoch1), 0);
        assertEq(vault.yStaked(epoch2), 4 ether);
        assertEq(vault.yStaked(epoch3), 0);
        assertEq(vault.yStaked(epoch4), 4 ether);
        assertEq(vault.yStakedTotal(), 8 ether);

        assertEq(vault.cumulativeYield(epoch1), 0.01 ether);
        assertEq(vault.cumulativeYield(epoch2), 0.28 ether - 12);
        assertEq(vault.cumulativeYield(epoch3), 0.16 ether - 1);  // [strike3] redeemed, so no increase
        assertEq(vault.cumulativeYield(epoch4), 0.04 ether - 4);  // [strike3] staked in new epoch
    }

    function testERC20() public {
        testVault();

        address hodl1Address = vault.deployERC20(strike1);

        // deploys should be saved
        assertEq(hodl1Address, vault.deployERC20(strike1));

        HodlToken hodl1 = HodlToken(hodl1Address);

        assertEq(vault.hodlMulti().totalSupply(strike1), hodl1.totalSupply());

        assertEq(vault.hodlMulti().balanceOf(alice, strike1), hodl1.balanceOf(alice));
        assertEq(vault.hodlMulti().balanceOf(bob, strike1), hodl1.balanceOf(bob));
        assertEq(vault.hodlMulti().balanceOf(chad, strike1), hodl1.balanceOf(chad));
        assertEq(vault.hodlMulti().balanceOf(degen, strike1), hodl1.balanceOf(degen));

        vm.startPrank(alice);
        hodl1.transfer(bob, 0.1 ether);
        vm.stopPrank();

        assertEq(hodl1.balanceOf(alice), 0.9 ether - 1);
        assertEq(hodl1.balanceOf(bob), 0.1 ether);

        vm.startPrank(degen);
        vm.expectRevert("not authorized");
        hodl1.transferFrom(alice, chad, 0.2 ether);
        vm.stopPrank();

        vm.startPrank(alice);
        hodl1.approve(degen, 0.2 ether);
        vm.stopPrank();

        assertEq(hodl1.allowance(alice, degen), 0.2 ether);

        vm.startPrank(degen);
        vm.expectRevert("not authorized");
        hodl1.transferFrom(alice, chad, 0.3 ether);

        hodl1.transferFrom(alice, chad, 0.2 ether);

        vm.expectRevert("not authorized");
        hodl1.transferFrom(alice, chad, 0.2 ether);
        vm.stopPrank();

        assertEq(hodl1.balanceOf(alice), 0.7 ether - 1);
        assertEq(hodl1.balanceOf(bob), 0.1 ether);
        assertEq(hodl1.balanceOf(chad), 0.2 ether);
        assertEq(hodl1.balanceOf(degen), 0);

        assertEq(vault.hodlMulti().totalSupply(strike1), hodl1.totalSupply());

        assertEq(vault.hodlMulti().balanceOf(alice, strike1), hodl1.balanceOf(alice));
        assertEq(vault.hodlMulti().balanceOf(bob, strike1), hodl1.balanceOf(bob));
        assertEq(vault.hodlMulti().balanceOf(chad, strike1), hodl1.balanceOf(chad));
        assertEq(vault.hodlMulti().balanceOf(degen, strike1), hodl1.balanceOf(degen));
    }

    function testStrikeReuse() public {
        initVault();

        vm.startPrank(alice);

        // mint hodl tokens
        vault.mint{value: 4 ether}(strike1);

        // stake 2 of 4 before strike hits
        uint32 stake1 = vault.hodlStake(strike1, 2 ether, alice);

        // strike hits
        oracle.setPrice(strike1 + 1);

        // redeem 1 of 2 staked
        vault.redeem(strike1, 1 ether, stake1);

        // go below strike
        oracle.setPrice(strike1 - 1);

        // redeem 1 remaining staked
        vault.redeem(strike1, 1 ether, stake1);

        // stake 1 at same strike
        uint32 stake2 = vault.hodlStake(strike1, 1 ether, alice);

        // the newly staked tokens cannot be redeemed
        vm.expectRevert("cannot redeem");
        vault.redeem(strike1, 1 ether, stake2);

        // strike hits
        oracle.setPrice(strike1 + 1);

        // redeem the one we staked, now that they hit the strike
        vault.redeem(strike1, 1 ether, stake2);

        // stake and redeem last 1 at that strike
        uint32 stake3 = vault.hodlStake(strike1, 1 ether - 10, alice);
        vault.redeem(strike1, 1 ether - 10, stake3);

        assertClose(IERC20(stEth).balanceOf(alice), 4 ether, 100);

        vm.stopPrank();
    }

    function simulateYield(uint256 amount) internal {
        IStEth(vault.stEth()).submit{value: amount}(address(0));
        IERC20(vault.stEth()).transfer(address(vault), amount);
    }

    function claimAndVerify(uint32 stakeId, address user, uint256 amount, bool dumpCoins) internal {
        assertEq(vault.claimable(stakeId), amount);

        uint256 before = IERC20(stEth).balanceOf(user);

        vm.startPrank(user);
        vault.claim(stakeId);
        vm.stopPrank();

        uint256 delta = IERC20(stEth).balanceOf(user) - before;
        assertClose(delta, amount, 10);
        assertEq(vault.claimable(stakeId), 0);

        vm.startPrank(user);
        vault.claim(stakeId);
        vm.stopPrank();

        delta = IERC20(stEth).balanceOf(user) - before;
        assertClose(delta, amount, 10);

        if (dumpCoins) {
            vm.startPrank(user);
            IERC20(stEth).transfer(address(123), delta);
            vm.stopPrank();
            assertClose(IERC20(stEth).balanceOf(user), before, 10);
        }
    }
}

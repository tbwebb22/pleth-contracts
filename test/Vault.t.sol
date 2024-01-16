// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol"; 

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IStEth } from "../src/interfaces/IStEth.sol";

import { Vault } from  "../src/Vault.sol";
import { HodlToken } from  "../src/single/HodlToken.sol";

import { BaseTest } from  "./BaseTest.sol";
import { FakeOracle } from  "./helpers/FakeOracle.sol";

contract VaultTest is BaseTest {
    Vault public vault;

    address stEth = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84; // mainnet

    function setUp() public {
        init();
    }

    function testVault() public {
        FakeOracle oracle = new FakeOracle();
        oracle.setPrice(1999_00000000);
        vault = new Vault(stEth, address(oracle));

        // Give the whale some stETH
        vm.startPrank(whale);
        IStEth(vault.stEth()).submit{value: 1 ether}(address(0));
        vm.stopPrank();

        uint256 strike1 = 2000_00000000;
        uint256 strike2 = 3000_00000000;
        uint256 strike3 = 4000_00000000;

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
        assertEq(vault.yMulti().balanceOf(alice, strike1), 0);
        assertEq(vault.yMulti().balanceOf(bob, strike1), 0);
        assertEq(vault.yMulti().balanceOf(chad, strike1), 0);

        assertEq(vault.hodlMulti().balanceOf(alice, strike2), 0);
        assertEq(vault.hodlMulti().balanceOf(bob, strike2), 4 ether);
        assertEq(vault.hodlMulti().balanceOf(chad, strike2), 0);
        assertEq(vault.yMulti().balanceOf(alice, strike2), 0);
        assertEq(vault.yMulti().balanceOf(bob, strike2), 0);
        assertEq(vault.yMulti().balanceOf(chad, strike2), 0);

        assertEq(vault.hodlMulti().balanceOf(alice, strike3), 0);
        assertEq(vault.hodlMulti().balanceOf(bob, strike3), 0);
        assertEq(vault.hodlMulti().balanceOf(chad, strike3), 8 ether - 1);
        assertEq(vault.yMulti().balanceOf(alice, strike3), 0);
        assertEq(vault.yMulti().balanceOf(bob, strike3), 0);
        assertEq(vault.yMulti().balanceOf(chad, strike3), 0);

        // stake hodl tokens, receive y tokens
        vm.startPrank(alice);
        uint256 stake1 = vault.hodlStake(strike1, 2 ether);
        vm.stopPrank();

        vm.startPrank(bob);
        uint256 stake2 = vault.hodlStake(strike2, 4 ether);
        vm.stopPrank();

        vm.startPrank(chad);
        uint256 stake3 = vault.hodlStake(strike3, 8 ether - 1);
        vm.stopPrank();

        assertEq(vault.hodlMulti().balanceOf(alice, strike1), 1 ether - 1);
        assertEq(vault.yMulti().balanceOf(alice, strike1), 2 ether);

        assertEq(vault.hodlMulti().balanceOf(bob, strike2), 0);
        assertEq(vault.yMulti().balanceOf(bob, strike2), 4 ether);

        assertEq(vault.hodlMulti().balanceOf(chad, strike3), 0);
        assertEq(vault.yMulti().balanceOf(chad, strike3), 8 ether - 1);

        // stake y token
        vm.startPrank(alice);
        uint256 stake4 = vault.yStake(strike1, 1 ether);
        vm.stopPrank();

        vm.startPrank(bob);
        uint256 stake5 = vault.yStake(strike2, 4 ether);
        vm.stopPrank();

        vm.startPrank(chad);
        uint256 stake6 = vault.yStake(strike3, 8 ether - 1);
        vm.stopPrank();

        assertEq(vault.yMulti().balanceOf(alice, strike1), 1 ether);
        assertEq(vault.yMulti().balanceOf(bob, strike2), 0);
        assertEq(vault.yMulti().balanceOf(chad, strike3), 0);

        assertEq(vault.yStakedTotal(), 13 ether - 1);

        // simulate yield, stETH balance grows, verify y token receives yield
        simulateYield(0.13 ether + 1);

        assertEq(vault.totalCumulativeYield(), 0.13 ether + 1);
        assertEq(vault.cumulativeYield(epoch1), 0.01 ether);
        assertEq(vault.cumulativeYield(epoch2), 0.04 ether);
        assertEq(vault.cumulativeYield(epoch3), 0.08 ether - 1);

        // move price above strike1, verify redeem via hodl token

        vm.startPrank(alice);
        vm.expectRevert("redeem price");
        vault.redeem(strike1, 1 ether, stake1);
        vm.stopPrank();

        oracle.setPrice(strike1 + 1);

        assertEq(IERC20(stEth).balanceOf(alice), 0 ether);

        vm.startPrank(alice);
        vault.redeem(strike1, 1 ether, stake1);
        vm.stopPrank();

        assertEq(vault.yStakedTotal(), 12 ether - 1);

        // unstaked y tokens should be burned

        assertEq(vault.yMulti().balanceOf(alice, strike1), 0);

        assertEq(IERC20(stEth).balanceOf(alice), 1 ether - 1);
        assertEq(IERC20(stEth).balanceOf(bob), 0);
        assertEq(IERC20(stEth).balanceOf(chad), 0);

        // simulate more yield, verify only epoch2 and epoch3 get it

        simulateYield(0.12 ether);

        assertEq(vault.cumulativeYield(epoch1), 0.01 ether);
        assertEq(vault.cumulativeYield(epoch2), 0.08 ether);
        assertEq(vault.cumulativeYield(epoch3), 0.16 ether - 1);

        // move price above both strike2 and strike3, but only strike3 claims

        oracle.setPrice(strike3 + 1);

        assertEq(IERC20(stEth).balanceOf(chad), 0 ether);

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

        assertEq(IERC20(stEth).balanceOf(alice), 1 ether - 1);
        assertEq(IERC20(stEth).balanceOf(bob), 0);
        assertEq(IERC20(stEth).balanceOf(chad), 4 ether - 1);

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
        assertEq(vault.yMulti().balanceOf(chad, strike3), 0);
        uint256 stake7 = vault.hodlStake(strike3, 8 ether);
        assertEq(vault.yMulti().balanceOf(chad, strike3), 8 ether);
        vault.yMulti().safeTransferFrom(chad, degen, strike3, 4 ether, "");
        vm.stopPrank();

        assertEq(vault.cumulativeYield(epoch4), 0);  // [strike3] unstaked, so no yield

        // simulate yield after y token transfer, verify address level accounting
        vm.startPrank(degen);
        uint256 stake8 = vault.yStake(strike3, 4 ether);
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

        uint256 strike1 = 2000_00000000;
        uint256 strike2 = 3000_00000000;
        uint256 strike3 = 4000_00000000;

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

    function simulateYield(uint256 amount) internal {
        vm.startPrank(whale);
        IERC20(vault.stEth()).transfer(address(vault), amount);
        vm.stopPrank();
    }
}

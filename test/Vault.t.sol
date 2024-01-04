// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol"; 

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IStEth } from "../src/interfaces/IStEth.sol";

import { Vault } from  "../src/Vault.sol";

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
        vault.mint{value: 2 ether}(strike1);
        vm.stopPrank();

        vm.startPrank(bob);
        vault.mint{value: 4 ether}(strike2);
        vm.stopPrank();

        vm.startPrank(chad);
        vault.mint{value: 8 ether}(strike3);
        vm.stopPrank();

        assertEq(vault.hodlMulti().balanceOf(alice, strike1), 2 ether - 1);
        assertEq(vault.hodlMulti().balanceOf(bob, strike1), 0);
        assertEq(vault.hodlMulti().balanceOf(chad, strike1), 0);
        assertEq(vault.yMulti().balanceOf(alice, strike1), 0);
        assertEq(vault.yMulti().balanceOf(bob, strike1), 0);
        assertEq(vault.yMulti().balanceOf(chad, strike1), 0);

        assertEq(vault.hodlMulti().balanceOf(alice, strike2), 0);
        assertEq(vault.hodlMulti().balanceOf(bob, strike2), 4 ether - 1);
        assertEq(vault.hodlMulti().balanceOf(chad, strike2), 0);
        assertEq(vault.yMulti().balanceOf(alice, strike2), 0);
        assertEq(vault.yMulti().balanceOf(bob, strike2), 0);
        assertEq(vault.yMulti().balanceOf(chad, strike2), 0);

        assertEq(vault.hodlMulti().balanceOf(alice, strike3), 0);
        assertEq(vault.hodlMulti().balanceOf(bob, strike3), 0);
        assertEq(vault.hodlMulti().balanceOf(chad, strike3), 8 ether);
        assertEq(vault.yMulti().balanceOf(alice, strike3), 0);
        assertEq(vault.yMulti().balanceOf(bob, strike3), 0);
        assertEq(vault.yMulti().balanceOf(chad, strike3), 0);

        // stake hodl tokens, receive y tokens
        vm.startPrank(alice);
        uint256 stake1 = vault.hodlMulti().stake(strike1, 1 ether);
        vm.stopPrank();

        vm.startPrank(bob);
        uint256 stake2 = vault.hodlMulti().stake(strike2, 4 ether - 1);
        vm.stopPrank();

        vm.startPrank(chad);
        uint256 stake3 = vault.hodlMulti().stake(strike3, 8 ether);
        vm.stopPrank();

        assertEq(vault.hodlMulti().balanceOf(alice, strike1), 1 ether - 1);
        assertEq(vault.yMulti().balanceOf(alice, strike1), 1 ether);

        assertEq(vault.hodlMulti().balanceOf(bob, strike2), 0);
        assertEq(vault.yMulti().balanceOf(bob, strike2), 4 ether - 1);

        assertEq(vault.hodlMulti().balanceOf(chad, strike3), 0);
        assertEq(vault.yMulti().balanceOf(chad, strike3), 8 ether);

        // stake y token
        vm.startPrank(alice);
        vault.yMulti().stake(strike1, 1 ether);
        vm.stopPrank();

        vm.startPrank(bob);
        vault.yMulti().stake(strike2, 4 ether - 1);
        vm.stopPrank();

        vm.startPrank(chad);
        vault.yMulti().stake(strike3, 8 ether);
        vm.stopPrank();

        assertEq(vault.yMulti().balanceOf(alice, strike1), 0);
        assertEq(vault.yMulti().balanceOf(bob, strike2), 0);
        assertEq(vault.yMulti().balanceOf(chad, strike3), 0);

        // simulate yield, stETH balance grows, verify y token receives yield
        simulateYield(0.13 ether + 1);

        assertEq(vault.totalCumulativeYield(), 0.13 ether);
        assertEq(vault.cumulativeYield(strike1), 0.01 ether);
        assertEq(vault.cumulativeYield(strike2), 0.04 ether - 1);
        assertEq(vault.cumulativeYield(strike3), 0.08 ether);

        // move price above strike1, verify redeem via hodl token

        console.log("fail to redeem strike1");

        vm.startPrank(alice);
        vm.expectRevert("V: price");
        vault.redeem(strike1, 1 ether, stake1);
        vm.stopPrank();

        oracle.setPrice(strike1 + 1);

        assertEq(IERC20(stEth).balanceOf(alice), 0 ether);

        vm.startPrank(alice);
        vault.redeem(strike1, 1 ether, stake1);
        vm.stopPrank();

        assertEq(IERC20(stEth).balanceOf(alice), 1 ether - 1);
        assertEq(IERC20(stEth).balanceOf(bob), 0);
        assertEq(IERC20(stEth).balanceOf(chad), 0);

        // simulate more yield, verify only strike2 and strike3 get it

        simulateYield(0.12 ether);

        assertEq(vault.cumulativeYield(strike1), 0.01 ether);
        assertEq(vault.cumulativeYield(strike2), 0.08 ether - 1);
        assertEq(vault.cumulativeYield(strike3), 0.16 ether);

        // move price above both strike2 and strike3, but only strike3 claims

        oracle.setPrice(strike3 + 1);

        assertEq(IERC20(stEth).balanceOf(chad), 0 ether);

        vm.startPrank(chad);
        vault.redeem(strike3, 4 ether, stake3);
        vm.stopPrank();

        assertEq(IERC20(stEth).balanceOf(alice), 1 ether - 1);
        assertEq(IERC20(stEth).balanceOf(bob), 0);
        assertEq(IERC20(stEth).balanceOf(chad), 4 ether - 1);

        simulateYield(0.08 ether);

        assertEq(vault.cumulativeYield(strike1), 0.01 ether);
        assertEq(vault.cumulativeYield(strike2), 0.16 ether - 1);
        assertEq(vault.cumulativeYield(strike3), 0.16 ether);

        // can mint at strike3 again, but only once price goes down
        vm.startPrank(degen);
        vm.expectRevert("V: strike too low");
        vault.mint{value: 4 ether}(strike3);
        vm.stopPrank();

        console.log("");
        console.log("");
        console.log("");
        console.log("");

        oracle.setPrice(strike3 - 1);

        console.log("BEFORE:", vault.cumulativeYield(strike3));

        vm.startPrank(degen);
        vault.mint{value: 4 ether}(strike3);
        vm.stopPrank();

        console.log("");
        console.log("");
        console.log("");
        console.log("");

        console.log("AFTER: ", vault.cumulativeYield(strike3));

        // assertEq(vault.cumulativeYield(strike3), 0.16 ether);

        return;

        // degen gets some yield, verify address level accounting
        
        simulateYield(0.08 ether);

        assertEq(vault.cumulativeYield(strike1), 0.01 ether);
        assertEq(vault.cumulativeYield(strike2), 0.24 ether - 5);
        assertEq(vault.cumulativeYield(strike3), 0.16 ether);

        // transfer y tokens, verify address level accounting

        // simulate yield after y token transfer, verify address level accounting
    }

    function simulateYield(uint256 amount) internal {
        vm.startPrank(whale);
        IERC20(vault.stEth()).transfer(address(vault), amount);
        vm.stopPrank();
    }
}

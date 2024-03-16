// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { BaseTest } from "./BaseTest.sol";

import { IStEth } from "../src/interfaces/IStEth.sol";
import { StETHERC4626 } from "../src/assets/StETHERC4626.sol";


contract StETHERC4626Test is BaseTest {

    function setUp() public {
        init();
    }

    function testAsset() public {
        console.log("testAsset");

        StETHERC4626 asset = new StETHERC4626(steth);

        console.log("asset", address(asset));

        // mint then deposit then redeem
        vm.startPrank(alice);
        IStEth(steth).submit{value: 1 ether}(address(0));
        console.log("before: alice steth       ", IERC20(steth).balanceOf(alice));
        console.log("before: alice asset shares", asset.balanceOf(alice));
        console.log("before: alice max withdraw", asset.maxWithdraw(alice));
        console.log("");
        IERC20(steth).approve(address(asset), 1 ether - 1);
        asset.deposit(1 ether - 1, alice);
        console.log("after:  alice steth       ", IERC20(steth).balanceOf(alice));
        console.log("after:  alice asset shares", asset.balanceOf(alice));
        console.log("after:  alice max withdraw", asset.maxWithdraw(alice));
        console.log("");
        asset.withdraw(1 ether - 2, alice, alice);
        console.log("after:  alice steth       ", IERC20(steth).balanceOf(alice));
        console.log("after:  asset steth       ", IERC20(steth).balanceOf(address(asset)));
        console.log("after:  alice asset shares", asset.balanceOf(alice));
        console.log("after:  alice max withdraw", asset.maxWithdraw(alice));
        vm.stopPrank();
    }

}

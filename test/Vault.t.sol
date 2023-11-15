// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol"; 

import { Vault } from  "../src/Vault.sol";

import { BaseTest } from  "./BaseTest.sol";

contract VaultTest is BaseTest {
    Vault public vault;

    function setUp() public {
        init();
    }

    function testVault() public {
        console.log("Test pleth vault");
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { Vault } from  "../src/Vault.sol";

import { BaseScript } from "./BaseScript.sol";
import { FakeOracle } from  "../test/helpers/FakeOracle.sol";

contract DeployScript is BaseScript {
    using SafeERC20 for IERC20;

    Vault public vault;

    function run() public {
        init();

        vm.startBroadcast(pk);

        console.log("deploy");
        FakeOracle oracle = new FakeOracle();
        oracle.setPrice(1999_00000000);
        console.log("oracle deployed to", address(oracle));
        vault = new Vault(stEth, address(oracle));

        vm.stopBroadcast();

        {
            string memory objName = string.concat("deploy");
            string memory json;

            json = vm.serializeAddress(objName, "address_oracle", address(oracle));
            json = vm.serializeAddress(objName, "address_vault", address(vault));
            json = vm.serializeAddress(objName, "address_yMulti", address(vault.yMulti()));
            json = vm.serializeAddress(objName, "address_hodlMulti", address(vault.hodlMulti()));

            json = vm.serializeString(objName, "contractName_oracle", "IOracle");
            json = vm.serializeString(objName, "contractName_vault", "Vault");
            json = vm.serializeString(objName, "contractName_yMulti", "YMultiToken");
            json = vm.serializeString(objName, "contractName_hodlMulti", "HodlMultiToken");

            vm.writeJson(json, string.concat("./json/deploy-eth.",
                                             vm.envString("NETWORK"),
                                             ".json"));
        }
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";

import "@openzeppelin/contracts/utils/Strings.sol";
import { ERC1155 } from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import { Ownable } from  "@openzeppelin/contracts/access/Ownable.sol";

import { Vault } from "../Vault.sol";
import { YMultiToken } from "./YMultiToken.sol";

contract HodlMultiToken is ERC1155, Ownable {

    uint256 public nextId = 1;
    mapping(uint256 => uint256) public totalSupply;
    mapping(address => bool) public authorized;

    constructor(string memory uri_) ERC1155(uri_) Ownable(msg.sender) { }

    function name(uint256 strike) public view virtual returns (string memory) {
        return string(abi.encodePacked("plETH @ ", Strings.toString(strike / 1e8)));
    }

    function symbol(uint256 strike) public view virtual returns (string memory) {
        return string(abi.encodePacked("plETH @ ", Strings.toString(strike / 1e8)));
    }

    function authorize(address operator) public onlyOwner {
        authorized[operator] = true;
    }

    function safeTransferFrom(address from,
                              address to,
                              uint256 strike,
                              uint256 amount,
                              bytes memory) public override {
        if (from != msg.sender &&
            !isApprovedForAll(from, msg.sender) &&
            !authorized[msg.sender]) {

            revert ERC1155MissingApprovalForAll(msg.sender, from);
        }

        uint256[] memory strikes = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);
        strikes[0] = strike;
        amounts[0] = amount;

        _update(from, to, strikes, amounts);
    }

    function mint(address user, uint256 strike, uint256 amount) public onlyOwner {
        totalSupply[strike] += amount;
        _mint(user, strike, amount, "");
    }

    function burn(address user, uint256 strike, uint256 amount) public onlyOwner {
        totalSupply[strike] -= amount;
        _burn(user, strike, amount);
    }
}

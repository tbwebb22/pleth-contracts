// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";

import { ERC1155 } from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import { Ownable } from  "@openzeppelin/contracts/access/Ownable.sol";

import { Vault } from "../Vault.sol";
import { YMultiToken } from "./YMultiToken.sol";

contract HodlMultiToken is ERC1155, Ownable {

    uint256 public nextId = 1;
    mapping(uint256 => uint256) public totalSupply;
    mapping(address => bool) public authorized;

    constructor(string memory uri_) ERC1155(uri_) Ownable(msg.sender) { }

    function authorize(address operator) public onlyOwner {
        authorized[operator] = true;
    }

    function safeTransferFrom(address from, address to, uint256 id, uint256 value, bytes memory) public override {
        if (from != msg.sender &&
            !isApprovedForAll(from, msg.sender) &&
            !authorized[msg.sender]) {

            revert ERC1155MissingApprovalForAll(msg.sender, from);
        }

        uint256[] memory ids = new uint256[](1);
        ids[0] = id;
        uint256[] memory values = new uint256[](1);
        values[0] = value;

        _update(from, to, ids, values);
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

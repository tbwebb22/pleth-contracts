// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

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

    function safeTransferFrom(address from, address to, uint256 id, uint256 value, bytes memory data) public override {
        address sender = _msgSender();
        if (from != sender &&
            !isApprovedForAll(from, sender) &&
            !authorized[sender]) {

            revert ERC1155MissingApprovalForAll(sender, from);
        }
        _safeTransferFrom(from, to, id, value, data);
    }

    function mint(address user, uint256 strike, uint256 amount) public onlyOwner {
        _mint(user, strike, amount, "");
        totalSupply[strike] += amount;
    }

    function burn(address user, uint256 strike, uint256 amount) public onlyOwner {
        _burn(user, strike, amount);
        totalSupply[strike] -= amount;
    }
}

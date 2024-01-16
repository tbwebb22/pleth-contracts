// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { ERC1155 } from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import { Ownable } from  "@openzeppelin/contracts/access/Ownable.sol";

import { YMultiToken } from "./YMultiToken.sol";
import { Vault } from "./Vault.sol";

contract HodlMultiToken is ERC1155, Ownable {

    uint256 public nextId = 1;

    constructor(string memory uri_) ERC1155(uri_) Ownable(msg.sender) { }

    function mint(address user, uint256 strike, uint256 amount) public onlyOwner {
        _mint(user, strike, amount, "");
    }

    function burn(address user, uint256 strike, uint256 amount) public onlyOwner {
        _burn(user, strike, amount);
    }
}

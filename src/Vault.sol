// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { ERC1155 } from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";

contract Vault is ERC1155 {

    constructor(string memory uri_) ERC1155(uri_) {
    }

}

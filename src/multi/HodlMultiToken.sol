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

    function _asSingletonArrays2(
        uint256 element1,
        uint256 element2
    ) private pure returns (uint256[] memory array1, uint256[] memory array2) {
        /// @solidity memory-safe-assembly
        assembly {
            // Load the free memory pointer
            array1 := mload(0x40)
            // Set array length to 1
            mstore(array1, 1)
            // Store the single element at the next word after the length (where content starts)
            mstore(add(array1, 0x20), element1)

            // Repeat for next array locating it right after the first array
            array2 := add(array1, 0x40)
            mstore(array2, 1)
            mstore(add(array2, 0x20), element2)

            // Update the free memory pointer by pointing after the second array
            mstore(0x40, add(array2, 0x40))
        }
    }

    function safeTransferFrom(address from, address to, uint256 id, uint256 value, bytes memory) public override {
        address sender = _msgSender();

        if (from != sender &&
            !isApprovedForAll(from, sender) &&
            !authorized[sender]) {

            revert ERC1155MissingApprovalForAll(sender, from);
        }

        (uint256[] memory ids, uint256[] memory values) = _asSingletonArrays2(id, value);
        _update(from, to, ids, values);
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

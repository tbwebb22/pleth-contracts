// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { ERC1155 } from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import { Ownable } from  "@openzeppelin/contracts/access/Ownable.sol";

contract YMultiToken is ERC1155, Ownable {

    uint256 public nextId = 1;
    struct Stake {
        address user;
        uint256 timestamp;
        uint256 strike;
        uint256 amount;
    }
    mapping (uint256 => Stake) stakes;

    event Staked(address indexed user,
                 uint256 indexed id,
                 uint256 timestamp,
                 uint256 strike,
                 uint256 amount);

    event Unstaked(address indexed user,
                   uint256 indexed id,
                   uint256 timestamp,
                   uint256 strike,
                   uint256 amount);

    constructor(string memory uri_) ERC1155(uri_) {
    }

    function mint(address user, uint256 strike, uint256 amount) public onlyOwner {
        _mint(user, strike, amount, "");
    }

    function stake(uint256 strike, uint256 amount) public returns (uint256) {
        require(balanceOf(msg.sender, strike) >= amount, "YMT: balance");

        _burn(msg.sender, strike, amount);

        uint256 id = nextId++;
        stakes[id] = Stake({
            user: msg.sender,
            timestamp: block.timestamp,
            strike: strike,
            amount: amount });

        emit Staked(msg.sender,
                    id,
                    block.timestamp,
                    strike,
                    amount);

        return id;
    }

    function unstake(uint256 id, uint256 amount) public {
        Stake storage stk = stakes[id]; 
        require(stk.user == msg.sender, "YMT: user");
        require(stk.amount >= amount, "YMT: amount");

        stk.amount -= amount;
        _mint(msg.sender, stk.strike, amount, "");

        emit Unstaked(msg.sender,
                      id,
                      block.timestamp,
                      stk.strike,
                      amount);
    }

}

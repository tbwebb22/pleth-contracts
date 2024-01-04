// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { ERC1155 } from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import { Ownable } from  "@openzeppelin/contracts/access/Ownable.sol";

import { YMultiToken } from "./YMultiToken.sol";
import { Vault } from "./Vault.sol";

contract HodlMultiToken is ERC1155, Ownable {

    uint256 public nextId = 1;

    YMultiToken public immutable yMulti;
    Vault public immutable vault;

    struct Stake {
        address user;
        uint256 timestamp;
        uint256 strike;
        uint256 amount;
    }
    mapping (uint256 => Stake) public stakes;

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

    event BurnedStake(uint256 indexed id,
                      uint256 amount);

    constructor(string memory uri_, address vault_) ERC1155(uri_) {
        yMulti = new YMultiToken("", vault_);
        vault = Vault(vault_);
    }

    function mint(address user, uint256 strike, uint256 amount) public onlyOwner {
        _mint(user, strike, amount, "");
    }

    function burn(address user, uint256 strike, uint256 amount) public onlyOwner {
        _burn(user, strike, amount);
    }

    function stake(uint256 strike, uint256 amount) public returns (uint256) {
        require(balanceOf(msg.sender, strike) >= amount, "HMT: balance");

        _burn(msg.sender, strike, amount);
        yMulti.mint(msg.sender, strike, amount);

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

    function burnStake(uint256 id, uint256 amount) public onlyOwner {
        Stake storage stk = stakes[id]; 
        require(stk.amount >= amount, "YMT: amount");

        stk.amount -= amount;

        emit BurnedStake(id, amount);
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol"; 

import { ERC1155 } from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import { Ownable } from  "@openzeppelin/contracts/access/Ownable.sol";

import { Vault } from "./Vault.sol";

contract YMultiToken is ERC1155, Ownable {

    Vault public immutable vault;

    uint256 public nextId = 1;
    uint256 public staked;

    // strike -> epoch ID
    mapping (uint256 => uint256) public activeEpochs;
    mapping (uint256 => uint256) public epochEnds;

    struct Stake {
        address user;
        uint256 timestamp;
        uint256 strike;
        uint256 epochId;
        uint256 amount;
    }
    mapping (uint256 => Stake) public stakes;
    mapping (uint256 => uint256) public totalSupply;
    mapping (uint256 => bool) public isPaused;

    mapping (uint256 => uint256) public yieldPerTokenAcc;
    mapping (uint256 => uint256) public cumulativeYieldAcc;

    struct UserInfo {
        uint256 yieldPerTokenClaimed;
        uint256 accClaimable;
    }
    mapping (address => mapping(uint256 => UserInfo)) infos;

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
        vault = Vault(vault_);
    }

    function mint(address user, uint256 strike, uint256 amount) public onlyOwner {
        _mint(user, strike, amount, "");
        totalSupply[strike] += amount;
    }

    function burn(address user, uint256 strike, uint256 amount) public onlyOwner {
        _burn(user, strike, amount);
        totalSupply[strike] -= amount;
    }

    function _yieldPerToken(uint256 strike) internal view returns (uint256) {
        uint256 supply = totalSupply[strike];
        if (supply == 0) return 0;
        uint256 deltaCumulative = isPaused[strike]
            ? 0
            : vault.cumulativeYield(strike) - cumulativeYieldAcc[strike];
        uint256 incr = (deltaCumulative * vault.PRECISION_FACTOR()
                        / supply);
        return yieldPerTokenAcc[strike] + incr;
    }

    function burnStrike(uint256 strike) public returns (uint256) {
        require(msg.sender == address(vault), "only vault");

        // burns all staked tokens at strike via epoch increment
        activeEpochs[strike]++;
        epochEnds[strike] = block.timestamp;
        staked -= totalSupply[strike];
        totalSupply[strike] = 0;
    }

    function stake(uint256 strike, uint256 amount) public returns (uint256) {
        require(balanceOf(msg.sender, strike) >= amount, "YMT: balance");

        _burn(msg.sender, strike, amount);

        if (activeEpochs[strike] == 0) {
            activeEpochs[strike]++;
        }

        uint256 id = nextId++;
        stakes[id] = Stake({
            user: msg.sender,
            timestamp: block.timestamp,
            strike: strike,
            epochId: activeEpochs[strike],
            amount: amount });

        staked += amount;

        emit Staked(msg.sender,
                    id,
                    block.timestamp,
                    strike,
                    amount);

        return id;
    }

    /* function unstake(uint256 id, uint256 amount) public { */
    /*     Stake storage stk = stakes[id];  */
    /*     require(stk.user == msg.sender, "YMT: user"); */
    /*     require(stk.amount >= amount, "YMT: amount"); */

    /*     stk.amount -= amount; */
    /*     _mint(msg.sender, stk.strike, amount, ""); */
    /*     staked -= amount; */

    /*     emit Unstaked(msg.sender, */
    /*                   id, */
    /*                   block.timestamp, */
    /*                   stk.strike, */
    /*                   amount); */
    /* } */

    /* function burnStake(uint256 id, uint256 amount) public onlyOwner { */
    /*     Stake storage stk = stakes[id];  */
    /*     require(stk.amount >= amount, "YMT: amount"); */

    /*     stk.amount -= amount; */

    /*     emit BurnedStake(id, amount); */
    /* } */

    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory strikes,
        uint256[] memory amounts,
        bytes memory data
    ) internal override {

        console.log("beforeTokenTransfer");

        for (uint256 i = 0; i < strikes.length; i++) {
            uint256 strike = strikes[i];
            uint256 ypt = _yieldPerToken(strike);
            /* infos[from].accClaimable = claimable(from); */
            infos[from][strike].yieldPerTokenClaimed = ypt;
            /* infos[to].accClaimable = claimable(to); */
            infos[to][strike].yieldPerTokenClaimed = ypt;
        }
    }
}

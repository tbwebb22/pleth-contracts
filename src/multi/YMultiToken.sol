// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/console.sol"; 

import { ERC1155 } from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import { Ownable } from  "@openzeppelin/contracts/access/Ownable.sol";

import { Vault } from "../Vault.sol";

contract YMultiToken is ERC1155, Ownable {

    Vault public immutable vault;

    uint256 public nextId = 1;
    uint256 public staked;

    mapping (uint256 => mapping(address => uint256)) public balances;
    mapping (uint256 => uint256) public strikeSeqs;

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

    constructor(string memory uri_, address vault_)
        Ownable(msg.sender)
        ERC1155(uri_) {

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

    function balanceOf(address user, uint256 strike) public override view returns (uint256) {
        uint256 seq = strikeSeqs[strike];
        return balances[seq][user];
    }

    function burnStrike(uint256 strike) public {
        require(msg.sender == address(vault), "only vault");
        strikeSeqs[strike]++;
    }

    function _update(address from,
                     address to,
                     uint256[] memory strikes,
                     uint256[] memory values) internal override {

        require(strikes.length == values.length, "mismatched update length");

        address operator = _msgSender();

        for (uint256 i = 0; i < strikes.length; ++i) {
            uint256 strike = strikes[i];
            uint256 value = values[i];
            uint256 seq = strikeSeqs[strike];

            if (from != address(0)) {
                uint256 fromBalance = balances[seq][from];
                require(fromBalance >= value, "insufficient balance");
                unchecked {
                    balances[seq][from] = fromBalance - value;
                }
            }

            if (to != address(0)) {
                balances[seq][to] += value;
            }
        }

        if (strikes.length == 1) {
            uint256 strike = strikes[0];
            uint256 value = values[0];
            emit TransferSingle(operator, from, to, strike, value);
        } else {
            emit TransferBatch(operator, from, to, strikes, values);
        }
    }
}

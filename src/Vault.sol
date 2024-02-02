// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IStEth } from "./interfaces/IStEth.sol";
import { IOracle } from "./interfaces/IOracle.sol";

import { HodlMultiToken } from "./multi/HodlMultiToken.sol";
import { YMultiToken } from "./multi/YMultiToken.sol";
import { HodlToken } from  "./single/HodlToken.sol";


contract Vault {
    using SafeERC20 for IERC20;

    uint256 public constant PRECISION_FACTOR = 1 ether;

    uint32 public nextId = 1;

    IStEth public immutable stEth;
    IOracle public immutable oracle;

    HodlMultiToken public immutable hodlMulti;
    YMultiToken public immutable yMulti;

    mapping (uint256 => address) public deployments;

    struct YStake {
        address user;
        uint256 strike;
        uint256 amount;
        uint256 yieldPerTokenClaimed;
        uint32 epochId;
    }
    mapping (uint32 => YStake) public yStakes;
    mapping (uint256 => uint256) public yStaked;
    mapping (uint256 => uint256) public terminalYieldPerToken;
    uint256 public yStakedTotal;

    struct HodlStake {
        address user;
        uint256 strike;
        uint256 amount;
        uint32 epochId;
    }
    mapping (uint32 => HodlStake) public hodlStakes;

    uint256 public deposits;
    uint256 public claimed;

    // Track yield on per-epoch basis to support cumulativeYield(uint256)
    uint256 public yieldPerTokenAcc;
    uint256 public cumulativeYieldAcc;
    struct EpochInfo {
        uint256 strike;
        uint256 yieldPerTokenAcc;
        uint256 cumulativeYieldAcc;
    }
    mapping (uint256 => EpochInfo) infos;

    // Map strike to active epoch ID
    mapping (uint256 => uint32) public epochs;

    event Triggered(uint256 indexed strike,
                    uint256 indexed epoch,
                    uint256 timestamp);

    event Mint(address indexed user,
               uint256 indexed strike,
               uint256 amount);

    event HodlStaked(address indexed user,
                     uint256 indexed strike,
                     uint256 indexed stakeId,
                     uint256 amount);

    event YStaked(address indexed user,
                  uint256 indexed strike,
                  uint256 indexed stakeId,
                  uint256 amount);

    constructor(address stEth_,
                address oracle_) {
        stEth = IStEth(stEth_);
        oracle = IOracle(oracle_);

        hodlMulti = new HodlMultiToken("");
        yMulti = new YMultiToken("", address(this));
    }

    function deployERC20(uint256 strike) public returns (address) {
        if (deployments[strike] != address(0)) {
            return deployments[strike];
        }

        HodlToken hodl = new HodlToken(address(hodlMulti), strike);
        hodlMulti.authorize(address(hodl));

        deployments[strike] = address(hodl);

        return address(hodl);
    }

    function _min(uint256 x, uint256 y) internal pure returns (uint256) {
        return x < y ? x : y;
    }

    function _checkpoint(uint256 epoch) internal {
        uint256 ypt = yieldPerToken();
        uint256 total = totalCumulativeYield();

        infos[epoch].cumulativeYieldAcc = cumulativeYield(epoch);
        infos[epoch].yieldPerTokenAcc = ypt;

        yieldPerTokenAcc = ypt;
        cumulativeYieldAcc = total;
    }

    function mint(uint256 strike) external payable {
        require(oracle.price(0) <= strike, "strike too low");

        uint256 before = stEth.balanceOf(address(this));
        stEth.submit{value: msg.value}(address(0));
        uint256 delta = stEth.balanceOf(address(this)) - before;
        deposits += delta;

        // create the epoch if needed
        if (epochs[strike] == 0) {
            infos[nextId].strike = strike;
            epochs[strike] = nextId++;
        }

        // track per-epoch yield accumulation
        _checkpoint(epochs[strike]);

        // mint hodl, y is minted on hodl stake
        hodlMulti.mint(msg.sender, strike, delta);

        emit Mint(msg.sender, strike, delta);
    }

    function canRedeem(uint32 stakeId) public view returns (bool) {
        HodlStake storage stk = hodlStakes[stakeId];

        // Check if price is currently above strike
        if (oracle.price(0) >= stk.strike) {
            return true;
        }

        // Check if this is a passed epoch
        if (stk.epochId != epochs[stk.strike]) {
            return true;
        }

        return false;
    }

    function redeem(uint256 strike, uint256 amount, uint32 stakeId) external {
        if (stakeId == 0) {
            // Redeem via tokens
            require(hodlMulti.balanceOf(msg.sender, strike) >= amount);
            require(yMulti.balanceOf(msg.sender, strike) >= amount);

            hodlMulti.burn(msg.sender, strike, amount);
            yMulti.burn(msg.sender, strike, amount);
        } else {
            // Redeem via staked hodl token
            HodlStake storage stk = hodlStakes[stakeId];

            require(stk.user == msg.sender, "redeem user");
            require(stk.amount >= amount, "redeem amount");
            require(stk.strike == strike, "redeem strike");
            require(canRedeem(stakeId), "cannot redeem");

            // burn the specified hodl stake
            stk.amount -= amount;

            uint256 epochId = epochs[strike];

            if (epochId != 0) {
                // checkpoint this strike, to prevent yield accumulation
                _checkpoint(epochId);

                // record the ypt at redemption time
                terminalYieldPerToken[epochId] = yieldPerToken();

                // update accounting for staked y tokens
                yStakedTotal -= yStaked[epochId];
                yStaked[epochId] = 0;

                // don't checkpoint again, trigger new epoch
                epochs[strike] = 0;
            }

            // burn all staked y tokens at that strike
            yMulti.burnStrike(strike);
        }

        amount = _min(amount, stEth.balanceOf(address(this)));
        stEth.transfer(msg.sender, amount);

        deposits -= amount;
    }

    function yStake(uint256 strike, uint256 amount) public returns (uint32) {

        require(yMulti.balanceOf(msg.sender, strike) >= amount, "y stake balance");
        uint32 epochId = epochs[strike];

        _checkpoint(epochId);

        yMulti.burn(msg.sender, strike, amount);
        uint32 id = nextId++;

        uint256 ypt = yieldPerToken();
        yStakes[id] = YStake({
            user: msg.sender,
            strike: strike,
            epochId: epochId,
            amount: amount,
            yieldPerTokenClaimed: ypt });
        yStaked[epochId] += amount;
        yStakedTotal += amount;

        emit YStaked(msg.sender, strike, id, amount);

        return id;
    }

    function _stakeYpt(uint32 stakeId) internal view returns (uint256) {
        YStake storage stk = yStakes[stakeId];
        uint256 ypt;
        if (epochs[stk.strike] == stk.epochId) {
            // active epoch
            ypt = yieldPerToken() - stk.yieldPerTokenClaimed;
        } else {
            // passed epoch
            ypt = terminalYieldPerToken[stk.epochId] - stk.yieldPerTokenClaimed;
        }
        return ypt;
    }

    function claimable(uint32 stakeId) public view returns (uint256) {
        YStake storage stk = yStakes[stakeId];
        uint256 ypt = _stakeYpt(stakeId);
        return ypt * stk.amount / PRECISION_FACTOR;
    }


    function claim(uint32 stakeId) public {
        YStake storage stk = yStakes[stakeId];
        require(stk.user == msg.sender, "y claim user");
        uint256 amount = _min(claimable(stakeId), stEth.balanceOf(address(this)));

        stk.yieldPerTokenClaimed = _stakeYpt(stakeId);
        stEth.transfer(msg.sender, amount);
        claimed += amount;
    }

    function hodlStake(uint256 strike, uint256 amount, address user) public returns (uint32) {
        require(hodlMulti.balanceOf(msg.sender, strike) >= amount, "hodl stake balance");

        hodlMulti.burn(msg.sender, strike, amount);
        yMulti.mint(msg.sender, strike, amount);

        uint32 id = nextId++;
        hodlStakes[id] = HodlStake({
            user: user,
            strike: strike,
            epochId: epochs[strike],
            amount: amount });

        emit HodlStaked(msg.sender, strike, id, amount);

        return id;
    }

    function yieldPerToken() public view returns (uint256) {
        if (yStakedTotal == 0) return 0;
        uint256 deltaCumulative = totalCumulativeYield() - cumulativeYieldAcc;
        uint256 incr = deltaCumulative * PRECISION_FACTOR / yStakedTotal;
        return yieldPerTokenAcc + incr;
    }

    function cumulativeYield(uint256 epochId) public view returns (uint256) {
        require(epochId < nextId, "invalid epoch");

        uint256 ypt;
        uint256 strike = infos[epochId].strike;
        if (epochs[strike] == epochId) {
            // active epoch
            ypt = yieldPerToken() - infos[epochId].yieldPerTokenAcc;
        } else {
            // passed epoch
            ypt = terminalYieldPerToken[epochId] - infos[epochId].yieldPerTokenAcc;
        }

        return (infos[epochId].cumulativeYieldAcc +
                yStaked[epochId] * ypt / PRECISION_FACTOR);
    }

    function totalCumulativeYield() public view returns (uint256) {
        uint256 delta = stEth.balanceOf(address(this)) - deposits;
        uint256 result = delta + claimed;
        return result;
    }
}

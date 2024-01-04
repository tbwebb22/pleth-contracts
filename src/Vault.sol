// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol"; 

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IStEth } from "./interfaces/IStEth.sol";
import { IOracle } from "./interfaces/IOracle.sol";

import { HodlMultiToken } from "./HodlMultiToken.sol";
import { YMultiToken } from "./YMultiToken.sol";

contract Vault {
    using SafeERC20 for IERC20;

    uint256 public constant PRECISION_FACTOR = 1 ether;

    IStEth public immutable stEth;
    IOracle public immutable oracle;

    HodlMultiToken public immutable hodlMulti;
    YMultiToken public immutable yMulti;

    uint256 public deposits;
    bool public didTrigger = false;

    mapping (uint256 => uint256) public activeEpochs;
    mapping (uint256 => uint256) public epochEnds;

    uint256 public claimed;

    // Track yield on per-strike basis to support cumulativeYield(uint256)
    uint256 public yieldPerTokenAcc;
    uint256 public cumulativeYieldAcc;
    struct StrikeInfo {
        uint256 yieldPerTokenClaimed;
        uint256 accClaimable;
    }
    mapping (uint256 => StrikeInfo) infos;

    event Triggered(uint256 indexed strike,
                    uint256 timestamp);


    constructor(address stEth_,
                address oracle_) {
        stEth = IStEth(stEth_);
        oracle = IOracle(oracle_);

        hodlMulti = new HodlMultiToken("", address(this));
        yMulti = hodlMulti.yMulti();
    }

    function _min(uint256 x, uint256 y) internal pure returns (uint256) {
        return x < y ? x : y;
    }

    function trigger(uint256 strike, uint80 roundId) external {
        uint256 epochId = activeEpochs[strike];
        require(epochEnds[epochId] == 0, "V: already triggered");
        require(oracle.timestamp(roundId) >= epochEnds[epochId - 1], "V: old round");
        require(oracle.price(roundId) >= strike, "V: price low");

        epochEnds[epochId] = block.timestamp;
        activeEpochs[strike] += 1;

        emit Triggered(strike, block.timestamp);
    }

    function _claimable(uint256 strike) internal returns (uint256) {
        uint256 ypt = _yieldPerToken();

        uint256 supply = yMulti.totalSupply(strike);
        
        return (supply * ypt / PRECISION_FACTOR
                + infos[strike].accClaimable
                - infos[strike].yieldPerTokenClaimed);
    }

    function _checkpoint(uint256 strike) internal {
        uint256 ypt = _yieldPerToken();
        uint256 total = totalCumulativeYield();

        infos[strike].accClaimable = _claimable(strike);
        infos[strike].yieldPerTokenClaimed = ypt;

        yieldPerTokenAcc = ypt;
        cumulativeYieldAcc = total;
    }

    function mint(uint256 strike) external payable {
        uint256 before = stEth.balanceOf(address(this));
        stEth.submit{value: msg.value}(address(0));
        uint256 delta = stEth.balanceOf(address(this)) - before;
        deposits += delta;

        // track per-strike yield accumulation
        _checkpoint(strike);

        // mint hodl, y is minted on hodl stake
        hodlMulti.mint(msg.sender, strike, delta);

        // epoch accounting
        uint256 epochId = activeEpochs[strike];
        if (epochId == 0) {
            epochEnds[0] = block.timestamp;
            activeEpochs[strike] = 1;
        }
    }

    function redeem(uint256 strike,
                    uint256 amount,
                    uint256 stakeId) external {

        if (stakeId == 0) {
            // Redeem via tokens
            require(hodlMulti.balanceOf(msg.sender, strike) >= amount);
            require(yMulti.balanceOf(msg.sender, strike) >= amount);

            hodlMulti.burn(msg.sender, strike, amount);
            yMulti.burn(msg.sender, strike, amount);
        } else {
            // Redeem via staked hodl token
            (address hmUser,
             uint256 hmTimestamp,
             uint256 hmStrike,
             uint256 hmAmount) = hodlMulti.stakes(stakeId);

            require(hmUser == msg.sender, "V: user");
            require(hmAmount >= amount, "V: amount");
            require(hmStrike == strike, "V: strike");
            require(block.timestamp >= hmTimestamp, "V: timestamp");
            require(oracle.price(0) >= hmStrike, "V: price");

            // burn the specified hodl stake
            hodlMulti.burnStake(stakeId, amount);

            // checkpoint this strike, to prevent yield accumulation
            _checkpoint(hmStrike);

            // burn all staked y tokens at that strike
            yMulti.burnStrike(hmStrike);
        }

        amount = _min(amount, stEth.balanceOf(address(this)));
        stEth.transfer(msg.sender, amount);

        deposits -= amount;
    }

    function disburse(address recipient, uint256 amount) external {
        require(msg.sender == address(yMulti));

        IERC20(stEth).safeTransfer(recipient, amount);
        claimed += amount;
    }

    function _yieldPerToken() internal view returns (uint256) {
        uint256 staked = yMulti.staked();
        if (staked == 0) return 0;
        uint256 deltaCumulative = totalCumulativeYield() - cumulativeYieldAcc;
        uint256 incr = deltaCumulative * PRECISION_FACTOR / staked;
        return yieldPerTokenAcc + incr;
    }

    function cumulativeYield(uint256 strike) external view returns (uint256) {
        uint256 ypt = _yieldPerToken();
        return (infos[strike].accClaimable +
                yMulti.totalSupply(strike) * ypt / PRECISION_FACTOR);
    }

    function totalCumulativeYield() public view returns (uint256) {
        uint256 delta = stEth.balanceOf(address(this)) - deposits;
        uint256 result = delta + claimed;
        return result;
    }
}

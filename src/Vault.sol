// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { IStEth } from "./interfaces/IStEth.sol";

import { HodlMultiToken } from "./HodlMultiToken.sol";
import { YMultiToken } from "./YMultiToken.sol";

contract Vault {

    IStEth public immutable stEth;

    HodlMultiToken public hodlMulti;
    YMultiToken public yMulti;

    uint256 public deposits;
    bool public didTrigger = false;

    constructor(address stEth_) {
        stEth = IStEth(stEth_);

        hodlMulti = new HodlMultiToken("");
        yMulti = new YMultiToken("");
    }

    function mint(uint256 strike) external payable {
        uint256 before = stEth.balanceOf(address(this));
        stEth.submit{value: msg.value}(address(0));
        uint256 delta = stEth.balanceOf(address(this)) - before;
        deposits += delta;

        // mint hodl first for proper accounting
        hodlMulti.mint(msg.sender, strike, delta);
        yMulti.mint(msg.sender, strike, delta);
    }

    function redeem(uint256 strike, uint256 amount) external {
        /* require(yMulti.balanceOf(msg.sender, strike) >= amount); */
        /* require(hodlMulti.balanceOf(msg.sender, strike) >= amount); */

        /* // burn hodl first for proper accounting */
        /* hodlMulti.burn(msg.sender, strike, amount); */
        /* if (!didTrigger) { */
        /*     yMulti.burn(msg.sender, strike, amount); */
        /* } */

        /* amount = _min(amount, stEth.balanceOf(address(this))); */
        /* stEth.transfer(msg.sender, amount); */

        /* deposits -= amount; */
    }

}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { YMultiToken } from "./YMultiToken.sol";

contract HodlMultiToken is YMultiToken {

    constructor(string memory uri_) YMultiToken(uri_) {
    }

}

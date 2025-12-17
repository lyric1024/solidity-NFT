// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "./NFTAuction.sol";

/*
    测试合约升级
*/
contract NFTAuctionV2 is NFTAuction {
    // 新增函数
    function HelloWorld() public pure returns (string memory) {
        return "Hello World";
    }
}

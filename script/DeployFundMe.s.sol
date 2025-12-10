// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {FundMe} from "../src/FundMe.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployFundMe is Script {
    //run() 是脚本入口
    //部署脚本返回 FundMe 地址
    function run() external returns (FundMe) {
        //根据链自动选择预言机地址
        //startBroadcast之前的代码都是本地执行，不会上链。不会花gas费
        HelperConfig helperConfig = new HelperConfig();
        address priceFeed = helperConfig.activeNetworkConfig();

        //开启广播（让链上真实执行）
        //从现在开始，把下面的代码 真的发交易到链上
        vm.startBroadcast();
        FundMe fundMe = new FundMe(priceFeed);
        //结束广播，后面的代码就不再发送交易。
        vm.stopBroadcast();
        return fundMe;
    }
}

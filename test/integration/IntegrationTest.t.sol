// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {FundMe} from "../../src/FundMe.sol";
import {DeployFundMe} from "../../script/DeployFundMe.s.sol";
import {FundFundMe, WithdrawFundMe} from "../../script/Interactions.s.sol";

contract IntegrationTest is Test {
    FundMe fundMe;

    //生成一个新地址 就是创建一个假的地址
    address USER = makeAddr("user");
    uint256 constant SEND_VALUE = 1e18;
    uint256 constant START_BALANCE = 100e18;
    uint256 constant GAS_PRICE = 1;

    function setUp() external {
        //部署合约的脚本
        //默认的EOA账户部署的的->所有合约的拥有者就是默认账户
        DeployFundMe deployFundMe = new DeployFundMe();
        fundMe = deployFundMe.run();
        //伪造一个地址给他充钱
        vm.deal(USER, START_BALANCE);
    }

    function testUserCanFundInteactions() public {
        FundFundMe fundFundMe = new FundFundMe();
        //默认的EOA账户给合约打钱
        fundFundMe.fundFundme(address(fundMe));

        //输出合约的拥有者
        console.log("FundMe owner: %s", fundMe.getOwner());
        //第一个捐钱的人地址
        console.log("FundMe funder person address : %s", fundMe.getFunder(0));

        WithdrawFundMe withdrawFundMe = new WithdrawFundMe();
        //这里的msg.sender也是默认账户
        withdrawFundMe.withdrawFundMe(address(fundMe));
        //合约地址余额是0
        assert(address(fundMe).balance == 0);
        console.log(
            "FundMe contract balance after withdraw: ",
            address(fundMe).balance
        );
    }
}

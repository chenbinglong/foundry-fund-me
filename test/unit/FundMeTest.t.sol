// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {FundMe} from "../../src/FundMe.sol";
import {DeployFundMe} from "../../script/DeployFundMe.s.sol";

contract FundMeTest is Test {
    FundMe fundMe;

    //生成一个新地址 就是创建一个假的地址
    address USER = makeAddr("user");

    uint256 constant SEND_VALUE = 1e18;

    uint256 constant START_BALANCE = 100e18;

    uint256 constant GAS_PRICE = 1;

    function setUp() external {
        //测试脚本
        DeployFundMe deployFundMe = new DeployFundMe();
        fundMe = deployFundMe.run();
        vm.deal(USER, START_BALANCE);
    }

    function testMinimumUsdIsFive() public {
        assertEq(fundMe.MINIMUM_USD(), 5 * 10 ** 18);
    }

    function testOwnerIsMsgSender() public {
        //FundMeTest 部署了一个 FundMe
        //那么FundMe的合约拥有者就是FundMeTest合约的地址
        //msg.sender = 调用 testOwnerIsMsgSender() 的发起者。这个人就是forge test 自动给你模拟出来的 EOA 地址（像一个假人的钱包）
        // 不是不是 FundMeTest，也不是 FundMe。 就是一个临时的测试账户

        //之前 owner 是： FundMeTest 合约部署 FundMe → msg.sender = FundMeTest
        //现在 owner 是： run() 里 startBroadcast 后 → msg.sender = 你本地的默认账户

        //之前部署FundMe的是FundMeTest 合约 ->所以 owner 是 FundMeTest 合约地址。address(this)就是合约的地址
        //现在部署是通过DeployFundMe部署的(vm.startBroadcast() 部署 FundMe → owner = 你的“外部账户地址” = msg.sender)
        //“通过 vm.startBroadcast 部署 → owner = 外部账户地址”
        console.log("address:", address(this));
        console.log("fundMe.getOwner:", fundMe.getOwner());
        console.log("msg.sender:", msg.sender);
        // assertEq(fundMe.getOwner(), address(this));
        assertEq(fundMe.getOwner(), msg.sender);
    }

    function testPriceFeedVersionIsAccurate() public {
        //拉取失败: 因为预言机的地址
        //0x694AA1769357215DE4FAC081bf1f309aDC325306 是 Sepolia 链上的 Chainlink AggregatorV3。
        // 但你的测试环境是 Anvil（本地链）。 本地链根本不存在这个 Chainlink 合约
        // 所以 getVersion() 会 revert 所以测试失败
        // 解决方案: 把 Sepolia 的链状态复制一份（snapshot）到你的本地
        // 本地就会拥有和 Sepolia 一样的合约、地址、数据
        // 包括 Chainlink AggregatorV3 合约
        // fork后的0x6这个地址合约就存在了 。 getVersion就不会失败了
        // fork测试执行: forge test --mt testPriceFeedVersionIsAccurate --fork-url $SEPOLIA_RPC_URL
        // --mt = "match test":只跑你指定的测试，提高速度。
        // 缺点:fork测试慢、贵、浪费RPC调用额度

        uint256 version = fundMe.getVersion();
        console.log("version:", version);
        if (block.chainid == 11155111) {
            assertEq(version, 4);
        } else if (block.chainid == 1) {
            assertEq(version, 6);
        } else {
            //本地anvil链部署的MockV3Aggregator
            assertEq(version, 40);
        }
    }

    function testFundFailsWithoutEnoughEth() public {
        //这个函数的作用:期待下面的代码会revert
        // 如果 fund() 确实 revert → ✔️ 测试通过 ;  没有 revert → ❌ 测试失败 ;
        vm.expectRevert();
        //value: 10e16 就是给合约发送一个1ETH
        //( ) = 传给函数的参数
        //{ } = 传给交易本身的参数（value、gas、sender 等）
        // fundMe.fund{value: 10e16}();
        fundMe.fund();
    }

    //Foundry 的 Cheatcodes = 在测试环境里给你“超能力”的特殊函数
    //（让你可以修改 EVM 状态、模拟用户、模拟失败、改余额等等）
    // 就是方便测试的
    function testFundUpdatesFundedDataStructure() public {
        //下一个交易的 msg.sender 变成这个地址。
        vm.prank(USER);
        //value: 1e18 就是给合约发送一个1ETH
        // 这里fund的人是谁?
        fundMe.fund{value: SEND_VALUE}();
        //断言 s_addressToAmountFunded[msg.sender] == 1e18
        // console.log("msg.sender:", msg.sender); // msg.sender是系统给的虚拟账户
        // console.log("address:", address(this)); // address(this)是FundMeTest合约地址
        console.log("address:", USER);
        uint256 amountFunded = fundMe.getAddressToAmountFunded(USER);
        assertEq(amountFunded, SEND_VALUE);
    }

    //测试 funders 是否加入 msg.sender
    function testAddsFunderToArrayOfFunders() public {
        //这段代码内让下一个交易的 msg.sender 变成 USER 地址。
        vm.startPrank(USER);
        fundMe.fund{value: SEND_VALUE}();
        vm.stopPrank();

        //断言 funder 数组的第0个元素是 USER 地址
        address funder = fundMe.getFunder(0);
        assertEq(funder, USER);
    }

    //测试 withdraw 权限。非 owner 不允许提款。
    function testOnlyOwnerCanWithdraw() public funded {
        //测试用户捐赠
        vm.prank(USER);
        fundMe.fund{value: SEND_VALUE}();

        vm.expectRevert();
        //测试用户提取 期望失败的
        vm.prank(USER);
        fundMe.withdraw();
    }

    //测试owner 提款功能
    function testWithdrawWithASingleFunder() public funded {
        //arrage(准备阶段）)
        uint256 fundeMeBalance = address(fundMe).balance;
        console.log("address balance:", fundeMeBalance);
        uint256 ownerBalance = fundMe.getOwner().balance;
        console.log("address owner start balance:", ownerBalance);

        //Act(执行阶段)
        // uint256 gasStart = gasleft(); // 1000
        // //模拟测试gas价格
        // vm.txGasPrice(GAS_PRICE);

        vm.startPrank(fundMe.getOwner());
        fundMe.withdraw(); // 200
        uint256 endingOwnerBalance = fundMe.getOwner().balance;
        console.log(
            "address owner withdraw after balance::",
            endingOwnerBalance
        );
        vm.stopPrank();

        // uint256 gasEnd = gasleft(); //那么剩下800
        // uint256 gasUsed = (gasStart - gasEnd) * tx.gasprice; //消耗的gas = 200
        // console.log("gasUsed:", gasUsed);

        // Assert(断言阶段)
        assertEq(address(fundMe).balance, 0);
        assertEq(fundeMeBalance + ownerBalance, endingOwnerBalance);
    }

    //测试owner 提款功能
    function testWithdrawWithAMulFunder() public {
        uint160 numberOfFunders = 10;
        uint160 startingFunderIndex = 1;

        for (uint160 i = startingFunderIndex; i < numberOfFunders; i++) {
            //vm.prank(address(i)) 让下一个交易的 msg.sender 变成 address(i) 地址。
            // vm.prank(address(i));
            // vm.deal
            //hoax = prank和deal
            //address(i) 会把 uint160 i 转成地址
            //只有  address(0)
            hoax(address(i), SEND_VALUE);
            fundMe.fund{value: SEND_VALUE}();
        }

        //当前合约拥有者的金额
        uint256 ownerBalance = fundMe.getOwner().balance;
        console.log("address owner start balance:", ownerBalance);

        //当前合约地址的金额
        uint256 addressBalance = address(fundMe).balance;
        console.log("address balance:", addressBalance);

        //Act(执行阶段)
        vm.startPrank(fundMe.getOwner());
        fundMe.withdraw();
        vm.stopPrank();

        // Assert(断言阶段)
        assertEq(address(fundMe).balance, 0);
        assertEq(ownerBalance + addressBalance, fundMe.getOwner().balance);
    }

    //测试owner cheap提款功能
    function testWithdrawWithAMulFunderCheap() public {
        uint160 numberOfFunders = 10;
        uint160 startingFunderIndex = 1;

        for (uint160 i = startingFunderIndex; i < numberOfFunders; i++) {
            //vm.prank(address(i)) 让下一个交易的 msg.sender 变成 address(i) 地址。
            // vm.prank(address(i));
            // vm.deal
            //hoax = prank和deal
            //address(i) 会把 uint160 i 转成地址
            //只有  address(0)
            hoax(address(i), SEND_VALUE);
            fundMe.fund{value: SEND_VALUE}();
        }

        //当前合约拥有者的金额
        uint256 ownerBalance = fundMe.getOwner().balance;
        console.log("address owner start balance:", ownerBalance);

        //当前合约地址的金额
        uint256 addressBalance = address(fundMe).balance;
        console.log("address balance:", addressBalance);

        //Act(执行阶段)
        vm.startPrank(fundMe.getOwner());
        fundMe.cheapWithdraw();
        vm.stopPrank();

        // Assert(断言阶段)
        assertEq(address(fundMe).balance, 0);
        assertEq(ownerBalance + addressBalance, fundMe.getOwner().balance);
    }

    function testPrintStorageData() public {
        //forge test --mt testPrintStorageData -vv
        for (uint256 i = 0; i < 3; i++) {
            bytes32 value = vm.load(address(fundMe), bytes32(i));
            console.log("Value at location", i, ":");
            console.logBytes32(value);
        }
        console.log("PriceFeed address:", address(fundMe.getPriceFeed()));
    }

    //等于一个通用的 funtion函数
    modifier funded() {
        vm.prank(USER);
        fundMe.fund{value: SEND_VALUE}();
        //合约地址的金额 > 0
        assert(address(fundMe).balance > 0);
        _;
    }
}

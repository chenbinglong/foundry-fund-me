// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {PriceConverter} from "./PriceConverter.sol";
import {console} from "forge-std/console.sol";

error FundMe_NotOwner();

contract FundMe {
    //这个语意代表PriceConverter库中的函数可以直接作用于uint256类型的变量
    //还是比较有意思的
    using PriceConverter for uint256;

    //所有状态storage变量建议以 s_ 开头
    //private的变量比public的变量节省gas；但是外部访问不了合约的这两个变量
    //public会自动生成get函数的。如果要让外部访问就自己写get函数
    //好处:自己控制get函数、安全、节约gas
    mapping(address => uint256) private s_addressToAmountFunded;
    address[] private s_funders;

    // forge-lint: disable-next-line(mixed-case-variable)
    //不可变的变量都用I开头
    address private immutable i_owner;
    uint256 public constant MINIMUM_USD = 5 * 10 ** 18;

    AggregatorV3Interface private s_priceFeed;

    //构造函数接受prcieFeed地址
    constructor(address priceFeedAddress) {
        i_owner = msg.sender;
        s_priceFeed = AggregatorV3Interface(priceFeedAddress);
    }

    function fund() public payable {
        //断言募捐的最小金额(发送过来的是数字货币需要转换为美金对比(chainlink获取真实世界的数据))
        require(
            msg.value.getConversionRate(s_priceFeed) >= MINIMUM_USD,
            "You need to spend more ETH!"
        );

        //记录每个募集人捐的金额
        s_addressToAmountFunded[msg.sender] += msg.value;
        //记录募集人
        s_funders.push(msg.sender);
    }

    function getVersion() public view returns (uint256) {
        // 合约地址是硬编码。所以需要重构一下代码
        // AggregatorV3Interface priceFeed = AggregatorV3Interface(
        //     0x694AA1769357215DE4FAC081bf1f309aDC325306
        // );
        return s_priceFeed.version();
    }

    modifier onlyOwner() {
        //断言发起交易的人是不是合约的作者
        if (msg.sender != i_owner) revert FundMe_NotOwner();
        _;
    }

    function cheapWithdraw() public onlyOwner {
        //清空募集人记录和捐款记录
        //这里只读了一次 所以比最开始的提取函数要节约gas，捐赠人越多越明显
        uint256 funderLength = s_funders.length;
        for (
            uint256 funderIndex = 0;
            funderIndex < funderLength;
            funderIndex++
        ) {
            address funder = s_funders[funderIndex];
            s_addressToAmountFunded[funder] = 0;
        }
        s_funders = new address[](0);

        //合约金额转移到合约作者账户中
        // call
        (bool callSuccess, ) = payable(msg.sender).call{
            value: address(this).balance
        }("");
        //断言是否成功
        require(callSuccess, "Call failed");
    }

    //提取合约中的资金的人必须是合约的作者
    function withdraw() public onlyOwner {
        //清空募集人记录和捐款记录
        console.log("Funders msg.send: %s", msg.sender);
        for (
            uint256 funderIndex = 0;
            funderIndex < s_funders.length;
            funderIndex++
        ) {
            address funder = s_funders[funderIndex];
            s_addressToAmountFunded[funder] = 0;
        }
        s_funders = new address[](0);

        //合约金额转移到合约作者账户中
        // call
        // 要给某个地址发钱，这个地址必须是payable类型的
        (bool callSuccess, ) = payable(msg.sender).call{
            value: address(this).balance
        }("");
        //断言是否成功
        require(callSuccess, "Call failed");
    }

    //根据地址得到捐赠的金额
    function getAddressToAmountFunded(
        address fundingAddress
    ) external view returns (uint256) {
        return s_addressToAmountFunded[fundingAddress];
    }

    //view表示这个函数不会修改区块链上的数据，但是会读取区块链上的数据
    //根据index 得到地址
    function getFunder(uint256 index) external view returns (address) {
        return s_funders[index];
    }

    //合约拥有者
    function getOwner() external view returns (address) {
        return i_owner;
    }

    function getPriceFeed() public view returns (AggregatorV3Interface) {
        return s_priceFeed;
    }

    fallback() external payable {
        fund();
    }

    receive() external payable {
        fund();
    }
}

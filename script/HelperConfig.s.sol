// SPDX-License-Identifier: MIT

// 1.在我们本地链部署一个mock
// 2.跟踪不同链的预言机地址
// Sepolia ETH/USD
// Mainnet ETH/USD
// Goerli ETH/USD
// 3.在部署脚本中根据链ID选择预言机地址
// 4.在测试脚本中部署mock预言机

pragma solidity ^0.8.20;
import {Script} from "forge-std/Script.sol";
import {FundMe} from "../src/FundMe.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";

contract HelperConfig is Script {
    //得到激活的配置
    NetworkConfig public activeNetworkConfig;

    uint8 public constant DECIMALS = 8;
    int256 public constant INITIAL_PRICE = 2000e8;

    //根据链ID选择配置
    constructor() {
        //block.chainid 是 Solidity 全局变量，表示当前链的ID
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaEthConfig();
        } else if (block.chainid == 1) {
            activeNetworkConfig = getMainnetEthConfig();
        } else {
            activeNetworkConfig = getAnvilEthConfig();
        }
    }

    //因为未来可能有多个链，每条链需要多个地址，比如：
    //priceFeed 地址、weth 地址、usdc 地址、uniswap router 地址
    struct NetworkConfig {
        //目前就存储一个预言机的地址
        address priceFeed;
    }

    //Sepolia的配置

    //函数权限（pure / view / 非 pure&view）
    //pure：不读链、不写链，只能读 calldat/memory，只做计算。
    //view：可以读链（storage），不能写链。
    //普通函数：可以读链、也可以写链。

    //数据存储位置（storage / memory / calldata）
    //storage：链上永久数据。
    //memory：临时内存变量，执行期间存在。
    //calldata：外部输入，只读，不可修改。
    function getSepoliaEthConfig() public pure returns (NetworkConfig memory) {
        NetworkConfig memory sepoliaConfig = NetworkConfig({
            priceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306
        });
        return sepoliaConfig;
    }

    function getMainnetEthConfig() public pure returns (NetworkConfig memory) {
        NetworkConfig memory ethConfig = NetworkConfig({
            priceFeed: 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419
        });
        return ethConfig;
    }

    function getAnvilEthConfig() public returns (NetworkConfig memory) {
        //避免重复部署mock
        // address(0) 是0地址
        if (activeNetworkConfig.priceFeed != address(0)) {
            return activeNetworkConfig;
        }

        vm.startBroadcast();
        MockV3Aggregator mockPriceFeed = new MockV3Aggregator(
            DECIMALS,
            INITIAL_PRICE
        );

        // 小数位 = 8，价格 = 2000 * 10^8
        vm.stopBroadcast();
        //上面执行完成就会部署一个 MockV3Aggregator 合约
        //后面的不需要上链
        //这样 DeployFundMe 就知道：“在本地链时，使用这个 mock 地址”。
        //Anvil 链本地没有真实 Chainlink → HelperConfig 自动部署 MockV3Aggregator
        //→ FundMe 使用 mock 地址 → 本地测试无需 fork 全链。
        NetworkConfig memory anvilConfig = NetworkConfig({
            priceFeed: address(mockPriceFeed)
        });
        return anvilConfig;
    }
}

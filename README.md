## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

- **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
- **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
- **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
- **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```


### 本地笔记1
本地测试的时候通过chainlink拿不到真实世界的数据
因为forge test没有指定链的时候默认就是本地的anvil链

解决方案:
(1)fork. 把 Sepolia 的链状态复制一份（snapshot）到你的本地
(2)本地就会拥有和 Sepolia 一样的合约、地址、数据. 包括Chainlink AggregatorV3的合约
(3)此时去getVersion就可以得到数据了
(4)测试: forge test --mt testPriceFeedVersionIsAccurate -vvv --fork-url $SEPOLIA_RPC_URL

原理:
在本地自动启动一个 Anvil（模拟 EVM），但它的链状态是从 Sepolia RPC 拉下来的真实数据。
把 Sepolia 链克隆一份到本地，然后在本地这份克隆链上跑你的测试。
按需加载链上的状态。测试中访问了什么合约就拉什么合约的。

### 本地笔记1-mock一个预言机
让所有测试都能在本地 Anvil 运行，不再依赖 Sepolia，不再需要 fork 模式。
mock: 在本地模拟一个“假的 Chainlink 价格预言机”。
本地 Mock理由: 本地fork测试慢
解决方法：在本地自动部署一个 MockPriceFeed，让它假装是 Chainlink 合约。这样就无需去fork链了。


### cheatcode 
伪代码测试

### chisel
chisel就是方便我快速测试某些代码是否生效之类的
用来做一些快速性检查


### 计算gas开销
Gas = 你在链上执行代码所要付的手续费
每行 Solidity 代码都要消耗节点的计算资源
～计算越复杂 → Gas 越贵
～数据写入 storage → Gas 最贵
～常量读取 / memory 操作 → Gas 很便宜

函数消耗gas计算: forge snapshot --mt testWithdrawFromASingleFunder
Foundry 会生成 .gas-snapshot文件
里面有： FundMeTest:testWithdrawFromASingleFunder() (gas: 95790) 这就是本次执行消耗的gas
Gas Fee = Gas Used × Gas Price =  95790 * GasPrice：7 gwei =
BTC/ETH 市场换算得出手续费约等于： 1.77 USD


测试环境Anvil 默认 gasPrice = 0。所以默认不花钱

修改 gasPrice，让测试模拟真实链上行为: 

uint256 constant GAS_PRICE = 1;
vm.txGasPrice(GAS_PRICE);

### storage优化(这一节就比较重要)
Storage = 合约永久存储的位置（最贵的地方
每次写入 / 修改 Storage → 消耗很多 Gas。
Memory / calldata 就便宜很多。

1.原理:
32 字节一格（slot）
slot 从 0 开始编号
state variable 会依次占用 slot
小于 32 字节的变量可以 拼在一个 slot 里（packing

就像一个： 巨大的无限 32 字节格子的仓库。变量按顺序摆进去，很贵，所以要摆得紧凑。

2.storage排布
Solidity 排布变量的规则：
每个 storage slot = 32 bytes
变量按代码顺序放入 slot
小于 32 bytes 的变量能塞在同一个 slot 里。塞不下 → 使用下一个 slot
mapping 和动态数组（如 address[]）永远占 1 槽位（元位置）
-真正的数据不放在这里
-而是用 keccak(slot) 算位置

constant 和 immutable 不占 storage slot


3.Storage 排布例子
uint256 var1;  // 32 bytes
uint256 var2;  // 32 bytes
uint64 var3;   // 8 bytes

slot 0 → var1
slot 1 → var2
slot 2 → var3（还剩 24 bytes）


4. 浪费空间例子
uint64 var1;     // 8 bytes
uint128 var2;    // 16 bytes
bool var3;       // 1 byte
bool var4;       // 1 byte
uint64 var5;     // 8 bytes
address user1;   // 20 bytes
uint128 var6;    // 16 bytes
uint8 var7;      // 1 byte
uint128 var8;    // 16 bytes


结果：

slot 0: var1 + var2 + var3 + var4 = 26 bytes → 还剩 6 bytes
slot 1: var5 + user1 = 28 bytes → 剩 4 bytes
slot 2: var6 + var7 = 17 bytes → 剩 15 bytes
slot 3: var8 = 16 bytes → 剩 16 bytes

浪费很多空间。

如果把 var7 往前移，可减少 slot 数量
让 var7 塞进 slot 0 / 1 的剩余空间 → 整体能减少 slot 排布。


5.mapping 和动态数组为什么不能塞进 slot
因为：mapping 数量未知、动态数组长度可变。如果塞进去，会导致数据覆盖其他变量。
mapping 和 array 占 1 个 slot 作为“入口”。真正元素位置 = keccak256(slot + key)

6. FundMe 的 storage 排布
mapping(address => uint256) private s_addressToAmountFunded; // slot 0
address[] private s_funders;  // slot 1
AggregatorV3Interface private s_priceFeed; // slot 2

vm.load 检查 storage slot
加入这个测试：
bytes32 value = vm.load(address(fundMe), bytes32(i));

slot 0: 0x00...00   <-- mapping 的元位置
slot 1: 0x00...00   <-- 动态数组的元位置
slot 2: 0x000000000000000000000000 + priceFeed 地址

为什么 slot 2 是这样？
地址只占 20 bytes，其余前 12 bytes 用 00 填充
右对齐，地址放在右边）

slot 2 example:
00000000000000000000000090193c961a926261B756D1E5bb255e67ff9498a1


7.查看 Storage
方法 1：vm.load（在测试中查看）
vm.load(contractAddress, slotNumber)
最灵活，能写断言。

方法 2：forge inspect（查看布局）
forge inspect FundMe storageLayout
╭-------------------------+--------------------------------+------+--------+-------+-----------------------╮
| Name                    | Type                           | Slot | Offset | Bytes | Contract              |
+==========================================================================================================+
| s_addressToAmountFunded | mapping(address => uint256)    | 0    | 0      | 32    | src/FundMe.sol:FundMe |
|-------------------------+--------------------------------+------+--------+-------+-----------------------|
| s_funders               | address[]                      | 1    | 0      | 32    | src/FundMe.sol:FundMe |
|-------------------------+--------------------------------+------+--------+-------+-----------------------|
| s_priceFeed             | contract AggregatorV3Interface | 2    | 0      | 20    | src/FundMe.sol:FundMe |
╰-------------------------+--------------------------------+------+--------+-------+-----------------------╯

方法 3：cast storage（在链上查看某 slot）
第一步：启动 anvil
第二步：部署 FundMe
第三步： cast storage 0xContractAddress 2 。 你会看到 slot 2 里的 bytes32 值。



8.重要警告：private 不等于安全
smart contract 的 private 不是保密。任何人都能查看 storage。
private 只是：不能被其他合约调用、不能被外部访问（合约语法层面）
Storage 是透明的、任何人都能读！！！
所以: 不要把密码 / API key / 私钥 / 敏感信息写到 Storage

总结: 
Storage 是最贵的 gas 消耗: 变量越多、写入越多 → 用户花的钱越多。
变量排列影响 Gas，用 packing 节省 slot: 越少 slot → 越省 gas。
mapping 和动态数组不放数据，只有入口:元素位置通过 keccak256 计算。
vm.load / forge inspect / cast storage:三个是查看 storage 的核心工具。
private 不安全，别存敏感信息: 所有 storage 都能读。



### https://www.evm.codes/
可以看到链上的rw比内存的贵了33倍左右



### 集成测试
单元测试:只是测试合约自身的逻辑。
集成测试:测试合约+脚本+链环境整体流程。就是测试整个系统流程，不只是测试一个函数。

### make 指令 

Makefile 是一个“任务自动化的工具”，和你使用什么编程语言没有关系。
可以学习一下这个


### 这两种虚拟机上运行测试和功能的 DevOps 工具
EVM and ZKsync Era VM之间的差异
https://docs.zksync.io/zksync-protocol/era-vm/differences/evm-instructions

在 FundMeTest.t.sol 文件中，某些在 Vanilla Foundry 上运行的测试可能无法在 ZKsync Foundry 上运行，
反之亦然。

为了解决这些差异，我们将探讨 foundry-devops 仓库中的两个包： ZkSyncChainChecker 和 FoundryZkSyncChecker。

   //skipZkSync: 如果当前是 ZKsync VM → 跳过这个测试。如果（普通 EVM VM）运行
    //onlyZkSync: 只有在 ZKsync VM 运行，否则跳过




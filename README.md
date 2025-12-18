# solidity-NFT 项目文档

日期：2025-12-18

本文件为中文项目说明，包含项目结构、功能说明与本地部署/测试步骤，方便团队内部阅读与使用。

**目录**
- 项目结构
- 功能说明
- 本地运行与测试
- UUPS 升级测试说明
- 其他说明
- TEST.md  测试报告

---

## 合约部署地址
- `impl` 0x5d4738B5E4EeE7592C72D1D27E1df18AE447da72
- `proxy` 0x24e520b4fDd6d9c814cfbe7affC088ADE666603D


## 一、项目结构（重要文件/目录）

- `contracts/`
  - `NFTAuction.sol`：主要拍卖合约，支持 ETH/ERC20 出价与 UUPS 可升级逻辑（继承 `UUPSUpgradeable`）。
  - `NFTAuctionV2.sol`：用于升级测试的 V2 实现（新增 `HelloWorld()` 用于验证升级生效）。
  - `TestERC721.sol`：简单的 ERC721 测试代币，用于 mint/transfer 测试。
  - `MockV3Aggregator.sol`：在测试中模拟 Chainlink Price Feed（本地测试使用）。
  - `MyERC1967Proxy.sol`：简化的 ERC1967 Proxy，用于在测试中部署代理并验证 UUPS 升级流程。

- `test/`
  - `NFTAuction.functionality.test.ts`：功能测试（ETH 流）。
  - `NFTAuction.uups.test.ts`：UUPS 升级测试（部署 impl v1、proxy、升级到 v2 并调用新方法）。

- `scripts/`, `ignition/`：仓库中包含示例脚本/部署模块（可根据需要参考并扩展）。
- `hardhat.config.ts`：Hardhat 配置，Solidity 编译器配置、网络配置等。
- `package.json`：项目依赖与脚本。
- `TEST.md`：本次测试执行后生成的测试报告（包含测试结果与覆盖率生成说明）。

---

## 二、功能说明（核心功能）

1. 拍卖登记（createAuction）
   - 拍卖者将其持有的 ERC721 代币上架拍卖，填写起拍价与拍卖时长。
   - 当前实现限制：只有 NFT 所有者可创建拍卖（并且调用者需为合约所记录 `owner`）。

2. 出价（bid）
   - 支持以太币（ETH）或 ERC20 代币出价（合约使用 Chainlink 预言机将不同代币价格统一转换为 USD 进行比较）。
   - 新的最高出价会退还之前最高出价（ETH 直接转账，ERC20 使用 SafeERC20）。

3. 结束拍卖（endAuction）
   - 拍卖到期后，调用 `endAuction` 将 NFT 转移给最高出价者，并将资金转给卖家；标记拍卖结束。

4. UUPS 可升级性
   - 合约实现 `UUPSUpgradeable`，在实现合约中 `_authorizeUpgrade` 使用 `onlyOwner` 限制升级权限。
   - 提供 `NFTAuctionV2` 用于测试升级后新增函数调用（`HelloWorld()` 返回示例字符串）。

---

## 三、本地运行与测试（一步一步）

先决条件：Node.js、npm 已安装。

1) 安装依赖

```bash
npm install
```

如果你遇到与 `sepolia` 配置相关的校验问题（Hardhat 会检查 `hardhat.config.ts` 中的 sepolia 配置），可以在运行测试时临时设置占位环境变量：

```bash
export SEPOLIA_PRIVATE_KEY=0x0123456789012345678901234567890123456789012345678901234567890123
export SEPOLIA_RPC_URL=http://127.0.0.1:8545
```

2) 运行全部测试

```bash
npx hardhat test --show-stack-traces
```

3) 运行单个测试文件（示例：UUPS 测试）

```bash
npx hardhat test test/NFTAuction.uups.test.ts --show-stack-traces
```

4) 说明：测试使用 `viem` 进行合约部署与签名交互，内置 Hardhat 网络可以直接运行上述命令；若使用远程网络，请确保环境变量和私钥正确配置。

---

## 四、UUPS 升级测试说明（要点）

- 测试流程概览：
  1. 部署实现合约 V1（`NFTAuction`）。
  2. 部署 ERC1967 Proxy，指向 V1 实现地址。
  3. 通过代理调用 `initialize()` 设置合约 `owner`。
  4. 部署实现合约 V2（`NFTAuctionV2`）。
  5. 从代理上调用 `upgradeTo` / `upgradeToAndCall`（通过实现合约的 UUPS 逻辑）将实现切换为 V2。
  6. 在代理地址上调用 V2 新增方法，例如 `HelloWorld()`，验证返回值并检查原有存储（如 `owner`）是否保留。

---

## 五、常见问题与注意事项

- 测试使用本地 Hardhat 网络时无需真实 RPC/私钥，但 `hardhat.config.ts` 中若包含 network 配置（如 `sepolia`）会在配置解析时检验环境变量，建议在 CI 或本地运行时临时设置占位环境变量。
- UUPS 升级的 `_authorizeUpgrade` 使用 `onlyOwner` 锁定为 `owner`，请确保在测试中调用 `initialize()` 设置正确的 `owner`。
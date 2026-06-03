# 🔐 PQ-Ready Arc：在 Arc Testnet 上部署了一套完整的抗量子智能账户系统

> 按 Circle 后量子路线图搭建，已开源，已全量上线 Arc Testnet

---

## 为什么要关心「抗量子」？

你可能觉得量子攻击还很遥远，但有一个事实值得注意：

**量子计算机的 Shor 算法可以秒杀 ECDSA** —— 而 ECDSA 正是今天几乎所有区块链账户的基础签名算法，包括以太坊的 EOA。

一旦足够强的量子计算机出现，所有基于 ECDSA 的地址都将裸奔。这不是科幻，NIST 已经在 2024 年发布了首批后量子密码标准（FIPS 205），各国也开始要求关键系统向 PQ 迁移。

Circle 在 2023 年就发布了 PQ 路线图博客，核心思路是 **分阶段迁移、混合签名、账户可升级**。这个项目就是按照那个框架，在 Arc Testnet 上落地了一个可运行的参考实现。

---

## 整体架构

```
用户交互层
    ↓
PQAccount（智能账户）
    ↓
MigrationManager（可升级签名模块管理器）
    ↓
ISignatureModule ← ECDSAModule | HashBasedModule | HybridModule
    ↓
RecoveryManager（M-of-N 社交恢复）
```

核心合约 6 个，全部分开部署，通过接口解耦：

| 合约 | 作用 |
|---|---|
| **PQAccount** | 智能账户入口，`verifyAndExecute` 校验签名并执行 |
| **ECDSAModule** | 当前主流方案，用 `ecrecover` 验证 |
| **HashBasedModule** | 抗量子方案，基于 Merkle 树 + keccak256 哈希签名 |
| **HybridModule** | 混合方案，ECDSA + Hash 双签，迁移过渡期最实用 |
| **MigrationManager** | 7 天时间锁升级签名模块，可插拔 |
| **RecoveryManager** | M-of-N 守护者社交恢复，带挑战期 |

---

## 为什么用 Merkle 树「模拟」而不是真 SPHINCS+？

直接原因：**SPHINCS+ 签名太大了（~41 KB），EVM 上没有 precompile，链上验证 gas 会炸穿区块上限**。

现实路线图是分步走：

1. **先做可插拔架构** — ISignatureModule 接口设计好，合约能换签名模块
2. **用哈希签名过渡** — Merkle 树 + keccak256，Grover 算法也只能把 256 bit 降到 128 bit，依然足够安全
3. **等 PQ precompile 就绪** — 未来 Arc 或其他 EVM 链加上 SPHINCS+ precompile 后，写一个 `RealSPHINCSModule` 插进去就行

所谓 **PQ-Ready**，关键在 Ready ——框架搭好了，等真的能上了换上去就行。

---

## 四个核心任务（全都在 Arc Testnet 上跑通了）

### Task 1: PQ 原生账户
一个一开始就用 HashBasedModule 的账户，纯抗量子签名。  
地址：`0xbE98b7057476cCc007b7bA490440762C8587C416`

### Task 2: 从 ECDSA 迁移到 PQ
账户先用 ECDSA，通过 MigrationManager 排期迁移到 PQ 方案，7 天时间锁保护。  
地址：`0xbD02D9b066eE4E4023A861D8fff7F881cD2C19C8`

### Task 3: 混合签名
ECDSA + Hash 双签同时通过才执行交易。  
地址：`0x870924e38cD2dC2bf44697D35F818666D8897728`

### Task 4: 社交恢复
2-of-2 守护者恢复机制，3 天挑战期。  
地址：`0x30E419908FB7d8E752a400547839f9f8960DABDD`

---

## 在线 DApp

所有功能都有可视化界面，不需要敲命令行：

🔗 **https://pq-secure-arc.vercel.app**

连接 MetaMask 后可以：

- **查询任意账户** — 贴地址看签名方案、nonce、迁移进度、恢复状态
- **排期 / 执行迁移** — 一键把 ECDSA 账户升级到抗量子方案
- **社交恢复** — 发起恢复、批准恢复、执行恢复
- **注册 PQ 密钥** — 设置 Merkle Root
- **创建自己的账户 🔥** — 钱包直接部署 MigrationManager + RecoveryManager + PQAccount，选方案、设守护者、三步搞定

所有合约已在 Blockscout 上验证通过，可在 Arc Scan 上查看源码。

---

## 技术细节

- **链**: Arc Testnet (Chain ID 5042002)
- **RPC**: `https://rpc.testnet.arc.network`
- **浏览器**: https://testnet.arcscan.app
- **语言**: 全英语界面
- **前端**: 纯 HTML + ethers.js v5 + Tailwind，单文件无构建
- **后端合约**: Solidity，Foundry 编译部署
- **NIST 标准参考**: FIPS 205 (SLH-DSA / SPHINCS+)

---

## 写在最后

这是一个**教学 + 架构演示**项目，它展示的是后量子时代区块链账户应该如何设计：

- 签名模块要**可插拔**
- 迁移要**有时间锁保护**
- 用户要有**恢复机制**
- 过渡期要支持**混合签名**

抗量子不是一个人的事，是整个行业需要开始思考的问题。Arc 作为 USDC 的 Circle 原链，本身就站在金融合规和安全的最前沿。希望这套实现能给社区带来一些参考价值。

代码已开源在 GitHub（欢迎 PR）  
DApp 可直接用：https://pq-secure-arc.vercel.app

---

*如果你在 Arc Testnet 上用自己的钱包部署了一个 PQAccount，欢迎在评论区分享你的地址 👇*

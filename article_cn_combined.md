# 🔐🛡️ Arc 上的「攻防一体」智能账户：抗量子 + 可选隐私

> 一套代码、一个 DApp、一条链，同时兼容**后量子安全**与**链上隐私保护**
> 已全量部署在 **Arc Testnet**，代码完全开源

---

## 两个命题，一套方案

今年区块链安全领域有两个趋势越来越明显：

1. **量子攻击** —— 一旦 Shor 算法跑在够强的量子计算机上，ECDSA 裸奔
2. **链上隐私** —— 所有 tx 都在区块浏览器上公开，任何人可以追踪你的每一笔交互

表面看它们是两个问题，但实际上它们指向同一个目标：**让你的账户更安全、更可控**。

抗量子解决的是「我的资产会不会被偷」，隐私解决的是「我的行为会不会被看光」。

于是有了这个项目 —— 在 Arc Testnet 上跑通了一套同时解决这两个问题的智能账户系统。

---

## 整体架构（这次带隐私层）

```
        传统视图                             隐私视图
     ┌──────────────┐               ┌──────────────────┐
     │  PQAccount   │               │  PrivacyManager   │
     │  (智能账户)    │               │  (隐身份管理层)     │
     ├──────────────┤               ├──────────────────┤
     │  签名模块     │               │  Stealth Key      │
     │  ECDSA / 哈希 │               │  ECDH 加密         │
     │  混合方案     │               │  Private Events    │
     ├──────────────┤               └──────────────────┘
     │  迁移管理     │     ←可选→           ↑
     │  (7天时间锁)   │               DApp 端 ECDH 解密
     ├──────────────┤
     │  社交恢复     │
     └──────────────┘
```

核心合约 7 个，各有分工：

| 合约 | 职责 | 地址 |
|---|---|---|
| **PQAccount** | 智能账户入口 | 用户部署 |
| **ECDSAModule** | 经典 ECDSA 签名 | `0xbf2ba8…F2E3` |
| **HashBasedModule** | 抗量子哈希签名（Merkle） | `0x388E0c…aaE` |
| **HybridModule** | ECDSA + 哈希双签 | `0x48bB3b…186` |
| **MigrationManager** | 7 天时间锁升级 | 用户部署 |
| **RecoveryManager** | M-of-N 守护者恢复 | 用户部署 |
| **PrivacyManager** 🆕 | 隐身地址 + 加密交易 | `0xE6C665…C136` |

---

## 可选隐私：PrivacyManager 怎么工作

传统的 DeFi 交互是这样的：

```
A → 转账100 USDC → B   ← 所有人都在浏览器上看到"A 给 B 转了 100"
```

加了隐私层之后变成：

```
A → 链上事件：加密密文 + 临时公钥       ← 观察者只看到乱码
                                    ↓
B 在 DApp 里用自己私钥 ECDH 解密       ← 只有 B 能看懂
```

### 技术流程

1. **注册隐身份** — 每个账户在 PrivacyManager 上注册一个 secp256k1 公钥（64 字节，无 0x04 前缀）
2. **发送私密交易** — 发送方生成临时密钥对，`ephemeralPriv × recipientPub` 做 ECDH，推导对称密钥，用 XOR 加密 `[收件人地址 + 消息内容]`，把临时公钥 + 密文上链
3. **接收方解密** — DApp 扫描链上 PrivateTransaction 事件，用自己的隐身份私钥做 ECDH，推导同一个对称密钥，XOR 解密拿到原文
4. **验证收件人** — 解密后的前 20 字节如果匹配接收方地址，说明消息确实是给自己的

### 关键设计取舍

- **ECDH 而非 AES** — 不需要链上分发对称密钥，非对称做完 ECDH 双方拿到同一个共享密钥
- **XOR 而非全密** — 简单高效，前端浏览器就能跑，不需要 WebAssembly
- **recipientHint** — 可选传 `keccak256(recipient)` 减少扫描量，不传则完全隐私（扫描需要遍历所有事件）
- **私钥存 localStorage** — 不做链上存储，只有浏览器本地有，清缓存即丢失

### 双钱包测试验证

我们用两个钱包做了完整测试：

```
Wallet A (0xb112...) → 注册隐身份公钥
Wallet B (0xE90D...) → 注册隐身份公钥
Wallet B → sendPrivate → 链上事件 ← 密文 ephPub + ciphertext
Wallet A → 扫描 → ECDH 解密 → "Hello from Wallet B! This is a private stealth transaction on Arc!"
```

**链上看不到**原始消息内容，只有：
- 临时公钥（一次性，无法关联）
- 加密后的密文（乱码）
- 时间戳

---

## 两种安全，一个 DApp

在线 DApp 把两个功能整合在一起了：

🔗 **https://pq-secure-arc.vercel.app**

### 首页：抗量子功能
- 查询任意 PQAccount 的签名方案、nonce、迁移进度
- 排期迁移（ECDSA → PQ）
- 社交恢复流程
- **创建自己的账户** — 三步部署 MigrationManager + RecoveryManager + PQAccount

### 🛡️ Privacy 选项卡：隐私功能
- **生成隐身份密钥** — 浏览器本地生成 secp256k1 密钥对
- **注册到链上** — 在 PrivacyManager 登记公钥
- **发送私密交易** — 填接收方地址 + 消息，自动 ECDH 加密上链
- **扫描私密收件箱** — 解密链上事件，只展示发送给自己的消息
- **一键测试** — 点「Generate Wallet B」自动生成测试钱包、打款、注册隐身份、发送私密测试消息
- **隐私开关** — 可以在链上标记"我使用隐私模式"（纯标记，解密靠自己）

### 其他钱包也能用
任何 MetaMask 钱包连接 DApp 后：
1. 🛡️ Privacy → 生成密钥 → 注册 → 发送加密消息
2. 收件人只要也在 PrivacyManager 注册了公钥，就能解密

---

## 部署信息

- **链**: Arc Testnet (Chain ID: 5042002)
- **RPC**: `https://rpc.testnet.arc.network`
- **浏览器**: https://testnet.arcscan.app
- **PrivacyManager 合约**: `0xE6C665048Bfcc1A2D9C9331BF8D586532216C136`（已验证源码）
- **签名模块合约**: 全部已验证
- **DApp**: https://pq-secure-arc.vercel.app
- **代码**: https://github.com/lzmaks10/pq-secure-arc

---

## 思考和展望

### 为什么这两个功能放在一起？

量子安全和隐私保护在技术栈上是互补的：

| | 抗量子 | 隐私 |
|---|---|---|
| 防护对象 | 未来量子攻击者 | 当前链上观察者 |
| 防护手段 | 签名方案替换 | 数据加密 |
| 实现层面 | 账户层 | 交易层 |
| 共同点 | 都要求"可升级" | 都依赖非对称密码学 |

在 PrivacyManager 里我们用的就是 **secp256k1 ECDH** —— 这恰恰是量子计算机理论上威胁最大的部分。这也是为什么要把隐私设计成**可选的** —— 当未来需要迁移到 PQ 版本的 ECDH 时，合约升级只涉及密钥注册的逻辑，密文格式不变。

### 接下来可以做什么

1. **给 PrivacyManager 加真正的 ECDH 挑战** — 当前是浏览器做 ECDH，未来可以用 ZK 证明让链上验证解密正确性
2. **隐私 + 迁移** — 在迁移期间同时更新隐身份密钥，防止旧密钥被量子破解
3. **批量扫链优化** — 当前扫描是遍历事件 + 逐个 ECDH，大量私密消息时可以用 bloom filter 加速

---

## 试试看

连接 MetaMask（Arc Testnet），打开 DApp：

1. 点 🛡️ Privacy → Generate Stealth Key → Register On-Chain
2. 在 Target Wallet 输入朋友的地址（对方也要注册过隐身份密钥）
3. 写消息 → 点 🔒 Send Private
4. 点 🔍 Scan for Private Txs 看看有没有人给你发了私密消息
5. 点 🔄 Generate Wallet B 一键全流程体验

抗量子部分也一样：首页点 🚀 Create Account，选你喜欢的签名方案，三步部署你自己的后量子账户。

代码全在 GitHub 上：**https://github.com/lzmaks10/pq-secure-arc**

---

*你有没有想过 —— 如果量子计算机先于隐私技术成熟，那今天加密的消息明天就是明文。抗量子 + 隐私，缺一不可。*

*欢迎在评论区留言交流 👇*

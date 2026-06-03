# 🔐🛡️ Offense & Defense on Arc: Post-Quantum Security + Optional Privacy in One Account System

> One codebase, one DApp, one chain — compatible with both **post-quantum security** and **on-chain privacy protection**
> Fully deployed on **Arc Testnet**, 100% open source

---

## Two Problems, One Solution

Two security trends are becoming impossible to ignore in blockchain:

1. **Quantum attacks** — Once Shor's algorithm runs on a sufficiently powerful quantum computer, ECDSA is exposed. Period.
2. **On-chain privacy** — Every transaction is publicly visible on block explorers. Anyone can trace every move you make.

On the surface these are two separate problems, but they point to the same goal: **making your account safer and more controllable**.

Post-quantum answers "can my assets be stolen." Privacy answers "can my behavior be watched."

That's why this project exists — a smart account system on Arc Testnet that solves both problems in one integrated design.

---

## Architecture (Now With Privacy Layer)

```
        Classic View                         Privacy View
     ┌──────────────┐               ┌──────────────────────┐
     │  PQAccount   │               │    PrivacyManager     │
     │ (Smart Acct) │               │ (Stealth Key Manager) │
     ├──────────────┤               ├──────────────────────┤
     │  Sig Modules │               │  • Stealth Key Reg    │
     │  ECDSA/Hash  │               │  • ECDH Encryption    │
     │  Hybrid      │               │  • Private Events     │
     ├──────────────┤               └──────────────────────┘
     │  Migration   │     ←opt→              ↑
     │  (7-day TL)  │             DApp-side ECDH decryption
     ├──────────────┤
     │  Recovery    │
     └──────────────┘
```

7 core contracts, each with a clear role:

| Contract | Role | Address |
|---|---|---|
| **PQAccount** | Smart account entry point | User-deployed |
| **ECDSAModule** | Classic ECDSA sig verification | `0xbf2ba8…F2E3` |
| **HashBasedModule** | PQ-hash sig (Merkle tree) | `0x388E0c…aaE` |
| **HybridModule** | ECDSA + Hash dual sig | `0x48bB3b…186` |
| **MigrationManager** | 7-day timelocked sig module upgrade | User-deployed |
| **RecoveryManager** | M-of-N guardian social recovery | User-deployed |
| **PrivacyManager** 🆕 | Stealth addresses + encrypted txs | `0xE6C665…C136` |

---

## Optional Privacy: How PrivacyManager Works

Traditional DeFi looks like this:

```
A → transfer 100 USDC → B   ← Everyone on the explorer sees "A sent B 100"
```

With the privacy layer:

```
A → On-chain event: encrypted ciphertext + ephemeral public key
                                    ↓
B decrypts in the DApp using their private key (ECDH)
```

Only B can read the original content. Observers see gibberish.

### Technical Flow

1. **Register stealth identity** — Each account registers a secp256k1 public key (64 bytes, no 0x04 prefix) on PrivacyManager
2. **Send private transaction** — The sender generates an ephemeral key pair, performs ECDH (`ephemeralPriv × recipientPub`), derives a symmetric key, XOR-encrypts `[recipient_address + message]`, and publishes the ephemeral pubkey + ciphertext on-chain
3. **Recipient decrypts** — The DApp scans on-chain `PrivateTransaction` events, performs ECDH with their own stealth private key, derives the same symmetric key, and XOR-decrypts
4. **Verify recipient** — If the first 20 bytes of decrypted text match the receiver's address, the message is confirmed for them

### Key Design Decisions

- **ECDH over AES** — No need to distribute symmetric keys on-chain; both parties derive the same shared key via asymmetric crypto
- **XOR over full encryption** — Simple, efficient, runs in the browser without WebAssembly
- **`recipientHint`** — Optionally pass `keccak256(recipient)` to reduce scan overhead; omit for maximum privacy (full event traversal)
- **Private keys in localStorage** — Never stored on-chain; only the browser has them. Clearing cache loses them.

### Two-Wallet Test Verification

We ran a full end-to-end test with two wallets:

```
Wallet A (0xb112...) → registers stealth public key
Wallet B (0xE90D...) → registers stealth public key
Wallet B → sendPrivate → on-chain event (ephPub + ciphertext)
Wallet A → scan → ECDH decrypt → "Hello from Wallet B! This is a private stealth transaction on Arc!"
```

**The chain cannot see** the original message. Only:
- Ephemeral public key (one-time use, unlinkable)
- Encrypted ciphertext (gibberish)
- Timestamp

---

## Two Kinds of Security, One DApp

The DApp integrates both features:

🔗 **https://pq-secure-arc.vercel.app**

### Main Tab: Post-Quantum Features
- Query any PQAccount's signature scheme, nonce, and migration status
- Schedule migrations (ECDSA → PQ)
- Full social recovery flow
- **Create your own account** — deploy MigrationManager + RecoveryManager + PQAccount in 3 transactions

### 🛡️ Privacy Tab: Privacy Features
- **Generate stealth identity** — secp256k1 key pair, generated locally in the browser
- **Register on-chain** — publish your public key to PrivacyManager
- **Send private transactions** — enter recipient address + message, auto ECDH encrypt, send on-chain
- **Scan private inbox** — decrypt on-chain events, show only messages addressed to you
- **One-click test** — click "Generate Wallet B" to auto-create a test wallet, fund it, register stealth keys, and send a demo private message
- **Privacy toggle** — optionally mark yourself as "privacy mode" on-chain (signal only; decryption is always local)

### Works for Any Wallet
Any MetaMask wallet connecting to the DApp can:
1. 🛡️ Privacy → Generate Key → Register on-chain → Send encrypted messages
2. Recipients can decrypt as long as they've registered their stealth key on PrivacyManager

---

## Deployment Info

- **Chain**: Arc Testnet (Chain ID: 5042002)
- **RPC**: `https://rpc.testnet.arc.network`
- **Explorer**: https://testnet.arcscan.app
- **PrivacyManager contract**: `0xE6C665048Bfcc1A2D9C9331BF8D586532216C136` (source verified ✅)
- **All signature modules**: source verified ✅
- **DApp**: https://pq-secure-arc.vercel.app
- **Source code**: https://github.com/lzmaks10/pq-secure-arc

---

## Discussion & Outlook

### Why put these two features together?

Quantum security and privacy protection are complementary in the tech stack:

| | Post-Quantum | Privacy |
|---|---|---|
| Defense target | Future quantum attackers | Current on-chain observers |
| Defense mechanism | Signature scheme replacement | Data encryption |
| Implementation layer | Account layer | Transaction layer |
| Common ground | Both need upgradeability | Both rely on asymmetric crypto |

The irony? PrivacyManager uses **secp256k1 ECDH** — the very thing quantum computers threaten most. That's exactly why privacy is designed as **optional**. When the time comes to migrate to a PQ-compatible ECDH, the contract upgrade only touches the key registration logic; the ciphertext format stays unchanged.

### What's next

1. **ZK proofs for ECDH** — Currently ECDH happens in the browser. A ZK proof could let the chain verify correct decryption without revealing the private key
2. **Privacy + migration** — Rotate stealth keys during migration to prevent old keys from being quantum-cracked
3. **Batch scan optimization** — Current scan iterates all events × ECDH per key. A bloom filter approach would scale for high-volume private messaging

---

## Try It Yourself

Connect MetaMask (Arc Testnet), open the DApp:

1. Click 🛡️ Privacy → Generate Stealth Key → Register On-Chain
2. Enter a friend's address in Target Wallet (they need to register a stealth key too)
3. Type a message → click 🔒 Send Private
4. Click 🔍 Scan for Private Txs to check your inbox
5. Click 🔄 Generate Wallet B for a full one-click demo

For the post-quantum side: go to the main tab → 🚀 Create Account, pick your favorite signature scheme, and deploy your own PQ-ready smart account in 3 MetaMask transactions.

All code is on GitHub: **https://github.com/lzmaks10/pq-secure-arc**

---

*Here's something to think about: if quantum computers mature before privacy tech catches up, today's encrypted messages will be tomorrow's plaintext. Post-quantum + privacy — you need both.*

*Comments and PRs welcome 👇*

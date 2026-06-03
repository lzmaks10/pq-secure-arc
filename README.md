# 🔐 PQ-Ready Arc

Post-Quantum-Ready Smart Account System on **Arc Testnet** (Chain 5042002)

> Following Circle's post-quantum security roadmap: phased migration, hybrid signatures, account recovery, upgradable architecture.

**[🌐 Live DApp](https://pq-secure-arc.vercel.app)**

## What This Is

A complete reference implementation of a post-quantum-resistant account system on Arc Testnet. Any connected wallet can:
- Deploy their own PQAccount (3 transactions via MetaMask)
- Query any account's signature scheme, nonce, migration status
- Schedule signature module upgrades (ECDSA → PQ) with 7-day timelock
- Execute M-of-N social recovery with guardian approval flow
- Register PQ Merkle root for hash-based signatures
- Demo PQ signature verification client-side

## Architecture

```
┌─────────────────────────────┐
│     PQAccount               │  Smart account (verifyAndExecute)
├─────────────────────────────┤
│  MigrationManager           │  7-day timelocked module upgrades
├─────────────────────────────┤
│  ISignatureModule  ←────────┼── ECDSAModule | HashBasedModule | HybridModule
├─────────────────────────────┤
│  RecoveryManager            │  M-of-N social recovery with challenge period
└─────────────────────────────┘
```

## Core Contracts (Verified on Blockscout)

| Contract | Address | Explorer |
|---|---|---|
| ECDSAModule | `0xbf2ba8…F2E3` | [View](https://testnet.arcscan.app/address/0xbf2ba8ede210d184c10b4b4D3E183B0a7CD1F2E3) |
| HashBasedModule | `0x388E0c…aaE` | [View](https://testnet.arcscan.app/address/0x388E0c1AB76A5A8C7C4567Dd8566496f96620aaE) |
| HybridModule | `0x48bB3b…186` | [View](https://testnet.arcscan.app/address/0x48bB3b57561d913d36634e991501fD1C7a578186) |

## Four Demo Tasks (All Executed On-Chain)

1. **PQ-Native Account** (`0xbE98b7…7C416`) — Hash-based from day 1
2. **Migration** (`0xbD02D9…2C19C8`) — ECDSA → PQ via timelocked upgrade
3. **Hybrid** (`0x870924…897728`) — ECDSA + Hash dual signature
4. **Recovery** (`0x30E419…DABDD`) — 2-of-2 guardian recovery

## Tech Stack

- **Chain**: Arc Testnet (Chain ID 5042002, `0x4CEF52`)
- **Contracts**: Solidity + Foundry (forge, cast)
- **Frontend**: Single HTML file, ethers.js v5, Tailwind
- **Auth**: MetaMask / WalletConnect (auto-switch to Arc)

## Local Development

```bash
git clone https://github.com/lzmaks10/pq-secure-arc.git
cd pq-secure-arc
forge build
forge test --match-contract PQAllFlows -vvv
```

To deploy:
```bash
forge script script/DeployPQSystem.s.sol \
  --rpc-url https://rpc.testnet.arc.network \
  --broadcast --via-ir
```

## DApp

The DApp is a single `ui/index.html` file. Development version:
- `ui/index.html` — working copy
- `ui_build/index.html` — deployed to Vercel

## Why Not Real SPHINCS+?

SPHINCS+ signatures (~41 KB) cannot be verified on EVM without a precompile due to gas limits. This implementation uses Merkle-tree-based hash signing (keccak256) as a simulation, following the same architectural pattern:

1. **Hash-based signatures** — quantum-resistant (Grover's algorithm only halves 256→128 bit security)
2. **Pluggable modules** — swap to RealSPHINCSModule when precompiles arrive
3. **Real architecture** — the upgradable framework is production-ready

## License

MIT

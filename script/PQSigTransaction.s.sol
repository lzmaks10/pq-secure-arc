// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {HashBasedModule} from "../src/modules/HashBasedModule.sol";
import {PQAccount} from "../src/PQAccount.sol";

/// @title PQSigTransaction
/// @notice Generate a hash-based PQ signature and submit a real on-chain
///         verifyAndExecute transaction on Arc Testnet.
///
///         Uses the same Merkle tree parameters as the deploy script.
contract PQSigTransaction is Script {
    uint256 public constant NUM_LEAVES = 256;
    uint256 public constant TREE_HEIGHT = 8;

    // Addresses from deployment
    address constant ACCOUNT = 0x9453ab0De3a04E68987C1323Cd9eA03dba9e4e35;
    address constant HASH_MODULE = 0x03bdCc3238B6C700Ce3751670A3A068Bd96B2aBc;

    // Pre-generated private keys (same as deploy script)
    bytes32[] privKeys;

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address dep = vm.addr(pk);

        console2.log("=== PQ-Signed Transaction on Arc Testnet ===");
        console2.log("Account:", ACCOUNT);
        console2.log("");

        // Regenerate the same private keys as in deployment
        _genKeys();

        vm.startBroadcast(pk);

        // Step 1: Fund the account
        console2.log("--- Funding account ---");
        uint256 fundAmount = 0.5 ether;
        payable(ACCOUNT).transfer(fundAmount);
        console2.log("Sent", fundAmount, "wei to account");
        console2.log("");

        // Step 2: Build and submit a PQ-signed transaction
        console2.log("--- Submitting PQ-signed transaction ---");
        address target = 0x000000000000000000000000000000000000dEaD;
        uint256 value = 0.001 ether;
        bytes memory data = hex"";

        // Read current nonce
        uint256 nonce = PQAccount(payable(ACCOUNT)).nonce();
        console2.log("Nonce:", nonce);

        // Compute digest (must match PQAccount.verifyAndExecute)
        bytes32 digest = keccak256(abi.encodePacked(
            "\x19\x01",
            block.chainid,
            ACCOUNT,
            target,
            value,
            keccak256(data),
            nonce
        ));
        console2.log("Digest:", vm.toString(digest));

        // Generate PQ signature
        uint256 leafIdx = 17;
        bytes memory signature = _genSig(leafIdx, digest);
        console2.log("Signature generated (leaf", leafIdx, ")");

        // Submit verifyAndExecute
        PQAccount(payable(ACCOUNT)).verifyAndExecute(target, value, data, signature);
        console2.log("Transaction executed successfully!");
        console2.log("");

        vm.stopBroadcast();

        console2.log("=== DONE ===");
        console2.log("Sent", value, "wei to", vm.toString(target));
        console2.log("Signature scheme: Hash-Based (Quantum-Resistant)");
        console2.log("Only hash functions were used (no ECDSA)!");
    }

    function _genKeys() internal {
        privKeys = new bytes32[](NUM_LEAVES);
        for (uint256 i = 0; i < NUM_LEAVES; i++) {
            privKeys[i] = keccak256(abi.encodePacked("arc-pq-demo", uint256(5042002), i));
        }
    }

    function _genSig(uint256 idx, bytes32 digest) internal view returns (bytes memory) {
        bytes32[] memory proof = _genProof(idx);
        bytes32 sigComponent = keccak256(abi.encodePacked(privKeys[idx], digest));
        return abi.encode(idx, proof, privKeys[idx], sigComponent);
    }

    function _genProof(uint256 idx) internal view returns (bytes32[] memory) {
        bytes32[] memory proof = new bytes32[](TREE_HEIGHT);
        bytes32[] memory level = new bytes32[](NUM_LEAVES);

        for (uint256 i = 0; i < NUM_LEAVES; i++) {
            bytes32 lpk = keccak256(abi.encodePacked(privKeys[i]));
            level[i] = keccak256(abi.encodePacked(lpk));
        }

        uint256 len = level.length;
        uint256 curIdx = idx;

        for (uint256 h = 0; h < TREE_HEIGHT; h++) {
            uint256 sib = (curIdx % 2 == 0) ? curIdx + 1 : curIdx - 1;
            proof[h] = (sib < len) ? level[sib] : bytes32(0);
            curIdx /= 2;

            uint256 nextLen = (len + 1) / 2;
            bytes32[] memory next = new bytes32[](nextLen);
            for (uint256 i = 0; i < len; i += 2) {
                if (i + 1 < len) {
                    next[i / 2] = keccak256(abi.encodePacked(level[i], level[i + 1]));
                } else {
                    next[i / 2] = level[i];
                }
            }
            level = next;
            len = nextLen;
        }
        return proof;
    }
}

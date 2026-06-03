// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {ECDSAModule} from "../src/modules/ECDSAModule.sol";
import {HashBasedModule} from "../src/modules/HashBasedModule.sol";
import {PQAccount} from "../src/PQAccount.sol";
import {MigrationManager} from "../src/MigrationManager.sol";
import {RecoveryManager} from "../src/RecoveryManager.sol";

/// @title DeployPQAccount
/// @notice Deploy a PQ-native account on Arc Testnet and register PQ public key.
///
///         Flow:
///         1. Generate Merkle tree (256 leaves, 8 levels)
///         2. Deploy ECDSAModule + HashBasedModule
///         3. Deploy PQAccount (starts with HashBasedModule)
///         4. Register Merkle root under the account's address via registerPqKey
///         5. Output setup details
contract DeployPQAccount is Script {
    uint256 public constant NUM_LEAVES = 256;
    uint256 public constant TREE_HEIGHT = 8;

    bytes32[] privKeys;
    bytes32 root;

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address dep = vm.addr(pk);

        console2.log("=== Deploy PQ-Native Account on Arc Testnet ===");
        console2.log("Chain:", block.chainid);
        console2.log("Deployer:", dep);
        console2.log("");

        // ---------- Generate Merkle Tree ----------
        console2.log("--- Generating Merkle Tree ---");
        _genKeypair();
        console2.log("Root:", vm.toString(root));
        console2.log("");

        vm.startBroadcast(pk);

        // ---------- Deploy modules ----------
        console2.log("--- Deploying modules ---");
        ECDSAModule ecdsa = new ECDSAModule();
        HashBasedModule hashMod = new HashBasedModule();
        console2.log("ECDSAModule:", address(ecdsa));
        console2.log("HashBasedModule:", address(hashMod));

        // ---------- Deploy account ----------
        console2.log("--- Deploying PQ-native Account ---");
        MigrationManager mgr = new MigrationManager(address(hashMod), dep);
        address[] memory guardians = new address[](2);
        guardians[0] = address(0xFEED);
        guardians[1] = address(0xBEEF);
        RecoveryManager rec = new RecoveryManager(dep, address(mgr), guardians, 2, 3 days);
        PQAccount account = new PQAccount(address(mgr), address(rec));
        console2.log("PQAccount:", address(account));
        console2.log("  Scheme:", account.currentScheme());
        console2.log("  PQ-Resistant:", account.isCurrentSchemeQuantumResistant());

        // ---------- Register PQ root under account's address ----------
        console2.log("--- Registering PQ public key ---");
        // registerPqKey forwards a call from this contract to the active module.
        // The module sees msg.sender = PQAccount, so merkleRoots[pqAccount] = root.
        bytes memory regData = abi.encodeWithSelector(
            hashMod.setMerkleRoot.selector, root
        );
        account.registerPqKey(regData);
        console2.log("  Root registered for:", address(account));

        // Verify
        bytes32 storedRoot = hashMod.merkleRoots(address(account));
        console2.log("  Stored root matches:", storedRoot == root);
        console2.log("");

        vm.stopBroadcast();

        // ---------- Summary ----------
        console2.log("=== SUMMARY ===");
        console2.log("Network: Arc Testnet (5042002)");
        console2.log("ECDSA:", address(ecdsa));
        console2.log("HashBased:", address(hashMod));
        console2.log("PQAccount:", address(account));
        console2.log("  Mgmt:", address(mgr));
        console2.log("  Recovery:", address(rec));
        console2.log("Root:", vm.toString(root));
        console2.log("");
        console2.log("To test PQ signature transaction:");
        console2.log("  1. Fund account: cast send <account> --value 0.1ether");
        console2.log("  2. Call verifyAndExecute with generated PQ signature");
    }

    function _genKeypair() internal {
        privKeys = new bytes32[](NUM_LEAVES);
        bytes32[] memory leaves = new bytes32[](NUM_LEAVES);

        for (uint256 i = 0; i < NUM_LEAVES; i++) {
            privKeys[i] = keccak256(abi.encodePacked("arc-pq-demo", block.chainid, i));
            bytes32 lpk = keccak256(abi.encodePacked(privKeys[i]));
            leaves[i] = keccak256(abi.encodePacked(lpk));
        }
        root = _buildRoot(leaves);
    }

    function _buildRoot(bytes32[] memory level) internal pure returns (bytes32) {
        while (level.length > 1) {
            uint256 nextLen = (level.length + 1) / 2;
            bytes32[] memory next = new bytes32[](nextLen);
            for (uint256 i = 0; i < level.length; i += 2) {
                if (i + 1 < level.length) {
                    next[i / 2] = keccak256(abi.encodePacked(level[i], level[i + 1]));
                } else {
                    next[i / 2] = level[i];
                }
            }
            level = next;
        }
        return level[0];
    }
}

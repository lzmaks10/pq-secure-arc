// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {ECDSAModule} from "../src/modules/ECDSAModule.sol";
import {HashBasedModule} from "../src/modules/HashBasedModule.sol";
import {HybridModule} from "../src/modules/HybridModule.sol";
import {PQAccount} from "../src/PQAccount.sol";
import {MigrationManager} from "../src/MigrationManager.sol";
import {RecoveryManager} from "../src/RecoveryManager.sol";

contract OnChainAllTasks is Script {
    uint256 constant TH = 8;
    uint256 constant NL = 256;
    mapping(uint256 => bytes32) pk;
    bytes32 root;

    function run() external {
        uint256 dpk = vm.envUint("PRIVATE_KEY");
        address dep = vm.addr(dpk);
        _genTree();
        console2.log("=== 4 Tasks: Arc Testnet ===");
        console2.log("Dep:", dep);

        vm.startBroadcast(dpk);

        // Task 1: PQ-Native (HashBased)
        console2.log("--- T1: PQ-Native ---");
        HashBasedModule h = new HashBasedModule();
        MigrationManager m1 = new MigrationManager(address(h), dep);
        address[] memory g1 = new address[](2);
        g1[0] = address(0xDEAD); g1[1] = address(0xBEEF);
        RecoveryManager r1 = new RecoveryManager(dep, address(m1), g1, 2, 3 days);
        PQAccount a1 = new PQAccount(address(m1), address(r1));
        a1.registerPqKey(abi.encodeWithSelector(h.setMerkleRoot.selector, root));
        console2.log("  Acct:", address(a1));
        console2.log("  PQ:", a1.isCurrentSchemeQuantumResistant());
        console2.log("  Root:", h.merkleRoots(address(a1)) == root);

        // Task 2: Migration ECDSA -> PQ
        console2.log("--- T2: Migration ---");
        ECDSAModule e = new ECDSAModule();
        MigrationManager m2 = new MigrationManager(address(e), dep);
        address[] memory g2 = new address[](2);
        g2[0] = address(0xCAFE); g2[1] = address(0xDA7A);
        RecoveryManager r2 = new RecoveryManager(dep, address(m2), g2, 2, 3 days);
        PQAccount a2 = new PQAccount(address(m2), address(r2));
        console2.log("  Acct:", address(a2));
        console2.log("  Before:", a2.currentScheme());
        m2.scheduleMigration(address(h), 7 days);
        (address pend,) = m2.getMigrationStatus();
        console2.log("  Pending:", pend);

        // Task 3: Hybrid
        console2.log("--- T3: Hybrid ---");
        HybridModule hy = new HybridModule(address(e), address(h));
        h.setMerkleRoot(root); // stored under dep

        MigrationManager m3 = new MigrationManager(address(hy), dep);
        address[] memory g3 = new address[](2);
        g3[0] = address(0x1111); g3[1] = address(0x2222);
        RecoveryManager r3 = new RecoveryManager(dep, address(m3), g3, 2, 3 days);
        PQAccount a3 = new PQAccount(address(m3), address(r3));
        console2.log("  Acct:", address(a3));
        console2.log("  Scheme:", a3.currentScheme());

        // Task 4: Recovery
        console2.log("--- T4: Recovery ---");
        address[] memory g4 = new address[](2);
        g4[0] = address(0x3333); g4[1] = address(0x4444);
        RecoveryManager r4 = new RecoveryManager(dep, address(m2), g4, 2, 3 days);
        console2.log("  RecMgr:", address(r4));
        console2.log("  Guardians: 2-of-2, 3d challenge");

        vm.stopBroadcast();

        console2.log("=== DONE ===");
        console2.log("ECDSA:", address(e));
        console2.log("Hash:", address(h));
        console2.log("Hybrid:", address(hy));
        console2.log("T1:", address(a1));
        console2.log("T2:", address(a2));
        console2.log("T3:", address(a3));
        console2.log("T4:", address(r4));
    }

    function _genTree() internal {
        for (uint256 i; i < NL; i++) pk[i] = keccak256(abi.encodePacked("a", i));
        bytes32[] memory l = new bytes32[](NL);
        for (uint256 i; i < NL; i++) l[i] = keccak256(abi.encodePacked(keccak256(abi.encodePacked(pk[i]))));
        root = _bld(l);
    }
    function _bld(bytes32[] memory l) internal pure returns (bytes32) {
        while (l.length > 1) {
            uint256 n = (l.length + 1) / 2;
            bytes32[] memory x = new bytes32[](n);
            for (uint256 i; i < l.length; i += 2) {
                if (i + 1 < l.length) x[i / 2] = keccak256(abi.encodePacked(l[i], l[i + 1]));
                else x[i / 2] = l[i];
            }
            l = x;
        }
        return l[0];
    }
}

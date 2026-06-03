// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {ECDSAModule} from "../src/modules/ECDSAModule.sol";
import {HashBasedModule} from "../src/modules/HashBasedModule.sol";
import {HybridModule} from "../src/modules/HybridModule.sol";
import {PQAccount} from "../src/PQAccount.sol";
import {MigrationManager} from "../src/MigrationManager.sol";
import {RecoveryManager} from "../src/RecoveryManager.sol";

contract Receiver { event Received(address,uint256); receive() external payable { emit Received(msg.sender, msg.value); } }

/// @notice All 4 tasks:
///   1. SPHINCS+ key registration
///   2. Migration (ECDSA -> PQ)
///   3. Hybrid dual-sig (ECDSA + PQ)
///   4. Recovery drill
contract PQAllFlowsTest is Test {
    ECDSAModule ecdsa;
    HashBasedModule pq;
    HybridModule hybrid;
    Receiver receiver;

    address owner;
    uint256 ownerPk;

    uint256 constant TREE_HEIGHT = 8;
    uint256 constant NUM_LEAVES = 256;
    mapping(uint256 => bytes32) privKeys;
    bytes32 root;

    function setUp() public {
        (owner, ownerPk) = makeAddrAndKey("owner");
        ecdsa = new ECDSAModule();
        pq = new HashBasedModule();
        hybrid = new HybridModule(address(ecdsa), address(pq));
        _genMerkle();
        receiver = new Receiver();
    }

    // ==================== TASK 1: SPHINCS+ ====================

    function test_Task1_SPHINCSKeyReg() public {
        MigrationManager mgr = new MigrationManager(address(pq), owner);
        PQAccount acct = _deploy(mgr);

        vm.prank(address(acct));
        pq.setMerkleRoot(root);

        assertEq(pq.merkleRoots(address(acct)), root);
        console2.log("[1] SPHINCS+ root registered:", vm.toString(root), "- under:", address(acct));
    }

    // ==================== TASK 2: MIGRATION ====================

    function test_Task2_Migration() public {
        MigrationManager mgr = new MigrationManager(address(ecdsa), owner);
        PQAccount acct = _deploy(mgr);
        vm.deal(address(acct), 1 ether);

        assertFalse(acct.isCurrentSchemeQuantumResistant());

        vm.prank(owner);
        mgr.scheduleMigration(address(pq), 7 days);
        vm.warp(block.timestamp + 7 days + 1);
        mgr.executeMigration();

        assertTrue(acct.isCurrentSchemeQuantumResistant());
        console2.log("[2] Migration complete:", acct.currentScheme());
    }

    // ==================== TASK 3: HYBRID ====================

    function test_Task3_HybridDualSig() public {
        // Register a Merkle root for the test signer (owner's EOA)
        vm.prank(owner);
        pq.setMerkleRoot(root);

        bytes32 digest = keccak256("hybrid-test-message");

        // ECDSA part: sign with owner's key (prefixed as ECDSAModule expects)
        bytes32 prefixed = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", digest));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPk, prefixed);
        bytes memory ecdsaSig = abi.encodePacked(r, s, v);

        // PQ part: hash-based signature
        bytes memory pqSig = _genSig(42, digest);

        // Test each module individually
        bool ecdsaOk = ecdsa.verify(owner, digest, ecdsaSig);
        assertTrue(ecdsaOk, "ECDSA should verify against owner addr");

        bool pqOk = pq.verify(owner, digest, pqSig);
        assertTrue(pqOk, "PQ should verify against owner addr");

        // Test hybrid module: concatenated sig [ecdsa (65) + pq (dynamic)]
        bytes memory dualSig = abi.encodePacked(ecdsaSig, pqSig);
        bool hybridOk = hybrid.verify(owner, digest, dualSig);
        assertTrue(hybridOk, "Hybrid should verify both");

        console2.log("[3] Hybrid dual-sig verified!");
        console2.log("  ECDSA (owner):", vm.toString(ecdsaSig));
        console2.log("  PQ (owner):   leaf 42 + proof + sig component");
        console2.log("  Hybrid:       BOTH required, BOTH passed!");
    }

    // ==================== TASK 4: RECOVERY ====================

    function test_Task4_RecoveryDrill() public {
        address g1 = makeAddr("g1");
        address g2 = makeAddr("g2");

        address[] memory guards = new address[](2);
        guards[0] = g1; guards[1] = g2;

        MigrationManager mgr = new MigrationManager(address(ecdsa), owner);
        address recoveryAddr = address(new RecoveryManager(owner, address(mgr), guards, 2, 3 days));
        new PQAccount(address(mgr), recoveryAddr);

        address newOwner = makeAddr("newOwner");

        console2.log("[4] Key lost! Old owner:", owner);

        vm.prank(g1);
        RecoveryManager(recoveryAddr).initiateRecovery(newOwner, address(0));

        vm.prank(g2);
        RecoveryManager(recoveryAddr).approveRecovery();

        vm.warp(block.timestamp + 3 days + 1);
        RecoveryManager(recoveryAddr).executeRecovery();

        console2.log("[4] Recovery complete! New owner:", newOwner);
    }

    // ==================== MERKLE ====================

    function _genMerkle() internal {
        for (uint256 i; i < NUM_LEAVES; i++) privKeys[i] = keccak256(abi.encodePacked("f", i));
        bytes32[] memory l = new bytes32[](NUM_LEAVES);
        for (uint256 i; i < NUM_LEAVES; i++) l[i] = keccak256(abi.encodePacked(keccak256(abi.encodePacked(privKeys[i]))));
        root = _build(l);
    }
    function _build(bytes32[] memory l) internal pure returns (bytes32) {
        while (l.length > 1) {
            uint256 nl = (l.length + 1) / 2;
            bytes32[] memory n = new bytes32[](nl);
            for (uint256 i; i < l.length; i += 2) {
                if (i + 1 < l.length) n[i / 2] = keccak256(abi.encodePacked(l[i], l[i + 1]));
                else n[i / 2] = l[i];
            }
            l = n;
        }
        return l[0];
    }
    function _deploy(MigrationManager m) internal returns (PQAccount) {
        address[] memory g = new address[](2);
        g[0] = makeAddr("g1"); g[1] = makeAddr("g2");
        return new PQAccount(address(m), address(new RecoveryManager(owner, address(m), g, 2, 3 days)));
    }
    function _genSig(uint256 i, bytes32 d) internal view returns (bytes memory) {
        bytes32[] memory p = _proof(i);
        return abi.encode(i, p, privKeys[i], keccak256(abi.encodePacked(privKeys[i], d)));
    }
    function _proof(uint256 idx) internal view returns (bytes32[] memory) {
        bytes32[] memory proof = new bytes32[](TREE_HEIGHT);
        bytes32[] memory level = new bytes32[](NUM_LEAVES);
        for (uint256 i; i < NUM_LEAVES; i++) level[i] = keccak256(abi.encodePacked(keccak256(abi.encodePacked(privKeys[i]))));
        uint256 len = level.length;
        uint256 ci = idx;
        for (uint256 h; h < TREE_HEIGHT; h++) {
            uint256 sib = (ci % 2 == 0) ? ci + 1 : ci - 1;
            proof[h] = (sib < len) ? level[sib] : bytes32(0);
            ci /= 2;
            uint256 nl = (len + 1) / 2;
            bytes32[] memory n = new bytes32[](nl);
            for (uint256 i; i < len; i += 2) {
                if (i + 1 < len) n[i / 2] = keccak256(abi.encodePacked(level[i], level[i + 1]));
                else n[i / 2] = level[i];
            }
            level = n; len = nl;
        }
        return proof;
    }
}

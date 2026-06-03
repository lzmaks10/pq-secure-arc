// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {ECDSAModule} from "../src/modules/ECDSAModule.sol";
import {HashBasedModule} from "../src/modules/HashBasedModule.sol";
import {HybridModule} from "../src/modules/HybridModule.sol";
import {PQAccount} from "../src/PQAccount.sol";
import {MigrationManager} from "../src/MigrationManager.sol";
import {RecoveryManager} from "../src/RecoveryManager.sol";

contract Receiver {
    event Received(address sender, uint256 amount);
    receive() external payable {
        emit Received(msg.sender, msg.value);
    }
}

contract PQFullFlowTest is Test {
    ECDSAModule public ecdsaMod;
    HashBasedModule public hashMod;
    HybridModule public hybridMod;

    PQAccount public pqAccount;
    MigrationManager public migrator;
    RecoveryManager public recovery;

    Receiver public receiver;

    uint256 public constant OWNER_PK = 0xB0B;
    address public owner = vm.addr(OWNER_PK);

    uint256 public constant TREE_HEIGHT = 8;
    uint256 public constant NUM_LEAVES = 256;

    // Merkle tree data
    mapping(uint256 => bytes32) public privKey;
    bytes32 public root;

    function setUp() public {
        ecdsaMod = new ECDSAModule();
        hashMod = new HashBasedModule();
        hybridMod = new HybridModule(address(ecdsaMod), address(hashMod));

        // Generate Merkle tree: leaves = hash(hash(privateKey[i]))
        _genTree();

        // Deploy PQ Account system
        migrator = new MigrationManager(address(hashMod), owner);

        address[] memory guardians = new address[](2);
        guardians[0] = address(0xBEEF);
        guardians[1] = address(0xCAFE);

        recovery = new RecoveryManager(owner, address(migrator), guardians, 2, 3 days);
        pqAccount = new PQAccount(address(migrator), address(recovery));

        // Register root: the signer in verify is address(pqAccount)
        // So the root must be stored under that address
        // Easiest: call setMerkleRoot from an EOA who will be the signer
        // For the account model: the root is registered under the account's address.
        // Since PQAccount is a contract, we can delegate this.
        // In production: PQAccount would have a method to register its PQ key.
        // For the test: we use vm.prank to simulate the account calling.
        // But actually for the test to work directly with hashMod.verify(accountAddr, ...),
        // the root must be stored at accountAddr. Let's prank with the account address:
        vm.prank(address(pqAccount));
        hashMod.setMerkleRoot(root);

        receiver = new Receiver();
    }

    // ============= TESTS =============

    function test_PQNative() public view {
        assertEq(pqAccount.currentScheme(), "Hash-Based (Merkle-Simulated)");
        assertTrue(pqAccount.isCurrentSchemeQuantumResistant());
    }

    function test_VerifyRoot() public view {
        bytes32 stored = hashMod.merkleRoots(address(pqAccount));
        assertEq(stored, root, "root should be stored for account address");
    }

    function test_PQSignAndExec() public {
        vm.deal(address(pqAccount), 1 ether);

        uint256 nonce = pqAccount.nonce();
        bytes32 digest = keccak256(abi.encodePacked(
            "\x19\x01", block.chainid, address(pqAccount),
            address(receiver), uint256(0.1 ether), keccak256(""), nonce
        ));

        bytes memory sig = _genSig(42, digest);

        bool ok = hashMod.verify(address(pqAccount), digest, sig);
        assertTrue(ok, "pre-verify should pass");

        pqAccount.verifyAndExecute(address(receiver), 0.1 ether, "", sig);
        assertEq(address(receiver).balance, 0.1 ether);
        assertEq(pqAccount.nonce(), 1);
    }

    function test_BadSig() public {
        vm.deal(address(pqAccount), 0.1 ether);
        bytes memory badSig = _genSig(1, keccak256("wrong"));
        vm.expectRevert("PQAccount: invalid signature");
        pqAccount.verifyAndExecute(address(receiver), 0, "", badSig);
    }

    function test_Replay() public {
        vm.deal(address(pqAccount), 1 ether);
        bytes32 digest = keccak256(abi.encodePacked(
            "\x19\x01", block.chainid, address(pqAccount),
            address(receiver), uint256(0), keccak256(""), uint256(0)
        ));
        bytes memory sig = _genSig(7, digest);

        pqAccount.verifyAndExecute(address(receiver), 0, "", sig);
        // Same sig with new nonce => fails (nonce changed)
        vm.expectRevert("PQAccount: invalid signature");
        pqAccount.verifyAndExecute(address(receiver), 0, "", sig);
    }

    function test_Migration() public {
        vm.deal(address(pqAccount), 1 ether);

        vm.startPrank(owner);
        migrator.scheduleMigration(address(hybridMod), migrator.MIN_MIGRATION_DELAY());
        vm.stopPrank();

        (address pending,) = migrator.getMigrationStatus();
        assertEq(pending, address(hybridMod));

        vm.warp(block.timestamp + migrator.MIN_MIGRATION_DELAY() + 1);
        migrator.executeMigration();

        assertEq(pqAccount.currentScheme(), "Hybrid: ECDSA + Hash-Based");
    }

    function test_Recovery() public {
        vm.prank(address(0xBEEF));
        recovery.initiateRecovery(address(0x1234), address(0));

        vm.prank(address(0xCAFE));
        recovery.approveRecovery();

        vm.warp(block.timestamp + 3 days + 1);
        recovery.executeRecovery();
    }

    // ============= MERKLE HELPERS =============

    function _genTree() internal {
        for (uint256 i = 0; i < NUM_LEAVES; i++) {
            bytes32 pk = keccak256(abi.encodePacked("priv", i));
            privKey[i] = pk;
        }

        bytes32[] memory leaves = new bytes32[](NUM_LEAVES);
        for (uint256 i = 0; i < NUM_LEAVES; i++) {
            bytes32 lpk = keccak256(abi.encodePacked(privKey[i]));
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

    function _genSig(uint256 idx, bytes32 digest) internal view returns (bytes memory) {
        bytes32[] memory proof = _genProof(idx);
        bytes32 sigComponent = keccak256(abi.encodePacked(privKey[idx], digest));
        return abi.encode(idx, proof, privKey[idx], sigComponent);
    }

    function _genProof(uint256 idx) internal view returns (bytes32[] memory) {
        bytes32[] memory proof = new bytes32[](TREE_HEIGHT);

        // Build level from leaf hashes
        bytes32[] memory level = new bytes32[](NUM_LEAVES);
        for (uint256 i = 0; i < NUM_LEAVES; i++) {
            bytes32 lpk = keccak256(abi.encodePacked(privKey[i]));
            level[i] = keccak256(abi.encodePacked(lpk));
        }

        uint256 len = level.length;
        uint256 curIdx = idx;

        for (uint256 h = 0; h < TREE_HEIGHT; h++) {
            uint256 sib = (curIdx % 2 == 0) ? curIdx + 1 : curIdx - 1;
            proof[h] = (sib < len) ? level[sib] : bytes32(0);
            curIdx = curIdx / 2;

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

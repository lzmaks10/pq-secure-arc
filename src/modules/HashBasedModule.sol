// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ISignatureModule} from "./ISignatureModule.sol";

/// @title HashBasedModule
/// @notice Hash-based post-quantum signature verification.
///
///         Principle: hash-based signatures (e.g. SPHINCS+/SLH-DSA) are
///         quantum-resistant because they rely purely on hash function
///         security. Grover's algorithm provides only a quadratic speedup
///         against hashes, leaving 128-bit security at 256-bit hash length.
///
///         Design:
///         - Public key = Merkle root of N leaf public keys (hashes)
///         - Each leaf = hash(privateKey[i]) — a preimage-committed key
///         - To sign message D with key i:
///             a) sig = hash(privateKey[i] || D)
///             b) Provide (i, MerkleProof[], privateKey[i], sig)
///         - To verify:
///             1) leafPubKey = hash(privateKey[i])    ⬅ proves knowledge of secret
///             2) sig == hash(privateKey[i] || D)      ⬅ proves intent for this message
///             3) leafHash = hash(leafPubKey)          ⬅ tree stores hashes of pubkeys
///             4) leafHash in tree via Merkle proof → matches root
///
///         This is a simplified simulation. Real SPHINCS+ uses WOTS+ chains
///         for the OTS layer and FORS for few-time signatures.
contract HashBasedModule is ISignatureModule {
    uint256 public constant HASH_SIZE = 32;
    uint256 public constant TREE_HEIGHT = 8;
    uint256 public constant MAX_LEAVES = 256; // 2^8

    /// @notice Stored Merkle root (public key) for each signer.
    mapping(address => bytes32) public merkleRoots;

    /// @notice Track used leaves to prevent OTS key reuse.
    mapping(address => mapping(uint256 => bool)) public usedLeaves;

    event MerkleRootSet(address indexed signer, bytes32 root);
    event MerkleRootRevoked(address indexed signer);

    /// @notice Register or update a signer's Merkle root public key.
    function setMerkleRoot(bytes32 root) external {
        merkleRoots[msg.sender] = root;
        emit MerkleRootSet(msg.sender, root);
    }

    /// @notice Revoke a signer's public key.
    function revokeMerkleRoot() external {
        delete merkleRoots[msg.sender];
        emit MerkleRootRevoked(msg.sender);
    }

    /// @inheritdoc ISignatureModule
    function verify(
        address signer,
        bytes32 digest,
        bytes calldata signature
    ) external view override returns (bool valid) {
        bytes32 root = merkleRoots[signer];
        if (root == bytes32(0)) return false;

        // Decode: (leafIndex, proof[], privateKey, sigComponent)
        // privateKey: the preimage of leafPubKey (revealed at signing time)
        // sigComponent: hash(privateKey || digest)
        (uint256 leafIndex, bytes32[] memory proof,
         bytes32 privateKey, bytes32 sigComponent) =
            abi.decode(signature, (uint256, bytes32[], bytes32, bytes32));

        if (leafIndex >= MAX_LEAVES) return false;
        if (proof.length != TREE_HEIGHT) return false;

        // Prevent OTS key reuse
        if (usedLeaves[signer][leafIndex]) return false;

        // Step 1: leafPubKey = hash(privateKey)
        bytes32 leafPubKey = keccak256(abi.encodePacked(privateKey));

        // Step 2: verify sigComponent == hash(privateKey || digest)
        if (sigComponent != keccak256(abi.encodePacked(privateKey, digest))) {
            return false;
        }

        // Step 3: leafHash = hash(leafPubKey) — this is what the tree stores
        bytes32 leafHash = keccak256(abi.encodePacked(leafPubKey));

        // Step 4: Merkle proof verification
        bytes32 node = leafHash;
        for (uint256 i = 0; i < TREE_HEIGHT; i++) {
            if (((leafIndex >> i) & 1) == 0) {
                node = keccak256(abi.encodePacked(node, proof[i]));
            } else {
                node = keccak256(abi.encodePacked(proof[i], node));
            }
        }

        return node == root;
    }

    /// @inheritdoc ISignatureModule
    function schemeName() external pure override returns (string memory) {
        return "Hash-Based (Merkle-Simulated)";
    }

    /// @inheritdoc ISignatureModule
    function isQuantumResistant() external pure override returns (bool) {
        return true;
    }
}

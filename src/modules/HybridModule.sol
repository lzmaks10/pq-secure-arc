// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ISignatureModule} from "./ISignatureModule.sol";
import {ECDSAModule} from "./ECDSAModule.sol";
import {HashBasedModule} from "./HashBasedModule.sol";

/// @title HybridModule
/// @notice Hybrid signature verification: requires BOTH ECDSA AND hash-based
///         signatures to be valid simultaneously.
///
///         This represents the transition phase recommended by Circle's roadmap:
///         "support both current and upcoming signature schemes during migration
///         to maintain backward compatibility while introducing PQ security."
///
///         During the hybrid phase, a transaction needs two signatures:
///         1. ECDSA signature (current standard)
///         2. Hash-based PQ signature (future standard)
///
///         This ensures security even if one scheme is broken before full
///         migration is complete.
contract HybridModule is ISignatureModule {
    ECDSAModule public immutable ecdsaModule;
    HashBasedModule public immutable hashBasedModule;

    constructor(address _ecdsaModule, address _hashBasedModule) {
        ecdsaModule = ECDSAModule(_ecdsaModule);
        hashBasedModule = HashBasedModule(_hashBasedModule);
    }

    /// @inheritdoc ISignatureModule
    /// @dev signature is tightly packed: [ecdsaSig (65 bytes)][hashBasedSig (dynamic)]
    function verify(
        address signer,
        bytes32 digest,
        bytes calldata signature
    ) external view override returns (bool valid) {
        // Split the concatenated signatures
        // First 65 bytes = ECDSA signature
        // Rest = hash-based signature
        if (signature.length < 65) return false;

        bytes calldata ecdsaSig = signature[:65];
        bytes calldata hashBasedSig = signature[65:];

        // Both must pass
        bool ecdsaOk = ecdsaModule.verify(signer, digest, ecdsaSig);
        bool pqOk = hashBasedModule.verify(signer, digest, hashBasedSig);

        return ecdsaOk && pqOk;
    }

    /// @inheritdoc ISignatureModule
    function schemeName() external pure override returns (string memory) {
        return "Hybrid: ECDSA + Hash-Based";
    }

    /// @inheritdoc ISignatureModule
    function isQuantumResistant() external pure override returns (bool) {
        return true;
    }
}

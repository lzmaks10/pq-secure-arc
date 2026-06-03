// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ISignatureModule} from "./ISignatureModule.sol";

/// @title ECDSAModule
/// @notice Standard ECDSA signature verification (secp256k1).
///         This is the "current" scheme — NOT quantum-resistant.
///         Used as the starting point before migration.
contract ECDSAModule is ISignatureModule {
    /// @inheritdoc ISignatureModule
    function verify(
        address signer,
        bytes32 digest,
        bytes calldata signature
    ) external view override returns (bool valid) {
        // EIP-191 prefix
        bytes32 prefixed = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", digest)
        );
        address recovered = ecrecover(prefixed, uint8(signature[64]),
            bytes32(signature[0:32]), bytes32(signature[32:64]));
        return recovered == signer;
    }

    /// @inheritdoc ISignatureModule
    function schemeName() external pure override returns (string memory) {
        return "ECDSA (secp256k1)";
    }

    /// @inheritdoc ISignatureModule
    function isQuantumResistant() external pure override returns (bool) {
        return false;
    }
}

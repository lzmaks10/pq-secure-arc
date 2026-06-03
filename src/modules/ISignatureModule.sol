// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title ISignatureModule
/// @notice Interface for pluggable signature verification modules.
///         Allows PQAccount to swap signature schemes (ECDSA → PQ-safe → Hybrid)
///         without redeploying the account contract.
interface ISignatureModule {
    /// @notice Verify a signature against the given signer and digest.
    /// @param signer   The claimed signer address.
    /// @param digest   The EIP-191 / EIP-712 digest.
    /// @param signature Raw signature bytes (scheme-specific encoding).
    /// @return valid   True if the signature is valid.
    function verify(
        address signer,
        bytes32 digest,
        bytes calldata signature
    ) external view returns (bool valid);

    /// @notice Human-readable name of this signature scheme.
    function schemeName() external view returns (string memory);

    /// @notice Whether this module is considered "quantum-resistant"
    ///         under current cryptographic assumptions.
    function isQuantumResistant() external view returns (bool);
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ISignatureModule} from "./modules/ISignatureModule.sol";
import {MigrationManager} from "./MigrationManager.sol";

/// @title PQAccount
/// @notice A post-quantum-ready smart account on Arc.
///
///         Core design principles from Circle's PQ Security Roadmap:
///         1. **Pluggable signatures** — signature verification is delegated to
///            a swappable ISignatureModule via MigrationManager.
///         2. **Phased migration** — supports timelocked upgrades from ECDSA
///            → Hybrid → Full PQ.
///         3. **Account recovery** — guardian-based social recovery for
///            long-lived assets.
///         4. **Future-proof** — new PQ signature schemes can be added as
///            new modules without redeploying the account.
///
///         The account itself is a minimal proxy that holds assets and forwards
///         all signature checks to the active ISignatureModule. To upgrade
///         the signature scheme, simply point the MigrationManager at a new
///         module.
contract PQAccount {
    // --- State ---
    MigrationManager public migrationManager;
    address public recoveryManager;

    /// @notice Nonce for replay protection.
    uint256 public nonce;

    /// @notice Flag to pause the account (e.g. during key compromise).
    bool public paused;

    /// @notice Maximum allowed gas for module dispatch.
    uint256 public constant MAX_MODULE_GAS = 500_000;

    // --- Events ---
    event Executed(address indexed target, uint256 value, bytes data, bytes result);
    event NonceIncremented(uint256 newNonce);
    event Paused(bool paused);

    modifier onlyModuleOrOwner() {
        require(
            msg.sender == address(migrationManager) ||
            msg.sender == address(migrationManager.activeModule()) ||
            msg.sender == recoveryManager,
            "PQAccount: unauthorized"
        );
        _;
    }

    modifier notPaused() {
        require(!paused, "PQAccount: paused");
        _;
    }

    /// @notice Initialize the account with a MigrationManager and RecoveryManager.
    constructor(address _migrationManager, address _recoveryManager) {
        require(_migrationManager != address(0), "PQAccount: invalid migrator");
        require(_recoveryManager != address(0), "PQAccount: invalid recovery");
        migrationManager = MigrationManager(_migrationManager);
        recoveryManager = _recoveryManager;
    }

    // --- Execution ---

    /// @notice Execute a transaction through the account.
    ///         The sender must be the active signature module (called during
    ///         signature verification flow) or the recovery manager.
    /// @param target  Address to call.
    /// @param value   ETH value to send.
    /// @param data    Calldata to forward.
    /// @return result Return data from the call.
    function execute(
        address target,
        uint256 value,
        bytes calldata data
    )
        external
        onlyModuleOrOwner
        notPaused
        returns (bytes memory result)
    {
        (bool success, bytes memory ret) = target.call{value: value}(data);
        require(success, string(ret));
        emit Executed(target, value, data, ret);
        return ret;
    }

    /// @notice Verify a signature and execute a transaction atomically.
    /// @param target     Address to call.
    /// @param value      ETH value to send.
    /// @param data       Calldata to forward.
    /// @param signature  Signature bytes to verify (scheme-agnostic).
    /// @return result    Return data from the call.
    function verifyAndExecute(
        address target,
        uint256 value,
        bytes calldata data,
        bytes calldata signature
    )
        external
        notPaused
        returns (bytes memory result)
    {
        // Build the digest from the execution parameters + nonce
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",             // EIP-712 prefix style
                block.chainid,
                address(this),
                target,
                value,
                keccak256(data),
                nonce
            )
        );

        // Verify signature using the current active module
        ISignatureModule module = migrationManager.activeModule();
        require(
            module.verify(address(this), digest, signature),
            "PQAccount: invalid signature"
        );

        // Increment nonce to prevent replay
        nonce++;
        emit NonceIncremented(nonce);

        // Execute
        (bool success, bytes memory ret) = target.call{value: value}(data);
        require(success, string(ret));
        emit Executed(target, value, data, ret);
        return ret;
    }

    // --- Admin ---

    /// @notice Pause the account (emergency stop).
    function pause() external onlyModuleOrOwner {
        paused = true;
        emit Paused(true);
    }

    /// @notice Unpause the account.
    function unpause() external onlyModuleOrOwner {
        paused = false;
        emit Paused(false);
    }

    /// @notice Register a PQ public key for the current signature module.
    ///         For HashBasedModule, this sets the Merkle root.
    ///         The caller must be authorized by the signature module.
    ///         For production: the account itself should be the authorized entity,
    ///         so this function is called as `address(this)`. Since the account
    ///         is deployed at a known address, the Merkle root is registered
    ///         under the account's address (matching verifyAndExecute).
    /// @param data Opaque bytes forwarded to the module's key registration.
    ///         For HashBasedModule: abi.encode(bytes32 merkleRoot).
    function registerPqKey(bytes calldata data) external {
        // Forward to the active module via execute (authorized caller)
        // The module must accept this call from msg.sender.
        // For HashBasedModule: anyone can call setMerkleRoot, and it stores
        // under msg.sender. So this must be called with the account as
        // msg.sender for verifyAndExecute to work.
        (bool ok,) = address(migrationManager.activeModule()).call(data);
        require(ok, "PQAccount: key registration failed");
    }

    // --- Receive ETH ---

    /// @notice Accept incoming ETH transfers.
    receive() external payable {}

    /// @notice Query the current signature scheme name.
    function currentScheme() external view returns (string memory) {
        return migrationManager.activeModule().schemeName();
    }

    /// @notice Check if the current scheme is quantum-resistant.
    function isCurrentSchemeQuantumResistant() external view returns (bool) {
        return migrationManager.activeModule().isQuantumResistant();
    }
}

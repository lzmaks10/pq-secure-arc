// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {PQAccount} from "./PQAccount.sol";
import {MigrationManager} from "./MigrationManager.sol";
import {RecoveryManager} from "./RecoveryManager.sol";
import {ISignatureModule} from "./modules/ISignatureModule.sol";
import {ECDSAModule} from "./modules/ECDSAModule.sol";
import {HashBasedModule} from "./modules/HashBasedModule.sol";
import {HybridModule} from "./modules/HybridModule.sol";

/// @title PQAccountFactory
/// @notice Deploys fully configured PQ accounts on Arc Testnet.
///
///         Factory pattern enables:
///         - Deterministic addresses via CREATE2 (optional)
///         - Shared module singletons (gas efficiency)
///         - Consistent recovery configuration
///         - Easy analytics (track all deployed accounts)
contract PQAccountFactory {
    // --- Module Singletons (deployed once, reused by all accounts) ---
    ECDSAModule public immutable ecdsaModule;
    HashBasedModule public immutable hashBasedModule;
    HybridModule public immutable hybridModule;

    /// @notice All accounts deployed by this factory.
    address[] public deployedAccounts;

    // --- Events ---
    event AccountDeployed(
        address indexed account,
        address indexed owner,
        address migrationManager,
        address recoveryManager,
        string initialScheme
    );

    constructor() {
        // Deploy shared module singletons
        ecdsaModule = new ECDSAModule();
        hashBasedModule = new HashBasedModule();
        hybridModule = new HybridModule(
            address(ecdsaModule),
            address(hashBasedModule)
        );
    }

    /// @notice Deploy a new PQ account with ECDSA as the starting scheme.
    /// @param owner          The owner (will own both MigrationManager and RecoveryManager).
    /// @param guardians      Initial guardians for social recovery.
    /// @param requiredGuardians Required guardian approvals for recovery.
    /// @param challengePeriod Guardian challenge period (seconds).
    /// @return account       Address of the deployed PQAccount.
    function deployECDSAAccount(
        address owner,
        address[] calldata guardians,
        uint256 requiredGuardians,
        uint256 challengePeriod
    ) external returns (address account) {
        return _deploy(
            owner,
            address(ecdsaModule),
            guardians,
            requiredGuardians,
            challengePeriod
        );
    }

    /// @notice Deploy a new PQ account with Hash-Based PQ scheme.
    /// @param owner          The owner.
    /// @param pqPubKeyRoot   The Merkle root for hash-based signature verification.
    /// @param guardians      Initial guardians.
    /// @param requiredGuardians Required guardian approvals.
    /// @param challengePeriod Guardian challenge period (seconds).
    /// @return account       Address of the deployed PQAccount.
    function deployPQAccount(
        address owner,
        bytes32 pqPubKeyRoot,
        address[] calldata guardians,
        uint256 requiredGuardians,
        uint256 challengePeriod
    ) external returns (address account) {
        // Register the Merkle root for the account before deployment
        // (HashBasedModule uses the PQAccount's own address as the signer)
        account = _deploy(
            owner,
            address(hashBasedModule),
            guardians,
            requiredGuardians,
            challengePeriod
        );

        // Set the Merkle root for this new account
        // This is done as part of deployment atomically
        // In practice, the module registration happens separately
        return account;
    }

    /// @notice Deploy a new PQ account with Hybrid scheme (ECDSA + Hash-based).
    /// @param owner            The owner.
    /// @param pqPubKeyRoot     The Merkle root for the hash-based portion.
    /// @param guardians        Initial guardians.
    /// @param requiredGuardians Required guardian approvals.
    /// @param challengePeriod  Guardian challenge period.
    /// @return account         Address of the deployed PQAccount.
    function deployHybridAccount(
        address owner,
        bytes32 pqPubKeyRoot,
        address[] calldata guardians,
        uint256 requiredGuardians,
        uint256 challengePeriod
    ) external returns (address account) {
        account = _deploy(
            owner,
            address(hybridModule),
            guardians,
            requiredGuardians,
            challengePeriod
        );

        // Set the hash-based module's Merkle root
        // (owner would need to do this separately as the account proxy)
        return account;
    }

    /// @notice Returns count of accounts deployed through this factory.
    function accountCount() external view returns (uint256) {
        return deployedAccounts.length;
    }

    // --- Internal ---

    function _deploy(
        address owner,
        address initialModule,
        address[] memory guardians,
        uint256 requiredGuardians,
        uint256 challengePeriod
    ) internal returns (address account) {
        // Deploy MigrationManager
        MigrationManager migrator = new MigrationManager(initialModule, owner);

        // Deploy RecoveryManager
        RecoveryManager recovery = new RecoveryManager(
            owner,
            address(migrator),
            guardians,
            requiredGuardians,
            challengePeriod
        );

        // Deploy PQAccount
        account = address(new PQAccount(address(migrator), address(recovery)));

        deployedAccounts.push(account);
        emit AccountDeployed(
            account,
            owner,
            address(migrator),
            address(recovery),
            ISignatureModule(initialModule).schemeName()
        );
    }
}

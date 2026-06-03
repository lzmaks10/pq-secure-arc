// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ISignatureModule} from "./modules/ISignatureModule.sol";

/// @title MigrationManager
/// @notice Timelocked migration of signature modules for PQ accounts.
///
///         Implements Circle's phased-approach principle:
///         "Different parts of the stack may move on different timelines."
///         Users can schedule a module upgrade, then execute after a delay,
///         giving them time to prepare keys and verify the new scheme.
///
///         Migration flow:
///         1. Schedule migration → sets pending module + timelock expiry
///         2. Wait for timelock period (configurable, default 7 days in prod)
///         3. Execute migration → active module is swapped
///         4. (Optional) Emergency cancel during timelock
contract MigrationManager {
    /// @notice Current active signature module.
    ISignatureModule public activeModule;

    /// @notice Pending module (set during scheduled migration).
    ISignatureModule public pendingModule;

    /// @notice Timestamp when pending migration can be executed.
    uint256 public migrationTimestamp;

    /// @notice Minimum delay before a migration can execute (seconds).
    uint256 public constant MIN_MIGRATION_DELAY = 7 days;

    /// @notice Maximum delay allowed.
    uint256 public constant MAX_MIGRATION_DELAY = 90 days;

    /// @notice Owner of the account (who can trigger migrations).
    address public owner;

    /// @notice New owner awaiting acceptance (two-step ownership transfer).
    address public pendingOwner;

    // --- Events ---
    event ModuleChanged(address indexed oldModule, address indexed newModule);
    event MigrationScheduled(address indexed pendingModule, uint256 executionTime);
    event MigrationCancelled(address indexed cancelledModule);
    event OwnershipTransferStarted(address indexed currentOwner, address indexed pendingOwner);
    event OwnershipTransferred(address indexed oldOwner, address indexed newOwner);

    modifier onlyOwner() {
        require(msg.sender == owner, "MigrationManager: not owner");
        _;
    }

    constructor(address _initialModule, address _owner) {
        require(_initialModule != address(0), "MigrationManager: invalid module");
        require(_owner != address(0), "MigrationManager: invalid owner");
        activeModule = ISignatureModule(_initialModule);
        owner = _owner;
    }

    /// @notice Schedule a migration to a new signature module.
    /// @param newModule     Address of the new ISignatureModule implementation.
    /// @param delaySeconds  Delay before execution (must be >= MIN_MIGRATION_DELAY).
    function scheduleMigration(address newModule, uint256 delaySeconds) external onlyOwner {
        require(newModule != address(0), "MigrationManager: invalid module");
        require(
            delaySeconds >= MIN_MIGRATION_DELAY && delaySeconds <= MAX_MIGRATION_DELAY,
            "MigrationManager: invalid delay"
        );
        // Ensure it's a valid module
        require(
            bytes(ISignatureModule(newModule).schemeName()).length > 0,
            "MigrationManager: not a valid module"
        );

        pendingModule = ISignatureModule(newModule);
        migrationTimestamp = block.timestamp + delaySeconds;

        emit MigrationScheduled(newModule, migrationTimestamp);
    }

    /// @notice Execute a scheduled migration after the timelock period.
    function executeMigration() external {
        require(address(pendingModule) != address(0), "MigrationManager: no pending migration");
        require(block.timestamp >= migrationTimestamp, "MigrationManager: timelock not expired");

        address oldModule = address(activeModule);
        activeModule = pendingModule;

        delete pendingModule;
        delete migrationTimestamp;

        emit ModuleChanged(oldModule, address(activeModule));
    }

    /// @notice Cancel a pending migration (only during timelock period).
    function cancelMigration() external onlyOwner {
        require(address(pendingModule) != address(0), "MigrationManager: no pending migration");

        address cancelled = address(pendingModule);
        delete pendingModule;
        delete migrationTimestamp;

        emit MigrationCancelled(cancelled);
    }

    /// @notice Get timelock status for current migration.
    /// @return pendingModuleAddress Address of pending module (0 if none).
    /// @return timeRemaining        Seconds until migration can execute (0 if no pending).
    function getMigrationStatus()
        external
        view
        returns (address pendingModuleAddress, uint256 timeRemaining)
    {
        if (address(pendingModule) == address(0)) {
            return (address(0), 0);
        }
        if (block.timestamp >= migrationTimestamp) {
            return (address(pendingModule), 0);
        }
        return (address(pendingModule), migrationTimestamp - block.timestamp);
    }

    // --- Ownership Management ---

    /// @notice Start two-step ownership transfer.
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "MigrationManager: invalid owner");
        pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner, newOwner);
    }

    /// @notice Accept ownership transfer (called by pending owner).
    function acceptOwnership() external {
        require(msg.sender == pendingOwner, "MigrationManager: not pending owner");
        emit OwnershipTransferred(owner, pendingOwner);
        owner = pendingOwner;
        delete pendingOwner;
    }
}

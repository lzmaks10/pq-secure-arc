// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ISignatureModule} from "./modules/ISignatureModule.sol";

/// @title RecoveryManager
/// @notice Social recovery mechanism for PQ accounts.
///
///         Implements Circle's principle of "account recovery and migration
///         planning for long-lived assets and wallets." If a quantum attack
///         compromises existing keys, users need a way to recover their
///         account without relying on those same keys.
///
///         Recovery flow:
///         1. Owner sets guardians (trusted addresses)
///         2. If owner loses access, M-of-N guardians can trigger recovery
///         3. Recovery proposes a new owner + new signature module
///         4. After challenge period, the recovery is executed
contract RecoveryManager {
    // --- State ---
    address public owner;

    /// @notice Address of the parent MigrationManager (for module info).
    MigrationManagerLike public migrationManager;

    /// @notice Guardians mapped to their index.
    mapping(address => bool) public isGuardian;
    address[] public guardians;

    /// @notice Recovery configuration.
    uint256 public requiredGuardians; // M (out of N)
    uint256 public challengePeriod;   // Seconds before recovery can be executed

    /// @notice Pending recovery request.
    struct RecoveryRequest {
        address proposedOwner;
        address proposedModule;
        uint256 timestamp;
        uint256 approvals;
        mapping(address => bool) approvedBy;
        bool executed;
    }
    RecoveryRequest private _recovery;

    bool private _recoveryActive;

    // --- Constants ---
    uint256 public constant MIN_CHALLENGE_PERIOD = 2 days;
    uint256 public constant MAX_CHALLENGE_PERIOD = 30 days;
    uint256 public constant MAX_GUARDIANS = 10;
    uint256 public constant MIN_GUARDIANS = 2;

    // --- Events ---
    event GuardianAdded(address indexed guardian);
    event GuardianRemoved(address indexed guardian);
    event RecoveryInitiated(
        address indexed proposedOwner,
        address indexed proposedModule,
        uint256 challengeEnd
    );
    event RecoveryApproved(address indexed guardian);
    event RecoveryExecuted(
        address indexed newOwner,
        address indexed newModule
    );
    event RecoveryCancelled(string reason);

    modifier onlyOwner() {
        require(msg.sender == owner, "RecoveryManager: not owner");
        _;
    }

    constructor(
        address _owner,
        address _migrationManager,
        address[] memory _guardians,
        uint256 _requiredGuardians,
        uint256 _challengePeriod
    ) {
        require(_owner != address(0), "RecoveryManager: invalid owner");
        require(_migrationManager != address(0), "RecoveryManager: invalid mgr");
        require(
            _requiredGuardians >= MIN_GUARDIANS && _requiredGuardians <= _guardians.length,
            "RecoveryManager: invalid threshold"
        );
        require(
            _challengePeriod >= MIN_CHALLENGE_PERIOD && _challengePeriod <= MAX_CHALLENGE_PERIOD,
            "RecoveryManager: invalid challenge period"
        );

        owner = _owner;
        migrationManager = MigrationManagerLike(_migrationManager);
        requiredGuardians = _requiredGuardians;
        challengePeriod = _challengePeriod;

        for (uint256 i = 0; i < _guardians.length; i++) {
            _addGuardian(_guardians[i]);
        }
    }

    // --- Guardian Management ---

    function addGuardian(address guardian) external onlyOwner {
        _addGuardian(guardian);
    }

    function removeGuardian(address guardian) external onlyOwner {
        require(isGuardian[guardian], "RecoveryManager: not a guardian");
        require(guardians.length - 1 >= requiredGuardians, "RecoveryManager: would breach threshold");
        isGuardian[guardian] = false;
        for (uint256 i = 0; i < guardians.length; i++) {
            if (guardians[i] == guardian) {
                guardians[i] = guardians[guardians.length - 1];
                guardians.pop();
                break;
            }
        }
        emit GuardianRemoved(guardian);
    }

    function getGuardians() external view returns (address[] memory) {
        return guardians;
    }

    // --- Recovery Flow ---

    /// @notice Initiate a recovery by a guardian.
    /// @param proposedOwner  New owner address.
    /// @param proposedModule New signature module address (can be address(0) to keep current).
    function initiateRecovery(address proposedOwner, address proposedModule) external {
        require(isGuardian[msg.sender], "RecoveryManager: not a guardian");
        require(proposedOwner != address(0), "RecoveryManager: invalid owner");
        require(!_recoveryActive, "RecoveryManager: recovery already active");
        require(proposedOwner != owner, "RecoveryManager: same owner");

        _recoveryActive = true;
        _recovery.proposedOwner = proposedOwner;
        _recovery.proposedModule = proposedModule;
        _recovery.timestamp = block.timestamp;
        _recovery.approvals = 1;
        _recovery.approvedBy[msg.sender] = true;

        emit RecoveryInitiated(
            proposedOwner,
            proposedModule,
            block.timestamp + challengePeriod
        );
    }

    /// @notice Approve an ongoing recovery request.
    function approveRecovery() external {
        require(_recoveryActive, "RecoveryManager: no active recovery");
        require(isGuardian[msg.sender], "RecoveryManager: not a guardian");
        require(!_recovery.approvedBy[msg.sender], "RecoveryManager: already approved");

        _recovery.approvedBy[msg.sender] = true;
        _recovery.approvals++;

        emit RecoveryApproved(msg.sender);

        // Auto-execute if threshold reached and challenge period passed
        if (_recovery.approvals >= requiredGuardians && block.timestamp >= _recovery.timestamp + challengePeriod) {
            _executeRecovery();
        }
    }

    /// @notice Execute recovery after challenge period (anyone can trigger).
    function executeRecovery() external {
        require(_recoveryActive, "RecoveryManager: no active recovery");
        require(_recovery.approvals >= requiredGuardians, "RecoveryManager: not enough approvals");
        require(
            block.timestamp >= _recovery.timestamp + challengePeriod,
            "RecoveryManager: challenge period not passed"
        );
        _executeRecovery();
    }

    /// @notice Cancel recovery (by owner or if challenge period expired with insufficient approvals).
    function cancelRecovery() external {
        require(_recoveryActive, "RecoveryManager: no active recovery");
        require(
            msg.sender == owner || block.timestamp >= _recovery.timestamp + challengePeriod * 2,
            "RecoveryManager: cannot cancel"
        );
        _resetRecovery();
        emit RecoveryCancelled("cancelled by owner");
    }

    // --- Internal ---

    function _executeRecovery() internal {
        address newOwner = _recovery.proposedOwner;
        address newModule = _recovery.proposedModule;

        // Update owner
        address oldOwner = owner;
        owner = newOwner;

        // If new module was proposed, forward migration to MigrationManager
        if (newModule != address(0)) {
            // The MigrationManager would handle the actual module swap
            // This requires the RecoveryManager to be authorized by the parent account
        }

        emit RecoveryExecuted(newOwner, newModule);
        _resetRecovery();
    }

    function _resetRecovery() internal {
        _recoveryActive = false;
        _recovery.proposedOwner = address(0);
        _recovery.proposedModule = address(0);
        _recovery.timestamp = 0;
        _recovery.approvals = 0;
    }

    function _addGuardian(address guardian) internal {
        require(guardian != address(0), "RecoveryManager: invalid address");
        require(guardian != owner, "RecoveryManager: owner cannot be guardian");
        require(!isGuardian[guardian], "RecoveryManager: already guardian");
        require(guardians.length < MAX_GUARDIANS, "RecoveryManager: max guardians");

        isGuardian[guardian] = true;
        guardians.push(guardian);
        emit GuardianAdded(guardian);
    }
}

/// @notice Minimal interface for MigrationManager.
interface MigrationManagerLike {
    function activeModule() external view returns (ISignatureModule);
}

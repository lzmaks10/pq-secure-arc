// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title PrivacyManager
 * @notice Stealth-address privacy layer for PQAccount system (ERC-5564 inspired)
 * 
 * Implements optional privacy via:
 *   1. Stealth key registry — each account registers a secp256k1 public key
 *   2. Encrypted on-chain events — the actual recipient + amount are encrypted
 *   3. Off-chain ECDH decryption — only the intended recipient can decrypt
 * 
 * This breaks the on-chain link between sender and recipient.
 * Encryption/decryption happens client-side in the DApp.
 */
contract PrivacyManager {

    // ──────────────────── State ────────────────────

    /// @notice Registered stealth public keys (64 bytes uncompressed secp256k1 pubkey: x || y)
    mapping(address => bytes) public stealthKeys;

    /// @notice Whether an account has opted into privacy mode
    mapping(address => bool) public privacyOptIn;

    /// @notice Counter for private transactions (for unique IDs)
    uint256 public privateTxCount;

    /// @notice Stealth address → recipient address mapping (for detection)
    mapping(bytes32 => bool) public stealthAddressUsed;

    // ──────────────────── Events ────────────────────

    /// @notice Emitted when an account registers/updates their stealth key
    event StealthKeyRegistered(
        address indexed account,
        bytes publicKey,
        uint256 timestamp
    );

    /// @notice Emitted when an account toggles privacy opt-in
    event PrivacyOptToggled(
        address indexed account,
        bool enabled,
        uint256 timestamp
    );

    /// @notice Emitted for a private transaction
    /// @param stealthId keccak256(ephemeralPubKey) — unique identifier for scanning
    /// @param sender The sender's address
    /// @param ephemeralPubKey Ephemeral public key (r * G) for ECDH key agreement
    /// @param encryptedCiphertext AES-encrypted payload: [recipient, amount, message]
    /// @param nonce Unique nonce to prevent replay
    event PrivateTransaction(
        bytes32 indexed stealthId,
        address indexed sender,
        bytes ephemeralPubKey,
        bytes encryptedCiphertext,
        uint256 nonce,
        uint256 timestamp
    );

    /// @notice Emitted when a recipient acknowledges receiving a private transaction
    event PrivateTxAcknowledged(
        bytes32 indexed stealthId,
        address indexed recipient,
        uint256 timestamp
    );

    // ──────────────────── Modifiers ────────────────────

    modifier onlyRegistered() {
        require(stealthKeys[msg.sender].length == 64, "Privacy: register stealth key first");
        _;
    }

    // ──────────────────── Core Functions ────────────────────

    /**
     * @notice Register or update your stealth public key (64 bytes uncompressed)
     * @param _publicKey secp256k1 uncompressed public key (x || y, no 0x04 prefix)
     */
    function registerStealthKey(bytes calldata _publicKey) external {
        require(_publicKey.length == 64, "Privacy: key must be 64 bytes (x||y)");
        // Store without 0x04 prefix — saves gas
        stealthKeys[msg.sender] = _publicKey;
        emit StealthKeyRegistered(msg.sender, _publicKey, block.timestamp);
    }

    /**
     * @notice Toggle privacy opt-in status
     */
    function togglePrivacyOptIn() external {
        privacyOptIn[msg.sender] = !privacyOptIn[msg.sender];
        emit PrivacyOptToggled(msg.sender, privacyOptIn[msg.sender], block.timestamp);
    }

    /**
     * @notice Send a private transaction via stealth address
     * @param _ephemeralPubKey Ephemeral public key (R = r * G, 64 bytes uncompressed)
     * @param _encryptedCiphertext AES-encrypted data: [recipient, amount, message]
     * @param _recipientHint Optional: keccak256 of recipient address for faster scanning
     *        Set to bytes32(0) for maximum privacy (slower scanning)
     */
    function sendPrivate(
        bytes calldata _ephemeralPubKey,
        bytes calldata _encryptedCiphertext,
        bytes32 _recipientHint
    ) external onlyRegistered {
        require(_ephemeralPubKey.length == 64, "Privacy: ephemeral key must be 64 bytes");

        privateTxCount++;
        bytes32 stealthId = keccak256(_ephemeralPubKey);
        require(!stealthAddressUsed[stealthId], "Privacy: stealth ID already used");

        emit PrivateTransaction(
            stealthId,
            msg.sender,
            _ephemeralPubKey,
            _encryptedCiphertext,
            privateTxCount,
            block.timestamp
        );

        // If hint provided, also emit indexed by recipient hint for faster scanning
        if (_recipientHint != bytes32(0)) {
            emit PrivateTransaction(
                _recipientHint,
                msg.sender,
                _ephemeralPubKey,
                _encryptedCiphertext,
                privateTxCount,
                block.timestamp
            );
        }
    }

    /**
     * @notice Acknowledge a private transaction (marks as seen by recipient)
     * @param _stealthId The stealth ID to acknowledge
     */
    function acknowledgePrivateTx(bytes32 _stealthId) external {
        // We don't enforce that only the real recipient can acknowledge,
        // but the event lets off-chain scanners filter
        emit PrivateTxAcknowledged(_stealthId, msg.sender, block.timestamp);
    }

    /**
     * @notice Remove your stealth key and privacy opt-in
     */
    function unregisterPrivacy() external {
        delete stealthKeys[msg.sender];
        privacyOptIn[msg.sender] = false;
        emit StealthKeyRegistered(msg.sender, hex"", block.timestamp);
        emit PrivacyOptToggled(msg.sender, false, block.timestamp);
    }

    // ──────────────────── View Functions ────────────────────

    /**
     * @notice Check if an address has privacy enabled
     */
    function hasPrivacy(address _account) external view returns (bool) {
        return stealthKeys[_account].length == 64 && privacyOptIn[_account];
    }

    /**
     * @notice Get the stealth key for an account (returns raw bytes)
     */
    function getStealthKey(address _account) external view returns (bytes memory) {
        return stealthKeys[_account];
    }
}

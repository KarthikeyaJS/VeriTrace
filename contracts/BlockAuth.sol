// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title BlockAuth — product registration and custody tracking for VeriTrace
/// @notice Stores only a product fingerprint (SHA-256 of identity fields) and the
///         custody chain. No personal data is stored on-chain.
contract BlockAuth {
    enum Role { None, Admin, Manufacturer, Supplier, Retailer }
    enum Stage { None, Manufactured, AtSupplier, AtRetailer, Sold }
    enum EventType { Registered, TransferInitiated, Received, TransferCancelled, Sold }

    struct Product {
        string productId;
        bytes32 productHash;
        address manufacturer;
        uint64 registeredAt;
        address currentHolder;
        address pendingRecipient;
        Stage stage;
        bool exists;
    }

    struct Handoff {
        address from;
        address to;
        uint64 timestamp;
        EventType eventType;
        Stage stageAfter;
    }

    mapping(address => Role) public roles;
    mapping(bytes32 => Product) private products;
    mapping(bytes32 => Handoff[]) private histories;
    uint256 public productCount;

    // ---------------------------------------------------------------- errors
    error NotAdmin(address caller);
    error NotManufacturer(address caller);
    error ZeroAddress();
    error CannotChangeOwnRole();
    error EmptyProductId();
    error InvalidHash();
    error ProductAlreadyExists(string productId);
    error ProductNotFound(string productId);
    error NotCurrentHolder(address caller, address holder);
    error TransferAlreadyPending(address pendingRecipient);
    error NoPendingTransfer();
    error NotPendingRecipient(address caller, address pendingRecipient);
    error CannotTransferToSelf();
    error CallerRoleMismatch(Role expected, Role actual);
    error InvalidTransition(Stage stage, Role recipientRole);
    error NotRetailer(address caller);
    error ProductAlreadySold(string productId);

    // ---------------------------------------------------------------- events
    event RoleChanged(address indexed user, Role previousRole, Role newRole, address indexed changedBy);
    event ProductRegistered(bytes32 indexed key, string productId, bytes32 productHash, address indexed manufacturer);
    event TransferInitiated(bytes32 indexed key, string productId, address indexed from, address indexed to);
    event TransferReceived(bytes32 indexed key, string productId, address indexed from, address indexed to, Stage stage);
    event TransferCancelled(bytes32 indexed key, string productId, address indexed from, address indexed to);
    event ProductSold(bytes32 indexed key, string productId, address indexed retailer);

    modifier onlyAdmin() {
        if (roles[msg.sender] != Role.Admin) revert NotAdmin(msg.sender);
        _;
    }

    constructor() {
        roles[msg.sender] = Role.Admin;
        emit RoleChanged(msg.sender, Role.None, Role.Admin, msg.sender);
    }

    // ----------------------------------------------------------------- roles
    function setUserRole(address user, Role role) external onlyAdmin {
        if (user == address(0)) revert ZeroAddress();
        if (user == msg.sender) revert CannotChangeOwnRole();
        Role previous = roles[user];
        roles[user] = role;
        emit RoleChanged(user, previous, role, msg.sender);
    }

    // -------------------------------------------------------------- products
    function registerProduct(string calldata productId, bytes32 productHash) external {
        if (roles[msg.sender] != Role.Manufacturer) revert NotManufacturer(msg.sender);
        if (bytes(productId).length == 0) revert EmptyProductId();
        if (productHash == bytes32(0)) revert InvalidHash();
        bytes32 key = keyOf(productId);
        if (products[key].exists) revert ProductAlreadyExists(productId);

        products[key] = Product({
            productId: productId,
            productHash: productHash,
            manufacturer: msg.sender,
            registeredAt: uint64(block.timestamp),
            currentHolder: msg.sender,
            pendingRecipient: address(0),
            stage: Stage.Manufactured,
            exists: true
        });
        productCount++;
        _record(key, msg.sender, msg.sender, EventType.Registered, Stage.Manufactured);
        emit ProductRegistered(key, productId, productHash, msg.sender);
    }

    /// @notice Returns the product; `exists` is false for unknown IDs (never reverts).
    function getProduct(string calldata productId) external view returns (Product memory) {
        return products[keyOf(productId)];
    }

    function getHandoffHistory(string calldata productId) external view returns (Handoff[] memory) {
        return histories[keyOf(productId)];
    }

    // ------------------------------------------------------------- transfers
    function initiateTransfer(string calldata productId, address to) external {
        (bytes32 key, Product storage p) = _load(productId);
        if (msg.sender != p.currentHolder) revert NotCurrentHolder(msg.sender, p.currentHolder);
        if (p.pendingRecipient != address(0)) revert TransferAlreadyPending(p.pendingRecipient);
        if (to == address(0)) revert ZeroAddress();
        if (to == msg.sender) revert CannotTransferToSelf();

        Role callerRole = roles[msg.sender];
        Role toRole = roles[to];
        if (p.stage == Stage.Manufactured) {
            if (callerRole != Role.Manufacturer) revert CallerRoleMismatch(Role.Manufacturer, callerRole);
            if (toRole != Role.Supplier) revert InvalidTransition(p.stage, toRole);
        } else if (p.stage == Stage.AtSupplier) {
            if (callerRole != Role.Supplier) revert CallerRoleMismatch(Role.Supplier, callerRole);
            if (toRole != Role.Supplier && toRole != Role.Retailer) revert InvalidTransition(p.stage, toRole);
        } else {
            revert InvalidTransition(p.stage, toRole);
        }

        p.pendingRecipient = to;
        _record(key, msg.sender, to, EventType.TransferInitiated, p.stage);
        emit TransferInitiated(key, productId, msg.sender, to);
    }

    function confirmReceipt(string calldata productId) external {
        (bytes32 key, Product storage p) = _load(productId);
        if (p.pendingRecipient == address(0)) revert NoPendingTransfer();
        if (msg.sender != p.pendingRecipient) revert NotPendingRecipient(msg.sender, p.pendingRecipient);

        Role role = roles[msg.sender];
        Stage next;
        if (role == Role.Supplier) next = Stage.AtSupplier;
        else if (role == Role.Retailer) next = Stage.AtRetailer;
        else revert InvalidTransition(p.stage, role);

        address from = p.currentHolder;
        p.currentHolder = msg.sender;
        p.pendingRecipient = address(0);
        p.stage = next;
        _record(key, from, msg.sender, EventType.Received, next);
        emit TransferReceived(key, productId, from, msg.sender, next);
    }

    function cancelTransfer(string calldata productId) external {
        (bytes32 key, Product storage p) = _load(productId);
        if (msg.sender != p.currentHolder) revert NotCurrentHolder(msg.sender, p.currentHolder);
        address to = p.pendingRecipient;
        if (to == address(0)) revert NoPendingTransfer();

        p.pendingRecipient = address(0);
        _record(key, msg.sender, to, EventType.TransferCancelled, p.stage);
        emit TransferCancelled(key, productId, msg.sender, to);
    }

    function markSold(string calldata productId) external {
        (bytes32 key, Product storage p) = _load(productId);
        if (p.stage == Stage.Sold) revert ProductAlreadySold(productId);
        if (msg.sender != p.currentHolder) revert NotCurrentHolder(msg.sender, p.currentHolder);
        if (roles[msg.sender] != Role.Retailer) revert NotRetailer(msg.sender);
        if (p.stage != Stage.AtRetailer) revert InvalidTransition(p.stage, Role.None);

        p.stage = Stage.Sold;
        _record(key, msg.sender, address(0), EventType.Sold, Stage.Sold);
        emit ProductSold(key, productId, msg.sender);
    }

    // --------------------------------------------------------------- helpers
    function keyOf(string calldata productId) public pure returns (bytes32) {
        return keccak256(bytes(productId));
    }

    function _load(string calldata productId) private view returns (bytes32 key, Product storage p) {
        key = keyOf(productId);
        p = products[key];
        if (!p.exists) revert ProductNotFound(productId);
    }

    function _record(bytes32 key, address from, address to, EventType eventType, Stage stageAfter) private {
        histories[key].push(Handoff(from, to, uint64(block.timestamp), eventType, stageAfter));
    }
}

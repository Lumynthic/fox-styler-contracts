// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {ERC1155Supply} from "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import {ERC1155Pausable} from "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Pausable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IFoxStylerItems} from "./interfaces/IFoxStylerItems.sol";

/// @notice Stable ERC-1155 ownership layer for tokenized Fox Styler items.
/// @dev Game state stays off-chain. This contract owns item definitions, balances, transfer policy,
///      supply caps, metadata freeze state, and global claim replay protection.
contract FoxStylerItems is ERC1155, ERC1155Supply, ERC1155Pausable, AccessControl, IFoxStylerItems {
    bytes32 public constant ITEM_REGISTRAR_ROLE = keccak256("ITEM_REGISTRAR_ROLE");
    bytes32 public constant METADATA_ROLE = keccak256("METADATA_ROLE");
    bytes32 public constant CLAIMS_ROLE = keccak256("CLAIMS_ROLE");
    bytes32 public constant EXCHANGE_ROLE = keccak256("EXCHANGE_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    bytes4 private constant _ERC6551_ACCOUNT_INTERFACE_ID = 0x6faff5f1;

    error InvalidAdmin();
    error ItemAlreadyRegistered(uint256 itemId);
    error ItemNotRegistered(uint256 itemId);
    error ItemIsFrozen(uint256 itemId);
    error ItemNotClaimable(uint256 itemId);
    error ItemNotExchangeInput(uint256 itemId);
    error ItemNotExchangeOutput(uint256 itemId);
    error ClaimAlreadyConsumed(bytes32 claimId);
    error InvalidClaimId();
    error ZeroAmount();
    error SupplyCapExceeded(uint256 itemId, uint256 cap, uint256 attemptedSupply);
    error CapBelowCurrentSupply(uint256 itemId, uint256 currentSupply, uint256 requestedCap);
    error SupplyCapCanOnlyTighten(uint256 itemId, uint256 oldCap, uint256 requestedCap);
    error TransferPolicyLockedAfterMint(uint256 itemId, TransferPolicy currentPolicy, TransferPolicy requestedPolicy);
    error FoxBoundItem(uint256 itemId);
    error TokenBoundAccountOperatorApprovalDisabled(address account);

    mapping(uint256 itemId => ItemDefinition definition) private _definitions;
    mapping(uint256 itemId => string tokenURI) private _itemURIs;
    mapping(bytes32 claimId => bool consumed) public consumedClaimIds;

    event ItemRegistered(
        uint256 indexed itemId,
        string uri,
        TransferPolicy transferPolicy,
        bool claimable,
        bool exchangeInputEligible,
        bool exchangeOutputEligible,
        uint256 maxSupply
    );
    event ItemPolicyUpdated(
        uint256 indexed itemId,
        TransferPolicy transferPolicy,
        bool claimable,
        bool exchangeInputEligible,
        bool exchangeOutputEligible,
        uint256 maxSupply
    );
    event ItemURIUpdated(uint256 indexed itemId, string uri);
    event ItemFrozen(uint256 indexed itemId);
    event ClaimMinted(
        bytes32 indexed claimId, address indexed to, uint256 indexed itemId, uint256 amount, bytes32 provenanceHash
    );
    event ExchangeBurn(address indexed from, uint256 indexed itemId, uint256 amount);
    event ExchangeMint(address indexed to, uint256 indexed itemId, uint256 amount);

    constructor(address initialAdmin) ERC1155("") {
        if (initialAdmin == address(0)) revert InvalidAdmin();
        _grantRole(DEFAULT_ADMIN_ROLE, initialAdmin);
    }

    function itemDefinition(uint256 itemId) external view returns (ItemDefinition memory) {
        return _definitions[itemId];
    }

    function uri(uint256 itemId) public view override returns (string memory) {
        return _itemURIs[itemId];
    }

    function registerItem(
        uint256 itemId,
        string calldata tokenURI,
        TransferPolicy transferPolicy,
        bool claimable,
        bool exchangeInputEligible,
        bool exchangeOutputEligible,
        uint256 maxSupply
    ) external onlyRole(ITEM_REGISTRAR_ROLE) {
        if (_definitions[itemId].registered) revert ItemAlreadyRegistered(itemId);

        _definitions[itemId] = ItemDefinition({
            registered: true,
            claimable: claimable,
            exchangeInputEligible: exchangeInputEligible,
            exchangeOutputEligible: exchangeOutputEligible,
            frozen: false,
            transferPolicy: transferPolicy,
            maxSupply: maxSupply
        });
        _itemURIs[itemId] = tokenURI;

        emit ItemRegistered(
            itemId, tokenURI, transferPolicy, claimable, exchangeInputEligible, exchangeOutputEligible, maxSupply
        );
        if (bytes(tokenURI).length != 0) emit URI(tokenURI, itemId);
    }

    /// @notice Update mutable item policy.
    /// @dev Once an item has supply, transfer policy cannot change and any existing finite supply cap
    ///      can only stay the same or become tighter. This prevents post-mint rug-style policy changes.
    function updateItemPolicy(
        uint256 itemId,
        TransferPolicy transferPolicy,
        bool claimable,
        bool exchangeInputEligible,
        bool exchangeOutputEligible,
        uint256 maxSupply
    ) external onlyRole(ITEM_REGISTRAR_ROLE) {
        ItemDefinition storage definition = _requireMutable(itemId);
        uint256 currentSupply = totalSupply(itemId);

        if (currentSupply != 0 && transferPolicy != definition.transferPolicy) {
            revert TransferPolicyLockedAfterMint(itemId, definition.transferPolicy, transferPolicy);
        }

        if (maxSupply != 0 && maxSupply < currentSupply) {
            revert CapBelowCurrentSupply(itemId, currentSupply, maxSupply);
        }

        if (currentSupply != 0 && definition.maxSupply != 0 && (maxSupply == 0 || maxSupply > definition.maxSupply)) {
            revert SupplyCapCanOnlyTighten(itemId, definition.maxSupply, maxSupply);
        }

        definition.transferPolicy = transferPolicy;
        definition.claimable = claimable;
        definition.exchangeInputEligible = exchangeInputEligible;
        definition.exchangeOutputEligible = exchangeOutputEligible;
        definition.maxSupply = maxSupply;

        emit ItemPolicyUpdated(
            itemId, transferPolicy, claimable, exchangeInputEligible, exchangeOutputEligible, maxSupply
        );
    }

    function setItemURI(uint256 itemId, string calldata tokenURI) external onlyRole(METADATA_ROLE) {
        _requireMutable(itemId);
        _itemURIs[itemId] = tokenURI;
        emit ItemURIUpdated(itemId, tokenURI);
        emit URI(tokenURI, itemId);
    }

    /// @notice Permanently freezes metadata AND the on-chain policy for an item definition.
    function freezeItem(uint256 itemId) external onlyRole(ITEM_REGISTRAR_ROLE) {
        ItemDefinition storage definition = _requireDefinition(itemId);
        if (definition.frozen) revert ItemIsFrozen(itemId);
        definition.frozen = true;
        emit ItemFrozen(itemId);
    }

    function mintClaim(address to, uint256 itemId, uint256 amount, bytes32 claimId, bytes32 provenanceHash)
        external
        onlyRole(CLAIMS_ROLE)
    {
        if (amount == 0) revert ZeroAmount();
        if (claimId == bytes32(0)) revert InvalidClaimId();

        ItemDefinition storage definition = _requireDefinition(itemId);
        if (!definition.claimable) revert ItemNotClaimable(itemId);
        if (consumedClaimIds[claimId]) revert ClaimAlreadyConsumed(claimId);

        _enforceCap(itemId, amount, definition.maxSupply);
        consumedClaimIds[claimId] = true;
        _mint(to, itemId, amount, "");

        emit ClaimMinted(claimId, to, itemId, amount, provenanceHash);
    }

    function exchangeBurn(address from, uint256 itemId, uint256 amount) external onlyRole(EXCHANGE_ROLE) {
        if (amount == 0) revert ZeroAmount();
        ItemDefinition storage definition = _requireDefinition(itemId);
        if (!definition.exchangeInputEligible) revert ItemNotExchangeInput(itemId);

        _burn(from, itemId, amount);
        emit ExchangeBurn(from, itemId, amount);
    }

    function exchangeMint(address to, uint256 itemId, uint256 amount) external onlyRole(EXCHANGE_ROLE) {
        if (amount == 0) revert ZeroAmount();
        ItemDefinition storage definition = _requireDefinition(itemId);
        if (!definition.exchangeOutputEligible) revert ItemNotExchangeOutput(itemId);

        _enforceCap(itemId, amount, definition.maxSupply);
        _mint(to, itemId, amount, "");
        emit ExchangeMint(to, itemId, amount);
    }

    /// @notice ERC-1155 operator approvals are disabled while Fox Styler items are held by an ERC-6551 account.
    /// @dev The Backpack address survives a parent-Fox sale, so ordinary persistent `setApprovalForAll` state would
    ///      otherwise remain live for the previous owner's operator after the Fox changes hands. A Fox TBA can still
    ///      transfer its own tradable items through `execute`; collectors can move items to a normal wallet before
    ///      using marketplace operator approvals.
    function setApprovalForAll(address operator, bool approved) public override {
        if (_isERC6551Account(msg.sender)) revert TokenBoundAccountOperatorApprovalDisabled(msg.sender);
        super.setApprovalForAll(operator, approved);
    }

    /// @dev Defensive override in case approval storage could ever be populated for a TBA through future changes.
    function isApprovedForAll(address account, address operator) public view override returns (bool) {
        if (_isERC6551Account(account)) return false;
        return super.isApprovedForAll(account, operator);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function _isERC6551Account(address account) internal view returns (bool) {
        if (account.code.length == 0) return false;

        (bool success, bytes memory data) =
            account.staticcall(abi.encodeCall(IERC165.supportsInterface, (_ERC6551_ACCOUNT_INTERFACE_ID)));
        return success && data.length >= 32 && abi.decode(data, (bool));
    }

    function _enforceCap(uint256 itemId, uint256 amount, uint256 maxSupply) internal view {
        if (maxSupply == 0) return;
        uint256 attemptedSupply = totalSupply(itemId) + amount;
        if (attemptedSupply > maxSupply) revert SupplyCapExceeded(itemId, maxSupply, attemptedSupply);
    }

    function _requireDefinition(uint256 itemId) internal view returns (ItemDefinition storage definition) {
        definition = _definitions[itemId];
        if (!definition.registered) revert ItemNotRegistered(itemId);
    }

    function _requireMutable(uint256 itemId) internal view returns (ItemDefinition storage definition) {
        definition = _requireDefinition(itemId);
        if (definition.frozen) revert ItemIsFrozen(itemId);
    }

    /// @dev Enforces Fox-bound policy on all non-mint/non-burn transfers.
    function _update(address from, address to, uint256[] memory ids, uint256[] memory values)
        internal
        override(ERC1155, ERC1155Supply, ERC1155Pausable)
    {
        if (from != address(0) && to != address(0)) {
            uint256 length = ids.length;
            for (uint256 i; i < length; ++i) {
                if (_definitions[ids[i]].transferPolicy == TransferPolicy.FoxBound) {
                    revert FoxBoundItem(ids[i]);
                }
            }
        }
        super._update(from, to, ids, values);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC1155, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}

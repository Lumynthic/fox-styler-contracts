// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

import {IERC6551Registry} from "./interfaces/IERC6551Registry.sol";
import {IFoxStylerItems} from "./interfaces/IFoxStylerItems.sol";

/// @notice Per-Fox Duplicate Exchange: one Fox must own every input copy, and the result returns to that Fox.
/// @dev Placement remains off-chain. A short-lived signed permit carries the minimum balance that must remain
///      after the burn, allowing the backend to protect the first copy AND currently placed quantity.
contract FoxExchange is AccessControl, EIP712, Pausable, ReentrancyGuard {
    bytes32 public constant RECIPE_MANAGER_ROLE = keccak256("RECIPE_MANAGER_ROLE");
    bytes32 public constant SIGNER_MANAGER_ROLE = keccak256("SIGNER_MANAGER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    bytes32 public constant PERMIT_TYPEHASH = keccak256(
        "ExchangePermit(bytes32 permitId,address expectedOwner,uint256 foxTokenId,uint256 recipeId,bytes32 recipeHash,uint256 minRemainingBalance,uint64 expiresAt)"
    );

    error InvalidAddress();
    error InvalidPermitId();
    error RecipeNotFound(uint256 recipeId);
    error RecipeDisabled(uint256 recipeId);
    error InvalidRecipe();
    error InvalidRecipeHash();
    error InvalidInputItem(uint256 itemId);
    error InvalidOutputItem(uint256 itemId);
    error PermitAlreadyUsed(bytes32 permitId);
    error PermitExpired(uint64 expiresAt);
    error InvalidExchangeSignature();
    error NotFoxOwner(address caller, address currentOwner);
    error OwnerChanged(address expectedOwner, address currentOwner);
    error InsufficientFoxBalance(uint256 have, uint256 need);
    error MinimumRemainingTooLow(uint256 supplied, uint256 required);
    error BackpackCreationFailed();

    struct Recipe {
        bool exists;
        bool enabled;
        uint256 inputItemId;
        uint256 inputAmount;
        uint256 retainedAmount;
        uint256 outputItemId;
        uint256 outputAmount;
    }

    struct ExchangePermit {
        bytes32 permitId;
        address expectedOwner;
        uint256 foxTokenId;
        uint256 recipeId;
        bytes32 recipeHash;
        uint256 minRemainingBalance;
        uint64 expiresAt;
    }

    IFoxStylerItems public immutable items;
    IERC6551Registry public immutable registry;
    address public immutable accountImplementation;
    address public immutable foxNft;
    bytes32 public immutable backpackSalt;

    address public exchangeSigner;

    mapping(uint256 recipeId => Recipe recipe) public recipes;
    mapping(uint256 recipeId => uint64 version) public recipeVersions;
    mapping(bytes32 permitId => bool used) public usedPermitIds;

    event ExchangeSignerUpdated(address indexed oldSigner, address indexed newSigner);
    event RecipeConfigured(
        uint256 indexed recipeId,
        bytes32 indexed recipeHash,
        uint64 version,
        bool enabled,
        uint256 inputItemId,
        uint256 inputAmount,
        uint256 retainedAmount,
        uint256 outputItemId,
        uint256 outputAmount
    );
    event RecipeEnabled(uint256 indexed recipeId, bool enabled, uint64 version, bytes32 recipeHash);
    event ExchangeCompleted(
        bytes32 indexed permitId,
        uint256 indexed foxTokenId,
        uint256 indexed recipeId,
        address owner,
        address backpack,
        uint256 inputItemId,
        uint256 inputAmount,
        uint256 outputItemId,
        uint256 outputAmount
    );

    constructor(
        address initialAdmin,
        address initialExchangeSigner,
        address items_,
        address registry_,
        address accountImplementation_,
        address foxNft_,
        bytes32 backpackSalt_
    ) EIP712("FoxExchange", "2") {
        if (
            initialAdmin == address(0) || initialExchangeSigner == address(0) || items_ == address(0)
                || registry_ == address(0) || accountImplementation_ == address(0) || foxNft_ == address(0)
        ) revert InvalidAddress();

        items = IFoxStylerItems(items_);
        registry = IERC6551Registry(registry_);
        accountImplementation = accountImplementation_;
        foxNft = foxNft_;
        backpackSalt = backpackSalt_;
        exchangeSigner = initialExchangeSigner;

        _grantRole(DEFAULT_ADMIN_ROLE, initialAdmin);
        _grantRole(RECIPE_MANAGER_ROLE, initialAdmin);
        _grantRole(SIGNER_MANAGER_ROLE, initialAdmin);
        _grantRole(PAUSER_ROLE, initialAdmin);
    }

    function accountFor(uint256 foxTokenId) public view returns (address) {
        return registry.account(accountImplementation, backpackSalt, block.chainid, foxNft, foxTokenId);
    }

    function getRecipe(uint256 recipeId) external view returns (Recipe memory) {
        return recipes[recipeId];
    }

    function recipeHash(uint256 recipeId) public view returns (bytes32) {
        Recipe memory recipe = recipes[recipeId];
        if (!recipe.exists) return bytes32(0);
        return _recipeHash(recipeId, recipe, recipeVersions[recipeId]);
    }

    function _recipeHash(uint256 recipeId, Recipe memory recipe, uint64 version) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                recipeId,
                version,
                recipe.inputItemId,
                recipe.inputAmount,
                recipe.retainedAmount,
                recipe.outputItemId,
                recipe.outputAmount
            )
        );
    }

    function hashPermit(ExchangePermit calldata p) public view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                PERMIT_TYPEHASH,
                p.permitId,
                p.expectedOwner,
                p.foxTokenId,
                p.recipeId,
                p.recipeHash,
                p.minRemainingBalance,
                p.expiresAt
            )
        );
        return _hashTypedDataV4(structHash);
    }

    /// @notice Create or update a recipe. Exact duplicate costs can be configured later without changing Items.
    /// @dev Input/output eligibility is checked at configuration time and again by the Items contract at execution.
    ///      Recipe hash changes whenever recipe economics/output changes, invalidating old signed permits.
    function configureRecipe(uint256 recipeId, Recipe calldata recipe) external onlyRole(RECIPE_MANAGER_ROLE) {
        if (
            recipe.inputAmount == 0 || recipe.retainedAmount == 0 || recipe.outputAmount == 0
                || recipe.inputItemId == recipe.outputItemId
        ) revert InvalidRecipe();

        IFoxStylerItems.ItemDefinition memory inputDefinition = items.itemDefinition(recipe.inputItemId);
        if (!inputDefinition.registered || !inputDefinition.exchangeInputEligible) {
            revert InvalidInputItem(recipe.inputItemId);
        }

        IFoxStylerItems.ItemDefinition memory outputDefinition = items.itemDefinition(recipe.outputItemId);
        if (!outputDefinition.registered || !outputDefinition.exchangeOutputEligible) {
            revert InvalidOutputItem(recipe.outputItemId);
        }

        Recipe memory configured = Recipe({
            exists: true,
            enabled: recipe.enabled,
            inputItemId: recipe.inputItemId,
            inputAmount: recipe.inputAmount,
            retainedAmount: recipe.retainedAmount,
            outputItemId: recipe.outputItemId,
            outputAmount: recipe.outputAmount
        });
        recipes[recipeId] = configured;
        uint64 version = ++recipeVersions[recipeId];
        bytes32 configuredHash = _recipeHash(recipeId, configured, version);

        emit RecipeConfigured(
            recipeId,
            configuredHash,
            version,
            configured.enabled,
            configured.inputItemId,
            configured.inputAmount,
            configured.retainedAmount,
            configured.outputItemId,
            configured.outputAmount
        );
    }

    function setRecipeEnabled(uint256 recipeId, bool enabled) external onlyRole(RECIPE_MANAGER_ROLE) {
        Recipe storage recipe = recipes[recipeId];
        if (!recipe.exists) revert RecipeNotFound(recipeId);
        if (recipe.enabled == enabled) return;
        recipe.enabled = enabled;
        uint64 version = ++recipeVersions[recipeId];
        emit RecipeEnabled(recipeId, enabled, version, _recipeHash(recipeId, recipe, version));
    }

    function setExchangeSigner(address newSigner) external onlyRole(SIGNER_MANAGER_ROLE) {
        if (newSigner == address(0)) revert InvalidAddress();
        address oldSigner = exchangeSigner;
        exchangeSigner = newSigner;
        emit ExchangeSignerUpdated(oldSigner, newSigner);
    }

    /// @notice Exchange duplicate copies owned by ONE Fox for an output owned by that SAME Fox.
    /// @dev Permit is bound to the Fox owner who requested it. A Fox transfer invalidates an outstanding permit.
    function exchange(ExchangePermit calldata p, bytes calldata signature)
        external
        whenNotPaused
        nonReentrant
        returns (address backpack)
    {
        if (p.permitId == bytes32(0)) revert InvalidPermitId();
        if (usedPermitIds[p.permitId]) revert PermitAlreadyUsed(p.permitId);
        if (p.expiresAt != 0 && block.timestamp > p.expiresAt) revert PermitExpired(p.expiresAt);

        Recipe memory recipe = recipes[p.recipeId];
        if (!recipe.exists) revert RecipeNotFound(p.recipeId);
        if (!recipe.enabled) revert RecipeDisabled(p.recipeId);

        bytes32 currentRecipeHash = recipeHash(p.recipeId);
        if (p.recipeHash != currentRecipeHash) revert InvalidRecipeHash();
        if (p.minRemainingBalance < recipe.retainedAmount) {
            revert MinimumRemainingTooLow(p.minRemainingBalance, recipe.retainedAmount);
        }

        address currentOwner = IERC721(foxNft).ownerOf(p.foxTokenId);
        if (p.expectedOwner != currentOwner) revert OwnerChanged(p.expectedOwner, currentOwner);
        if (msg.sender != currentOwner) revert NotFoxOwner(msg.sender, currentOwner);

        if (!SignatureChecker.isValidSignatureNow(exchangeSigner, hashPermit(p), signature)) {
            revert InvalidExchangeSignature();
        }

        backpack = registry.createAccount(accountImplementation, backpackSalt, block.chainid, foxNft, p.foxTokenId);
        if (backpack.code.length == 0) revert BackpackCreationFailed();

        uint256 balance = IERC1155(address(items)).balanceOf(backpack, recipe.inputItemId);
        uint256 requiredBalance = recipe.inputAmount + p.minRemainingBalance;
        if (balance < requiredBalance) revert InsufficientFoxBalance(balance, requiredBalance);

        // Mark first. If either token operation reverts, the entire transaction including this flag reverts.
        usedPermitIds[p.permitId] = true;
        items.exchangeBurn(backpack, recipe.inputItemId, recipe.inputAmount);
        items.exchangeMint(backpack, recipe.outputItemId, recipe.outputAmount);

        emit ExchangeCompleted(
            p.permitId,
            p.foxTokenId,
            p.recipeId,
            currentOwner,
            backpack,
            recipe.inputItemId,
            recipe.inputAmount,
            recipe.outputItemId,
            recipe.outputAmount
        );
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }
}

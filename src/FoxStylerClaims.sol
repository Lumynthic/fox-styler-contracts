// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {IERC6551Registry} from "./interfaces/IERC6551Registry.sol";
import {IFoxStylerItems} from "./interfaces/IFoxStylerItems.sol";

/// @notice Converts Fox-earned off-chain item awards into ERC-1155 items in that SAME Fox's Backpack.
/// @dev Anyone may relay a valid claim, enabling gas sponsorship. Destination is never caller-controlled.
contract FoxStylerClaims is AccessControl, EIP712, Pausable, ReentrancyGuard {
    bytes32 public constant SIGNER_MANAGER_ROLE = keccak256("SIGNER_MANAGER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    bytes32 public constant CLAIM_TYPEHASH = keccak256(
        "Claim(bytes32 claimId,uint256 foxTokenId,uint256 itemId,uint256 amount,uint8 sourceType,bytes32 sourceReferenceHash,uint64 expiresAt)"
    );

    error InvalidAddress();
    error InvalidClaimId();
    error ZeroAmount();
    error ClaimExpired(uint64 expiresAt);
    error InvalidRewardSignature();
    error BackpackCreationFailed();
    error ArrayLengthMismatch();

    struct Claim {
        bytes32 claimId;
        uint256 foxTokenId;
        uint256 itemId;
        uint256 amount;
        uint8 sourceType;
        bytes32 sourceReferenceHash;
        uint64 expiresAt;
    }

    IFoxStylerItems public immutable items;
    IERC6551Registry public immutable registry;
    address public immutable accountImplementation;
    address public immutable foxNft;
    bytes32 public immutable backpackSalt;

    address public rewardSigner;

    event RewardSignerUpdated(address indexed oldSigner, address indexed newSigner);
    event ItemClaimed(
        bytes32 indexed claimId,
        uint256 indexed foxTokenId,
        address indexed backpack,
        uint256 itemId,
        uint256 amount,
        uint8 sourceType,
        bytes32 sourceReferenceHash
    );

    constructor(
        address initialAdmin,
        address initialRewardSigner,
        address items_,
        address registry_,
        address accountImplementation_,
        address foxNft_,
        bytes32 backpackSalt_
    ) EIP712("FoxStylerClaims", "1") {
        if (
            initialAdmin == address(0) || initialRewardSigner == address(0) || items_ == address(0)
                || registry_ == address(0) || accountImplementation_ == address(0) || foxNft_ == address(0)
        ) revert InvalidAddress();

        items = IFoxStylerItems(items_);
        registry = IERC6551Registry(registry_);
        accountImplementation = accountImplementation_;
        foxNft = foxNft_;
        backpackSalt = backpackSalt_;
        rewardSigner = initialRewardSigner;

        _grantRole(DEFAULT_ADMIN_ROLE, initialAdmin);
        _grantRole(SIGNER_MANAGER_ROLE, initialAdmin);
        _grantRole(PAUSER_ROLE, initialAdmin);
    }

    function accountFor(uint256 foxTokenId) public view returns (address) {
        return registry.account(accountImplementation, backpackSalt, block.chainid, foxNft, foxTokenId);
    }

    function hashClaim(Claim calldata c) public view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                CLAIM_TYPEHASH,
                c.claimId,
                c.foxTokenId,
                c.itemId,
                c.amount,
                c.sourceType,
                c.sourceReferenceHash,
                c.expiresAt
            )
        );
        return _hashTypedDataV4(structHash);
    }

    /// @notice Claim an earned item into the bound Fox's Backpack.
    /// @dev Caller does not need to own the Fox; this intentionally permits a sponsored relayer.
    function claim(Claim calldata c, bytes calldata signature) external whenNotPaused nonReentrant returns (address) {
        return _claim(c, signature);
    }

    function claimBatch(Claim[] calldata claims, bytes[] calldata signatures)
        external
        whenNotPaused
        nonReentrant
        returns (address[] memory backpacks)
    {
        uint256 length = claims.length;
        if (length != signatures.length) revert ArrayLengthMismatch();
        backpacks = new address[](length);
        for (uint256 i; i < length; ++i) {
            backpacks[i] = _claim(claims[i], signatures[i]);
        }
    }

    function setRewardSigner(address newSigner) external onlyRole(SIGNER_MANAGER_ROLE) {
        if (newSigner == address(0)) revert InvalidAddress();
        address oldSigner = rewardSigner;
        rewardSigner = newSigner;
        emit RewardSignerUpdated(oldSigner, newSigner);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function _claim(Claim calldata c, bytes calldata signature) internal returns (address backpack) {
        if (c.claimId == bytes32(0)) revert InvalidClaimId();
        if (c.amount == 0) revert ZeroAmount();
        if (c.expiresAt != 0 && block.timestamp > c.expiresAt) revert ClaimExpired(c.expiresAt);

        bytes32 digest = hashClaim(c);
        if (!SignatureChecker.isValidSignatureNow(rewardSigner, digest, signature)) {
            revert InvalidRewardSignature();
        }

        // Existence check only. The reward is Fox-owned, so it remains claimable after a sale
        // and always resolves to the canonical Backpack for this tokenId.
        IERC721(foxNft).ownerOf(c.foxTokenId);

        backpack = registry.createAccount(accountImplementation, backpackSalt, block.chainid, foxNft, c.foxTokenId);
        if (backpack.code.length == 0) revert BackpackCreationFailed();

        bytes32 provenanceHash = keccak256(abi.encode(c.sourceType, c.sourceReferenceHash, foxNft, c.foxTokenId));
        items.mintClaim(backpack, c.itemId, c.amount, c.claimId, provenanceHash);

        emit ItemClaimed(c.claimId, c.foxTokenId, backpack, c.itemId, c.amount, c.sourceType, c.sourceReferenceHash);
    }
}

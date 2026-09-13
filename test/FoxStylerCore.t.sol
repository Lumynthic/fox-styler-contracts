// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {ERC6551Registry} from "erc6551/ERC6551Registry.sol";

import {FoxStylerAccount} from "../src/FoxStylerAccount.sol";
import {FoxStylerItems} from "../src/FoxStylerItems.sol";
import {FoxStylerClaims} from "../src/FoxStylerClaims.sol";
import {FoxExchange} from "../src/FoxExchange.sol";
import {IFoxStylerItems} from "../src/interfaces/IFoxStylerItems.sol";
import {MockFox} from "./mocks/MockFox.sol";

contract FoxStylerCoreTest is Test {
    uint256 internal constant FOX_A = 101;
    uint256 internal constant FOX_B = 202;

    uint256 internal constant BOWL = 1001;
    uint256 internal constant LIMITED_ITEM = 1002;
    uint256 internal constant NON_OUTPUT_ITEM = 1003;
    uint256 internal constant EXCHANGE_BOWL = 5001;
    uint256 internal constant CAPPED_EXCHANGE_BOWL = 5002;
    uint256 internal constant FOX_BOUND_RELIC = 9001;

    uint256 internal rewardSignerPk = 0xA11CE;
    uint256 internal exchangeSignerPk = 0xB0B;
    uint256 internal wrongSignerPk = 0xBAD;

    address internal rewardSigner;
    address internal exchangeSigner;
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);
    address internal relayer = address(0xCAFE);
    address internal marketplaceOperator = address(0xBEEF);

    bytes32 internal constant SALT = keccak256("FOX_STYLER_BACKPACK_V1");

    MockFox internal fox;
    ERC6551Registry internal registry;
    FoxStylerAccount internal accountImplementation;
    FoxStylerItems internal items;
    FoxStylerClaims internal claims;
    FoxExchange internal exchange;

    function setUp() public {
        rewardSigner = vm.addr(rewardSignerPk);
        exchangeSigner = vm.addr(exchangeSignerPk);

        fox = new MockFox();
        registry = new ERC6551Registry();
        accountImplementation = new FoxStylerAccount();
        items = new FoxStylerItems(address(this));

        claims = new FoxStylerClaims(
            address(this),
            rewardSigner,
            address(items),
            address(registry),
            address(accountImplementation),
            address(fox),
            SALT
        );

        exchange = new FoxExchange(
            address(this),
            exchangeSigner,
            address(items),
            address(registry),
            address(accountImplementation),
            address(fox),
            SALT
        );

        items.grantRole(items.ITEM_REGISTRAR_ROLE(), address(this));
        items.grantRole(items.METADATA_ROLE(), address(this));
        items.grantRole(items.CLAIMS_ROLE(), address(claims));
        items.grantRole(items.EXCHANGE_ROLE(), address(exchange));
        items.grantRole(items.PAUSER_ROLE(), address(this));

        _registerItem(BOWL, IFoxStylerItems.TransferPolicy.Transferable, true, true, false, 0);
        _registerItem(LIMITED_ITEM, IFoxStylerItems.TransferPolicy.Transferable, true, false, false, 100);
        _registerItem(NON_OUTPUT_ITEM, IFoxStylerItems.TransferPolicy.Transferable, true, false, false, 0);
        _registerItem(EXCHANGE_BOWL, IFoxStylerItems.TransferPolicy.Transferable, false, false, true, 0);
        _registerItem(CAPPED_EXCHANGE_BOWL, IFoxStylerItems.TransferPolicy.Transferable, false, false, true, 1);
        _registerItem(FOX_BOUND_RELIC, IFoxStylerItems.TransferPolicy.FoxBound, true, false, false, 0);

        fox.mint(alice, FOX_A);
        fox.mint(alice, FOX_B);
    }

    function testClaimCreatesBackpackAndMintsToFox() public {
        FoxStylerClaims.Claim memory c = _claimStruct(bytes32("claim-1"), FOX_A, BOWL, 2);
        bytes memory sig = _signClaim(c);

        vm.prank(relayer);
        address backpack = claims.claim(c, sig);

        assertGt(backpack.code.length, 0);
        assertEq(items.balanceOf(backpack, BOWL), 2);
        assertEq(FoxStylerAccount(payable(backpack)).owner(), alice);
    }

    function testClaimReplayFailsGloballyInItems() public {
        FoxStylerClaims.Claim memory c = _claimStruct(bytes32("claim-replay"), FOX_A, BOWL, 1);
        bytes memory sig = _signClaim(c);
        claims.claim(c, sig);

        vm.expectRevert(abi.encodeWithSelector(FoxStylerItems.ClaimAlreadyConsumed.selector, c.claimId));
        claims.claim(c, sig);
    }

    function testClaimReplayFailsAcrossReplacementClaimsModule() public {
        FoxStylerClaims.Claim memory c = _claimStruct(bytes32("global-replay"), FOX_A, BOWL, 1);
        claims.claim(c, _signClaim(c));

        FoxStylerClaims claimsV2 = new FoxStylerClaims(
            address(this),
            rewardSigner,
            address(items),
            address(registry),
            address(accountImplementation),
            address(fox),
            SALT
        );
        items.grantRole(items.CLAIMS_ROLE(), address(claimsV2));

        bytes32 digest = claimsV2.hashClaim(c);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(rewardSignerPk, digest);
        bytes memory sigV2 = abi.encodePacked(r, s, v);

        vm.expectRevert(abi.encodeWithSelector(FoxStylerItems.ClaimAlreadyConsumed.selector, c.claimId));
        claimsV2.claim(c, sigV2);
    }

    function testZeroClaimIdFails() public {
        FoxStylerClaims.Claim memory c = _claimStruct(bytes32(0), FOX_A, BOWL, 1);
        vm.expectRevert(FoxStylerClaims.InvalidClaimId.selector);
        claims.claim(c, _signClaim(c));
    }

    function testWrongClaimSignerFails() public {
        FoxStylerClaims.Claim memory c = _claimStruct(bytes32("bad-signature"), FOX_A, BOWL, 1);
        bytes32 digest = claims.hashClaim(c);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongSignerPk, digest);

        vm.expectRevert(FoxStylerClaims.InvalidRewardSignature.selector);
        claims.claim(c, abi.encodePacked(r, s, v));
    }

    function testExpiredClaimFails() public {
        FoxStylerClaims.Claim memory c = _claimStruct(bytes32("expired-claim"), FOX_A, BOWL, 1);
        bytes memory sig = _signClaim(c);
        vm.warp(uint256(c.expiresAt) + 1);

        vm.expectRevert(abi.encodeWithSelector(FoxStylerClaims.ClaimExpired.selector, c.expiresAt));
        claims.claim(c, sig);
    }

    function testSignedRewardStillFollowsFoxAfterSale() public {
        FoxStylerClaims.Claim memory c = _claimStruct(bytes32("claim-after-sale"), FOX_A, BOWL, 1);
        bytes memory sig = _signClaim(c);

        vm.prank(alice);
        fox.transferFrom(alice, bob, FOX_A);

        address backpack = claims.claim(c, sig);
        assertEq(items.balanceOf(backpack, BOWL), 1);
        assertEq(FoxStylerAccount(payable(backpack)).owner(), bob);
    }

    function testBackpackControlMovesWithFox() public {
        address backpack = _claimItemToFox(FOX_A, BOWL, 1, "claim-control");

        vm.prank(alice);
        FoxStylerAccount(payable(backpack)).execute(alice, 0, "", 0);

        vm.prank(alice);
        fox.transferFrom(alice, bob, FOX_A);

        vm.prank(alice);
        vm.expectRevert(FoxStylerAccount.InvalidSigner.selector);
        FoxStylerAccount(payable(backpack)).execute(alice, 0, "", 0);

        vm.prank(bob);
        FoxStylerAccount(payable(backpack)).execute(bob, 0, "", 0);
    }

    function testBackpackAdvertisesERC721Receiver() public {
        address backpack = registry.account(address(accountImplementation), SALT, block.chainid, address(fox), FOX_A);
        // The undeployed address cannot delegate yet, so query the implementation directly only for this interface test.
        assertTrue(accountImplementation.supportsInterface(type(IERC721Receiver).interfaceId));
        assertTrue(backpack != address(0));
    }

    function testFoxBoundItemCannotLeaveBackpack() public {
        address backpack = _claimItemToFox(FOX_A, FOX_BOUND_RELIC, 1, "bound");

        bytes memory transferData =
            abi.encodeWithSelector(IERC1155.safeTransferFrom.selector, backpack, alice, FOX_BOUND_RELIC, 1, bytes(""));

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(FoxStylerItems.FoxBoundItem.selector, FOX_BOUND_RELIC));
        FoxStylerAccount(payable(backpack)).execute(address(items), 0, transferData, 0);
    }

    function testBatchTransferContainingFoxBoundItemFails() public {
        address backpack = _claimItemToFox(FOX_A, BOWL, 1, "batch-bowl");
        _claimItemToFox(FOX_A, FOX_BOUND_RELIC, 1, "batch-relic");

        uint256[] memory ids = new uint256[](2);
        uint256[] memory amounts = new uint256[](2);
        ids[0] = BOWL;
        ids[1] = FOX_BOUND_RELIC;
        amounts[0] = 1;
        amounts[1] = 1;

        bytes memory transferData =
            abi.encodeWithSelector(IERC1155.safeBatchTransferFrom.selector, backpack, alice, ids, amounts, bytes(""));

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(FoxStylerItems.FoxBoundItem.selector, FOX_BOUND_RELIC));
        FoxStylerAccount(payable(backpack)).execute(address(items), 0, transferData, 0);

        assertEq(items.balanceOf(backpack, BOWL), 1);
        assertEq(items.balanceOf(backpack, FOX_BOUND_RELIC), 1);
    }

    function testTbaCannotCreatePersistentERC1155OperatorApproval() public {
        address backpack = _claimItemToFox(FOX_A, BOWL, 1, "tba-approval-block");

        bytes memory approvalData =
            abi.encodeWithSelector(IERC1155.setApprovalForAll.selector, marketplaceOperator, true);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(FoxStylerItems.TokenBoundAccountOperatorApprovalDisabled.selector, backpack)
        );
        FoxStylerAccount(payable(backpack)).execute(address(items), 0, approvalData, 0);

        assertFalse(items.isApprovedForAll(backpack, marketplaceOperator));
    }

    function testNormalWalletCanApproveOperatorAfterItemLeavesBackpack() public {
        address backpack = _claimItemToFox(FOX_A, BOWL, 1, "wallet-marketplace-approval");

        bytes memory transferData =
            abi.encodeWithSelector(IERC1155.safeTransferFrom.selector, backpack, alice, BOWL, 1, bytes(""));
        vm.prank(alice);
        FoxStylerAccount(payable(backpack)).execute(address(items), 0, transferData, 0);

        vm.prank(alice);
        items.setApprovalForAll(marketplaceOperator, true);
        assertTrue(items.isApprovedForAll(alice, marketplaceOperator));

        vm.prank(marketplaceOperator);
        items.safeTransferFrom(alice, bob, BOWL, 1, "");
        assertEq(items.balanceOf(bob, BOWL), 1);
    }

    function testParentFoxSafeTransferIntoOwnBackpackIsRejected() public {
        address backpack =
            registry.createAccount(address(accountImplementation), SALT, block.chainid, address(fox), FOX_A);

        vm.prank(alice);
        vm.expectRevert(FoxStylerAccount.ParentFoxCannotBeReceived.selector);
        fox.safeTransferFrom(alice, backpack, FOX_A);
    }

    function testTransferPolicyCannotChangeAfterFirstMint() public {
        _claimItemToFox(FOX_A, BOWL, 1, "policy-lock");

        vm.expectRevert(FoxStylerItems.TransferPolicyLockedAfterMint.selector);
        items.updateItemPolicy(BOWL, IFoxStylerItems.TransferPolicy.FoxBound, true, true, false, 0);
    }

    function testFiniteSupplyCapCannotIncreaseAfterMint() public {
        _claimItemToFox(FOX_A, LIMITED_ITEM, 10, "cap-lock");

        vm.expectRevert(FoxStylerItems.SupplyCapCanOnlyTighten.selector);
        items.updateItemPolicy(LIMITED_ITEM, IFoxStylerItems.TransferPolicy.Transferable, true, false, false, 120);
    }

    function testFiniteSupplyCapCanTightenAfterMint() public {
        _claimItemToFox(FOX_A, LIMITED_ITEM, 10, "cap-tighten");

        items.updateItemPolicy(LIMITED_ITEM, IFoxStylerItems.TransferPolicy.Transferable, true, false, false, 50);

        IFoxStylerItems.ItemDefinition memory definition = items.itemDefinition(LIMITED_ITEM);
        assertEq(definition.maxSupply, 50);
    }

    function testFrozenItemCannotChangeURIOrPolicy() public {
        items.freezeItem(BOWL);

        vm.expectRevert(abi.encodeWithSelector(FoxStylerItems.ItemIsFrozen.selector, BOWL));
        items.setItemURI(BOWL, "ipfs://replacement.json");

        vm.expectRevert(abi.encodeWithSelector(FoxStylerItems.ItemIsFrozen.selector, BOWL));
        items.updateItemPolicy(BOWL, IFoxStylerItems.TransferPolicy.Transferable, false, false, false, 0);
    }

    function testPausedItemsBlocksClaimMint() public {
        items.pause();
        FoxStylerClaims.Claim memory c = _claimStruct(bytes32("paused-items"), FOX_A, BOWL, 1);

        vm.expectRevert();
        claims.claim(c, _signClaim(c));
    }

    function testPausedClaimsBlocksClaim() public {
        claims.pause();
        FoxStylerClaims.Claim memory c = _claimStruct(bytes32("paused-claims"), FOX_A, BOWL, 1);

        vm.expectRevert();
        claims.claim(c, _signClaim(c));
    }

    function testExchangeConsumesDuplicatesAndKeepsOriginal() public {
        address backpack = _claimItemToFox(FOX_A, BOWL, 4, "claim-four");
        _configureRecipe(1, 3, 1, EXCHANGE_BOWL);

        FoxExchange.ExchangePermit memory p = _permit(bytes32("permit-1"), alice, FOX_A, 1, 1);

        vm.prank(alice);
        exchange.exchange(p, _signPermit(p));

        assertEq(items.balanceOf(backpack, BOWL), 1);
        assertEq(items.balanceOf(backpack, EXCHANGE_BOWL), 1);
    }

    function testDifferentFoxBalancesCannotPoolForExchange() public {
        _claimItemToFox(FOX_A, BOWL, 2, "claim-a-two");
        _claimItemToFox(FOX_B, BOWL, 2, "claim-b-two");

        _configureRecipe(2, 3, 1, EXCHANGE_BOWL);
        FoxExchange.ExchangePermit memory p = _permit(bytes32("permit-pool"), alice, FOX_A, 2, 1);

        vm.prank(alice);
        vm.expectRevert(FoxExchange.InsufficientFoxBalance.selector);
        exchange.exchange(p, _signPermit(p));
    }

    function testCollectorCanMoveTradableItemBetweenTheirFoxes() public {
        address backpackA = _claimItemToFox(FOX_A, BOWL, 2, "claim-transfer");
        address backpackB =
            registry.createAccount(address(accountImplementation), SALT, block.chainid, address(fox), FOX_B);

        bytes memory transferData =
            abi.encodeWithSelector(IERC1155.safeTransferFrom.selector, backpackA, backpackB, BOWL, 1, bytes(""));

        vm.prank(alice);
        FoxStylerAccount(payable(backpackA)).execute(address(items), 0, transferData, 0);

        assertEq(items.balanceOf(backpackA, BOWL), 1);
        assertEq(items.balanceOf(backpackB, BOWL), 1);
    }

    function testPermitMinimumRemainingProtectsPlacedQuantityAgainstBalanceChange() public {
        address backpack = _claimItemToFox(FOX_A, BOWL, 5, "claim-five");
        _configureRecipe(3, 3, 1, EXCHANGE_BOWL);

        // Backend signs while two copies must remain (e.g. one protected + one currently placed).
        FoxExchange.ExchangePermit memory p = _permit(bytes32("permit-reserved"), alice, FOX_A, 3, 2);
        bytes memory sig = _signPermit(p);

        // User removes one copy after permit issuance. Balance is now 4; permit requires 3 + 2 = 5.
        bytes memory transferData =
            abi.encodeWithSelector(IERC1155.safeTransferFrom.selector, backpack, alice, BOWL, 1, bytes(""));
        vm.prank(alice);
        FoxStylerAccount(payable(backpack)).execute(address(items), 0, transferData, 0);

        vm.prank(alice);
        vm.expectRevert(FoxExchange.InsufficientFoxBalance.selector);
        exchange.exchange(p, sig);
    }

    function testExchangePermitIsInvalidatedByFoxSale() public {
        _claimItemToFox(FOX_A, BOWL, 4, "sale-permit-balance");
        _configureRecipe(4, 3, 1, EXCHANGE_BOWL);

        FoxExchange.ExchangePermit memory p = _permit(bytes32("sale-permit"), alice, FOX_A, 4, 1);
        bytes memory sig = _signPermit(p);

        vm.prank(alice);
        fox.transferFrom(alice, bob, FOX_A);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(FoxExchange.OwnerChanged.selector, alice, bob));
        exchange.exchange(p, sig);
    }

    function testOldOwnerCannotUsePermitAfterSale() public {
        _claimItemToFox(FOX_A, BOWL, 4, "old-owner-balance");
        _configureRecipe(5, 3, 1, EXCHANGE_BOWL);

        FoxExchange.ExchangePermit memory p = _permit(bytes32("old-owner-permit"), alice, FOX_A, 5, 1);
        bytes memory sig = _signPermit(p);

        vm.prank(alice);
        fox.transferFrom(alice, bob, FOX_A);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(FoxExchange.OwnerChanged.selector, alice, bob));
        exchange.exchange(p, sig);
    }

    function testWrongExchangeSignerFails() public {
        _claimItemToFox(FOX_A, BOWL, 4, "wrong-exchange-signer-balance");
        _configureRecipe(6, 3, 1, EXCHANGE_BOWL);
        FoxExchange.ExchangePermit memory p = _permit(bytes32("wrong-ex-signer"), alice, FOX_A, 6, 1);

        bytes32 digest = exchange.hashPermit(p);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongSignerPk, digest);

        vm.prank(alice);
        vm.expectRevert(FoxExchange.InvalidExchangeSignature.selector);
        exchange.exchange(p, abi.encodePacked(r, s, v));
    }

    function testExpiredExchangePermitFails() public {
        _claimItemToFox(FOX_A, BOWL, 4, "expired-permit-balance");
        _configureRecipe(7, 3, 1, EXCHANGE_BOWL);
        FoxExchange.ExchangePermit memory p = _permit(bytes32("expired-permit"), alice, FOX_A, 7, 1);
        bytes memory sig = _signPermit(p);
        vm.warp(uint256(p.expiresAt) + 1);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(FoxExchange.PermitExpired.selector, p.expiresAt));
        exchange.exchange(p, sig);
    }

    function testRecipeChangeInvalidatesOutstandingPermit() public {
        _claimItemToFox(FOX_A, BOWL, 5, "recipe-change-balance");
        _configureRecipe(8, 3, 1, EXCHANGE_BOWL);
        FoxExchange.ExchangePermit memory p = _permit(bytes32("recipe-change"), alice, FOX_A, 8, 1);
        bytes memory sig = _signPermit(p);

        _configureRecipe(8, 2, 1, EXCHANGE_BOWL);

        vm.prank(alice);
        vm.expectRevert(FoxExchange.InvalidRecipeHash.selector);
        exchange.exchange(p, sig);
    }

    function testDisableReenableInvalidatesOutstandingPermit() public {
        _claimItemToFox(FOX_A, BOWL, 4, "toggle-recipe-balance");
        _configureRecipe(13, 3, 1, EXCHANGE_BOWL);

        FoxExchange.ExchangePermit memory p = _permit(bytes32("toggle-recipe"), alice, FOX_A, 13, 1);
        bytes memory sig = _signPermit(p);

        exchange.setRecipeEnabled(13, false);
        exchange.setRecipeEnabled(13, true);

        vm.prank(alice);
        vm.expectRevert(FoxExchange.InvalidRecipeHash.selector);
        exchange.exchange(p, sig);
    }

    function testRecipeRejectsItemNotApprovedAsExchangeOutput() public {
        FoxExchange.Recipe memory recipe = FoxExchange.Recipe({
            exists: true,
            enabled: true,
            inputItemId: BOWL,
            inputAmount: 3,
            retainedAmount: 1,
            outputItemId: NON_OUTPUT_ITEM,
            outputAmount: 1
        });

        vm.expectRevert(abi.encodeWithSelector(FoxExchange.InvalidOutputItem.selector, NON_OUTPUT_ITEM));
        exchange.configureRecipe(9, recipe);
    }

    function testMinimumRemainingCannotUndercutRecipeRetention() public {
        _claimItemToFox(FOX_A, BOWL, 5, "min-remaining-balance");
        _configureRecipe(10, 3, 2, EXCHANGE_BOWL);
        FoxExchange.ExchangePermit memory p = _permit(bytes32("min-remaining"), alice, FOX_A, 10, 1);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(FoxExchange.MinimumRemainingTooLow.selector, 1, 2));
        exchange.exchange(p, _signPermit(p));
    }

    function testExchangeIsAtomicWhenOutputSupplyCapIsReached() public {
        address backpackA = _claimItemToFox(FOX_A, BOWL, 4, "cap-exchange-a");
        address backpackB = _claimItemToFox(FOX_B, BOWL, 4, "cap-exchange-b");
        _configureRecipe(11, 3, 1, CAPPED_EXCHANGE_BOWL);

        FoxExchange.ExchangePermit memory first = _permit(bytes32("cap-first"), alice, FOX_A, 11, 1);
        vm.prank(alice);
        exchange.exchange(first, _signPermit(first));
        assertEq(items.balanceOf(backpackA, CAPPED_EXCHANGE_BOWL), 1);

        FoxExchange.ExchangePermit memory second = _permit(bytes32("cap-second"), alice, FOX_B, 11, 1);
        vm.prank(alice);
        vm.expectRevert(FoxStylerItems.SupplyCapExceeded.selector);
        exchange.exchange(second, _signPermit(second));

        // Burn must also roll back when output mint fails.
        assertEq(items.balanceOf(backpackB, BOWL), 4);
        assertEq(items.balanceOf(backpackB, CAPPED_EXCHANGE_BOWL), 0);
    }

    function testPausedExchangeBlocksExchange() public {
        _claimItemToFox(FOX_A, BOWL, 4, "paused-exchange-balance");
        _configureRecipe(12, 3, 1, EXCHANGE_BOWL);
        FoxExchange.ExchangePermit memory p = _permit(bytes32("paused-exchange"), alice, FOX_A, 12, 1);
        bytes memory sig = _signPermit(p);
        exchange.pause();

        vm.prank(alice);
        vm.expectRevert();
        exchange.exchange(p, sig);
    }

    function _registerItem(
        uint256 itemId,
        IFoxStylerItems.TransferPolicy transferPolicy,
        bool claimable,
        bool exchangeInputEligible,
        bool exchangeOutputEligible,
        uint256 maxSupply
    ) internal {
        items.registerItem(
            itemId,
            string.concat("ipfs://placeholder/", vm.toString(itemId), ".json"),
            transferPolicy,
            claimable,
            exchangeInputEligible,
            exchangeOutputEligible,
            maxSupply
        );
    }

    function _claimItemToFox(uint256 foxId, uint256 itemId, uint256 amount, string memory label)
        internal
        returns (address backpack)
    {
        FoxStylerClaims.Claim memory c = _claimStruct(keccak256(bytes(label)), foxId, itemId, amount);
        backpack = claims.claim(c, _signClaim(c));
    }

    function _claimStruct(bytes32 claimId, uint256 foxId, uint256 itemId, uint256 amount)
        internal
        view
        returns (FoxStylerClaims.Claim memory)
    {
        return FoxStylerClaims.Claim({
            claimId: claimId,
            foxTokenId: foxId,
            itemId: itemId,
            amount: amount,
            sourceType: 1,
            sourceReferenceHash: keccak256(abi.encode("test-source", foxId, itemId)),
            expiresAt: uint64(block.timestamp + 1 days)
        });
    }

    function _signClaim(FoxStylerClaims.Claim memory c) internal returns (bytes memory) {
        bytes32 digest = claims.hashClaim(c);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(rewardSignerPk, digest);
        return abi.encodePacked(r, s, v);
    }

    function _configureRecipe(uint256 recipeId, uint256 inputAmount, uint256 retainedAmount, uint256 outputItemId)
        internal
    {
        exchange.configureRecipe(
            recipeId,
            FoxExchange.Recipe({
                exists: true,
                enabled: true,
                inputItemId: BOWL,
                inputAmount: inputAmount,
                retainedAmount: retainedAmount,
                outputItemId: outputItemId,
                outputAmount: 1
            })
        );
    }

    function _permit(bytes32 permitId, address expectedOwner, uint256 foxId, uint256 recipeId, uint256 minRemaining)
        internal
        view
        returns (FoxExchange.ExchangePermit memory)
    {
        FoxExchange.Recipe memory recipe = exchange.getRecipe(recipeId);
        return FoxExchange.ExchangePermit({
            permitId: permitId,
            expectedOwner: expectedOwner,
            foxTokenId: foxId,
            recipeId: recipeId,
            recipeHash: exchange.recipeHash(recipeId),
            minRemainingBalance: minRemaining,
            expiresAt: uint64(block.timestamp + 10 minutes)
        });
    }

    function _signPermit(FoxExchange.ExchangePermit memory p) internal returns (bytes memory) {
        bytes32 digest = exchange.hashPermit(p);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(exchangeSignerPk, digest);
        return abi.encodePacked(r, s, v);
    }
}

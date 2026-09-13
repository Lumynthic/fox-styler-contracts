// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {ERC6551Registry} from "erc6551/ERC6551Registry.sol";

import {FoxStylerAccount} from "../src/FoxStylerAccount.sol";
import {FoxStylerItems} from "../src/FoxStylerItems.sol";
import {FoxStylerClaims} from "../src/FoxStylerClaims.sol";
import {FoxExchange} from "../src/FoxExchange.sol";
import {IFoxStylerItems} from "../src/interfaces/IFoxStylerItems.sol";
import {MockFox} from "./mocks/MockFox.sol";

/// @notice Property-oriented fuzz tests for the invariants that matter most to Fox Styler.
contract FoxStylerFuzzTest is Test {
    uint256 internal constant FOX_A = 101;
    uint256 internal constant FOX_B = 202;
    uint256 internal constant BOWL = 1001;
    uint256 internal constant EXCHANGE_BOWL = 5001;
    uint256 internal constant FOX_BOUND_RELIC = 9001;

    uint256 internal rewardSignerPk = 0xA11CE;
    uint256 internal exchangeSignerPk = 0xB0B;

    address internal rewardSigner;
    address internal exchangeSigner;
    address internal alice = address(0xA11CE);

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
        items.grantRole(items.CLAIMS_ROLE(), address(claims));
        items.grantRole(items.EXCHANGE_ROLE(), address(exchange));

        _registerItem(BOWL, IFoxStylerItems.TransferPolicy.Transferable, true, true, false, 0);
        _registerItem(EXCHANGE_BOWL, IFoxStylerItems.TransferPolicy.Transferable, false, false, true, 0);
        _registerItem(FOX_BOUND_RELIC, IFoxStylerItems.TransferPolicy.FoxBound, true, false, false, 0);

        fox.mint(alice, FOX_A);
        fox.mint(alice, FOX_B);
    }

    function testFuzzClaimMintsExactAmount(uint96 rawAmount, bytes32 seed) public {
        uint256 amount = bound(uint256(rawAmount), 1, 1_000_000);
        bytes32 claimId = _nonZeroId(seed, "claim-exact");
        address backpack = _claimToFox(FOX_A, BOWL, amount, claimId);

        assertEq(items.balanceOf(backpack, BOWL), amount);
        assertEq(FoxStylerAccount(payable(backpack)).owner(), alice);
    }

    function testFuzzClaimReplayNeverMintsTwice(uint96 rawAmount, bytes32 seed) public {
        uint256 amount = bound(uint256(rawAmount), 1, 1_000_000);
        bytes32 claimId = _nonZeroId(seed, "claim-replay");
        FoxStylerClaims.Claim memory c = _claim(claimId, FOX_A, BOWL, amount);
        bytes memory signature = _signClaim(c);

        address backpack = claims.claim(c, signature);
        vm.expectRevert(abi.encodeWithSelector(FoxStylerItems.ClaimAlreadyConsumed.selector, claimId));
        claims.claim(c, signature);

        assertEq(items.balanceOf(backpack, BOWL), amount);
    }

    function testFuzzFoxBoundItemCannotMoveIndependently(uint96 rawAmount, bytes32 seed) public {
        uint256 amount = bound(uint256(rawAmount), 1, 1_000);
        address backpack = _claimToFox(FOX_A, FOX_BOUND_RELIC, amount, _nonZeroId(seed, "bound"));

        bytes memory data = abi.encodeWithSelector(
            IERC1155.safeTransferFrom.selector,
            backpack,
            alice,
            FOX_BOUND_RELIC,
            amount,
            bytes("")
        );

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(FoxStylerItems.FoxBoundItem.selector, FOX_BOUND_RELIC));
        FoxStylerAccount(payable(backpack)).execute(address(items), 0, data, 0);

        assertEq(items.balanceOf(backpack, FOX_BOUND_RELIC), amount);
    }

    function testFuzzTradableItemCanMoveBetweenFoxes(uint96 rawAmount, bytes32 seed) public {
        uint256 amount = bound(uint256(rawAmount), 1, 1_000);
        address backpackA = _claimToFox(FOX_A, BOWL, amount, _nonZeroId(seed, "move"));
        address backpackB = registry.createAccount(
            address(accountImplementation), SALT, block.chainid, address(fox), FOX_B
        );

        bytes memory data = abi.encodeWithSelector(
            IERC1155.safeTransferFrom.selector,
            backpackA,
            backpackB,
            BOWL,
            amount,
            bytes("")
        );

        vm.prank(alice);
        FoxStylerAccount(payable(backpackA)).execute(address(items), 0, data, 0);

        assertEq(items.balanceOf(backpackA, BOWL), 0);
        assertEq(items.balanceOf(backpackB, BOWL), amount);
    }

    function testFuzzFormerOwnerCannotExecuteAfterFoxTransfer(address newOwner, bytes32 seed) public {
        vm.assume(newOwner != address(0));
        vm.assume(newOwner != alice);

        address backpack = _claimToFox(FOX_A, BOWL, 1, _nonZeroId(seed, "owner-transfer"));

        vm.prank(alice);
        fox.transferFrom(alice, newOwner, FOX_A);

        vm.prank(alice);
        vm.expectRevert(FoxStylerAccount.InvalidSigner.selector);
        FoxStylerAccount(payable(backpack)).execute(alice, 0, bytes(""), 0);

        assertEq(FoxStylerAccount(payable(backpack)).owner(), newOwner);
    }

    function testFuzzExchangeAlwaysRetainsSignedMinimum(
        uint8 rawInput,
        uint8 rawRetain,
        uint8 rawExtra,
        bytes32 seed
    ) public {
        uint256 inputAmount = bound(uint256(rawInput), 1, 20);
        uint256 retainedAmount = bound(uint256(rawRetain), 1, 20);
        uint256 extra = bound(uint256(rawExtra), 0, 20);
        uint256 startingBalance = inputAmount + retainedAmount + extra;

        address backpack = _claimToFox(FOX_A, BOWL, startingBalance, _nonZeroId(seed, "exchange-balance"));
        uint256 recipeId = uint256(keccak256(abi.encode(seed, inputAmount, retainedAmount))) | 1;

        exchange.configureRecipe(
            recipeId,
            FoxExchange.Recipe({
                exists: true,
                enabled: true,
                inputItemId: BOWL,
                inputAmount: inputAmount,
                retainedAmount: retainedAmount,
                outputItemId: EXCHANGE_BOWL,
                outputAmount: 1
            })
        );

        FoxExchange.ExchangePermit memory p = FoxExchange.ExchangePermit({
            permitId: _nonZeroId(seed, "exchange-permit"),
            expectedOwner: alice,
            foxTokenId: FOX_A,
            recipeId: recipeId,
            recipeHash: exchange.recipeHash(recipeId),
            minRemainingBalance: retainedAmount,
            expiresAt: uint64(block.timestamp + 10 minutes)
        });

        vm.prank(alice);
        exchange.exchange(p, _signPermit(p));

        assertEq(items.balanceOf(backpack, BOWL), retainedAmount + extra);
        assertGe(items.balanceOf(backpack, BOWL), retainedAmount);
        assertEq(items.balanceOf(backpack, EXCHANGE_BOWL), 1);
    }

    function testFuzzBalancesAcrossFoxesNeverPool(uint8 rawA, uint8 rawB, bytes32 seed) public {
        uint256 amountA = bound(uint256(rawA), 2, 20);
        uint256 amountB = bound(uint256(rawB), 2, 20);
        uint256 inputAmount = amountA > amountB ? amountA : amountB;

        _claimToFox(FOX_A, BOWL, amountA, _nonZeroId(seed, "pool-a"));
        _claimToFox(FOX_B, BOWL, amountB, _nonZeroId(seed, "pool-b"));

        uint256 recipeId = uint256(keccak256(abi.encode(seed, "pool-recipe"))) | 1;
        exchange.configureRecipe(
            recipeId,
            FoxExchange.Recipe({
                exists: true,
                enabled: true,
                inputItemId: BOWL,
                inputAmount: inputAmount,
                retainedAmount: 1,
                outputItemId: EXCHANGE_BOWL,
                outputAmount: 1
            })
        );

        FoxExchange.ExchangePermit memory p = FoxExchange.ExchangePermit({
            permitId: _nonZeroId(seed, "pool-permit"),
            expectedOwner: alice,
            foxTokenId: FOX_A,
            recipeId: recipeId,
            recipeHash: exchange.recipeHash(recipeId),
            minRemainingBalance: 1,
            expiresAt: uint64(block.timestamp + 10 minutes)
        });

        vm.prank(alice);
        vm.expectRevert(FoxExchange.InsufficientFoxBalance.selector);
        exchange.exchange(p, _signPermit(p));
    }

    function _registerItem(
        uint256 itemId,
        IFoxStylerItems.TransferPolicy policy,
        bool claimable,
        bool inputEligible,
        bool outputEligible,
        uint256 maxSupply
    ) internal {
        items.registerItem(
            itemId,
            "ipfs://placeholder.json",
            policy,
            claimable,
            inputEligible,
            outputEligible,
            maxSupply
        );
    }

    function _claimToFox(uint256 foxId, uint256 itemId, uint256 amount, bytes32 claimId)
        internal
        returns (address)
    {
        FoxStylerClaims.Claim memory c = _claim(claimId, foxId, itemId, amount);
        return claims.claim(c, _signClaim(c));
    }

    function _claim(bytes32 claimId, uint256 foxId, uint256 itemId, uint256 amount)
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
            sourceReferenceHash: keccak256(abi.encode("fuzz", claimId, foxId, itemId)),
            expiresAt: uint64(block.timestamp + 1 days)
        });
    }

    function _signClaim(FoxStylerClaims.Claim memory c) internal returns (bytes memory) {
        bytes32 digest = claims.hashClaim(c);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(rewardSignerPk, digest);
        return abi.encodePacked(r, s, v);
    }

    function _signPermit(FoxExchange.ExchangePermit memory p) internal returns (bytes memory) {
        bytes32 digest = exchange.hashPermit(p);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(exchangeSignerPk, digest);
        return abi.encodePacked(r, s, v);
    }

    function _nonZeroId(bytes32 seed, string memory label) internal pure returns (bytes32 id) {
        id = keccak256(abi.encode(seed, label));
        if (id == bytes32(0)) id = bytes32(uint256(1));
    }
}

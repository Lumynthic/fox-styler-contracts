# Fox Styler Backend Integration — v0.3 Draft

This document defines the boundary between Fox Styler's off-chain game state and the token contracts. It is an integration draft; it does not change game canon.

## 1. Earned item lifecycle

An ordinary Fox-owned item is first recorded off-chain against a specific Fox.

Suggested database record:

```json
{
  "earnedItemLotId": "stable-backend-id",
  "foxContract": "0xf455A9b47d720E144A5C29B32bC078E6dA5E0f76",
  "foxTokenId": "812",
  "itemId": "1001",
  "earnedQuantity": "3",
  "claimedQuantity": "0",
  "sourceType": 1,
  "sourceReferenceHash": "0x...",
  "earnedAt": "2026-09-10T20:00:00Z"
}
```

`itemId`, quantities, and token IDs should be treated as decimal strings at JSON boundaries so JavaScript does not lose precision on large `uint256` values.

## 2. Claim generation

The client requests tokenization. The backend verifies that the Fox still owns unclaimed quantity in the game database, allocates a globally unique `claimId`, and signs the EIP-712 `Claim` message defined by `FoxStylerClaims`.

The claim intentionally does **not** contain a destination wallet. The smart contract creates/resolves the canonical Backpack from `foxTokenId` and mints there.

A Fox sale after the item was earned does not invalidate the claim. This is deliberate: the unclaimed item belongs to the Fox.

Recommended backend sequence:

1. Lock the earned-item lot row.
2. Verify `earnedQuantity - claimedQuantity >= requestedAmount`.
3. Allocate a unique random/hashed `claimId` (never zero).
4. Persist the claim record before signing.
5. Sign the EIP-712 message.
6. Return typed data + signature to client/relayer.
7. Index `ItemClaimed`/`ClaimMinted` on-chain.
8. Mark the corresponding quantity tokenized only after confirmed chain receipt.

If a submitted transaction fails, the same unconsumed claim can be retried until expiry. Do not create a second claim ID for the same quantity unless the first claim is explicitly invalidated/expired in backend accounting.

## 3. Exchange permit generation

Exchange consumes **tokenized** copies from one Fox only.

Before signing a permit, the backend should verify:

- current on-chain `ownerOf(foxTokenId)`;
- canonical Backpack address;
- on-chain Backpack balance for the input ID;
- currently placed/reserved quantity in that Fox's Den;
- selected recipe and selected allowed output;
- no conflicting pending Exchange operation for the same reserved inventory.

Set:

`minRemainingBalance = max(recipe.retainedAmount, protectedBaseCopy + currentlyReservedPlacedQuantity)`

where the exact off-chain reservation calculation is implemented by Fox Styler. The contract independently requires `minRemainingBalance >= recipe.retainedAmount`.

The permit includes `expectedOwner`. If the Fox transfers before execution, the permit becomes invalid and the new owner must request a fresh permit.

Recommended permit lifetime: short (for example 5–15 minutes), with the exact production duration configurable in the backend rather than hardcoded into Solidity.

### Recipe-version rule

`recipeHash` is now versioned on-chain. The backend must fetch `FoxExchange.recipeHash(recipeId)` after the current recipe configuration is final and place that exact value in the EIP-712 permit. Reconfiguring, disabling, or re-enabling the recipe changes its version/hash and intentionally makes older permits stale. Do not calculate a recipe hash from a cached local recipe definition alone.

## 4. Den placement reconciliation

Den coordinates/placement stay off-chain. Placement does not change ERC-1155 ownership.

If a collector manually transfers a tokenized item away from a Backpack outside Fox Styler, the chain indexer must reconcile the balance and invalidate/remove any placement that can no longer be backed by owned quantity.

Do not put ordinary Den dragging/repositioning on-chain solely to prevent this edge case.

## 5. Collector-profile entitlements

These remain separate from Fox Backpack balances:

- Wardrobe unlocks;
- Treowx Starter Set;
- Founding Den Set;
- Special Moments;
- permanent holder-tier account/profile unlocks.

Store the wallet that earned the entitlement, the entitlement ID, earned timestamp, and source/qualification record. Where useful, store `sourceFoxTokenId` as provenance without making that Fox the owner of the entitlement.

## 6. Indexing

At minimum index:

- Fox ERC-721 transfers (`Transfer`);
- Fox Styler ERC-1155 `TransferSingle` and `TransferBatch`;
- `ItemClaimed` / `ClaimMinted`;
- `ExchangeCompleted`;
- item registration/policy/freeze events;
- signer and role/admin changes for monitoring.

Chain data is authoritative for **tokenized balances**. Fox Styler's database is authoritative for **unclaimed earned quantities, Den placement, progression, and collector-profile entitlements**.

## 7. Marketplace / operator approval behavior

For native Fox Styler ERC-1155 items, a canonical Fox Backpack is intentionally not allowed to call `setApprovalForAll`. Standard ERC-1155 operator approval state is persistent against the holder address, while the ERC-6551 Backpack address survives a Fox ownership transfer. Blocking Backpack-level operator approvals prevents a previous owner's marketplace/operator authorization from remaining useful after a Fox sale.

The supported v0.3 flow for a normal tradable item is:

1. current Fox owner directs the Backpack to transfer the item to a normal wallet;
2. the normal wallet may call `setApprovalForAll` for a marketplace/operator;
3. marketplace trading proceeds under ordinary ERC-1155 rules.

Fox Styler should not present a direct `Approve marketplace for this Backpack` action for native Fox Styler items.

This rule does not sanitize approvals in third-party token contracts. If Fox Styler later exposes arbitrary external assets inside the Backpack UI, the UI/indexer should treat external approval state as a separate security domain.

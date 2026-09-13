# Security Notes — v0.3

This package is a hardened implementation draft, **not an audit**.

## Trust boundaries

### The collector controls

- the Fox ERC-721 in their wallet;
- the canonical ERC-6551 Backpack through current Fox ownership;
- intentional transfers of tradable Backpack items;
- intentional Duplicate Exchanges submitted from the current Fox owner address.

### Fox Styler backend controls

- deciding whether an off-chain earned item is valid;
- signing tokenization claims;
- evaluating Den placement/reservation state before signing an Exchange permit;
- permanent collector-profile entitlements and game state.

The backend must **not** have authority to transfer arbitrary assets out of a Fox Backpack.

## High-priority controls before mainnet

1. Verify `eth_getCode` for the canonical ERC-6551 registry on the exact target chain.
2. Keep `FoxStylerAccount` immutable after review and use one canonical implementation + salt.
3. Put production admin roles behind a multisig.
4. Use separate keys/signers for reward claims and Exchange permits.
5. Keep Exchange permits short-lived and owner-bound.
6. Assign conservative finite caps to any scarce claimable IDs before first mint.
7. Freeze item metadata/policy only after the production asset, URI, transfer policy, and cap are confirmed.
8. Monitor Claim/Exchange events and signer-role changes.
9. Reconcile Den placement immediately when a placed token leaves a Backpack.
10. Keep native Fox Styler item operator approvals disabled from token-bound accounts.
11. Obtain an independent smart-contract review/audit before mainnet.

## Token-bound account approval safety

### Native Fox Styler ERC-1155 items

A normal ERC-1155 `setApprovalForAll` approval is stored against the holder address. Because an ERC-6551 Backpack keeps the same address when the parent Fox changes owners, a persistent operator approval created by an earlier owner could otherwise remain live for the next owner.

`FoxStylerItems` therefore rejects `setApprovalForAll` when the caller is an ERC-6551 account and defensively reports `isApprovedForAll == false` for ERC-6551 holders. This protects Fox Styler's own ERC-1155 inventory from stale marketplace/operator approvals surviving a Fox sale.

This does **not** prevent ordinary trading:

- the current Fox owner can direct the Backpack to transfer a tradable item itself through `FoxStylerAccount.execute`;
- the collector can move a tradable item from the Backpack to a normal wallet;
- once in a normal wallet, standard ERC-1155 operator approvals and marketplace flows work normally.

### Third-party tokens sent into a Backpack

The Backpack is a general smart account and can receive assets that Fox Styler did not issue. Fox Styler cannot alter or revoke approval state stored inside an unrelated ERC-20/ERC-721/ERC-1155 contract. If a collector uses the Backpack to approve an external token's operator, that approval may remain associated with the Backpack address after the Fox changes owners.

For v0.3, the safety guarantee is deliberately narrow: **Fox Styler prevents persistent operator approvals for Fox Styler items. It does not claim to sanitize approvals created on third-party token contracts.** A broader restriction on arbitrary Backpack approval calls would be a separate product/security decision and is not silently locked by this implementation.

## Existing Fox parent-token hazards

### Burning a Fox

The parent ERC-721's burn behavior is outside these contracts. A burned parent token can leave its ERC-6551 account without a valid current owner, potentially making its assets inaccessible. Fox Styler should not expose a casual burn action and should warn users to remove any independently transferable Backpack assets before intentionally burning a Fox.

### Sending a Fox into its own Backpack

The Backpack rejects the parent Fox through `onERC721Received`, so normal safe transfers fail. A raw ERC-721 `transferFrom` can bypass receiver hooks. Fox Styler must never construct or encourage that transaction.

## Signer compromise behavior

### Reward signer

A compromised reward signer can authorize claims for any `claimable` ID, subject to supply caps. It cannot choose an arbitrary destination because `FoxStylerClaims` derives the destination from the signed Fox token ID. Emergency response: pause Claims and/or Items, rotate signer, investigate issued claim IDs.

### Exchange signer

A compromised Exchange signer cannot unilaterally burn a collector's items because `exchange()` must be submitted by the current Fox owner and the permit is bound to that owner. Emergency response: pause Exchange and rotate signer.

## Administrative role caution

`EXCHANGE_ROLE` and `CLAIMS_ROLE` on `FoxStylerItems` are intentionally powerful module roles. Grant them only to reviewed module contracts. Never grant either role directly to a routine backend EOA.

## v0.3 Exchange permit lifecycle hardening

Exchange recipe hashes now include an on-chain recipe version. Reconfiguration and enabled-state changes advance the version. This prevents a permit signed before a recipe disable/re-enable cycle from becoming valid again later. Backend code must use the contract-returned `recipeHash(recipeId)` when signing permits.

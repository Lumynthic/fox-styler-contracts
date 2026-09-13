# Fox Styler Contract Architecture Lock — v0.3

Status: security-hardened implementation draft, **not independently audited and not production deployed**.

## Locked product rules represented in this scaffold

- Every Fox has its own canonical ERC-6551 Backpack.
- Fox-owned item balances are never pooled across Foxes just because one collector owns them.
- Collector Fox count may be aggregated for account-level eligibility; that does not merge Backpack inventories.
- Ordinary game items are earned off-chain first and optionally tokenized later.
- Tokenization always mints a Fox-earned item to that same Fox's canonical Backpack.
- A signed Fox-earned claim may survive a Fox sale because the reward belongs to the Fox, not the old wallet.
- Tradable tokenized items may be moved between Foxes/wallets through real on-chain transfers and therefore gas.
- Tokenized does not imply tradable: Fox-bound item IDs cannot move independently from their Backpack.
- Duplicate Exchange is strictly per-Fox. One Fox must own every required input copy.
- Exchange retains the recipe-required base/reserved quantity and mints the result to the same Fox Backpack.
- Exchange permits are bound to the current Fox owner who requested them. Selling/transferring the Fox invalidates the outstanding permit.
- Den placement remains off-chain. Exchange permits carry `minRemainingBalance` to protect retained/placed quantities.
- Persistent ERC-1155 `setApprovalForAll` approvals are disabled when the holder is an ERC-6551 account **for Fox Styler's own item contract**, preventing an old marketplace/operator approval from surviving a Fox sale. Direct Backpack transfers remain supported; a collector can move a tradable item to a normal wallet for standard marketplace approvals.
- Wardrobe unlocks, Treowx Starter Set, Founding Den Set, Special Moments, and permanent holder-tier profile unlocks are collector-profile entitlements by default and are not represented as ERC-1155 balances here.
- Skills, Trust, live state, Roam, Vacation, dialogue, Den coordinates, achievements, and rich history remain game/database state, not Solidity state.

## Explicit security boundary

The Backpack is capable of receiving third-party tokens. Fox Styler's operator-approval protection applies only to `FoxStylerItems`. Approval state stored by an unrelated external token contract is outside Fox Styler's control. A broader restriction on arbitrary Backpack approval calls is **not locked in v0.3** and would require a deliberate product/security decision.

## Not locked / intentionally configurable

- Production item IDs.
- Final metadata URIs and final art.
- Duplicate Exchange costs.
- Which exact normal items are Exchange inputs.
- Which future tokenized items are Fox-bound.
- Gas sponsorship provider and policy.
- Initial holder-tier reward catalog.
- Any broader policy restricting approval calls for third-party assets held by a Backpack.

## Existing Fox NFT

Mainnet collection address supplied by project owner:

`0xf455A9b47d720E144A5C29B32bC078E6dA5E0f76`

The Fox Variable contract itself is not modified by this project.

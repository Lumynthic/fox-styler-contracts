# Fox Styler v0.2 — Internal Security Review

Status: **internal pre-compile review, not an independent audit**.

This pass reviewed the v0.1 scaffold against the approved Fox Styler ownership model and current ERC-6551/OpenZeppelin behavior. The findings below are the concrete issues corrected in v0.2.

## FS-01 — Exchange permit survived a Fox transfer

**Severity:** Medium  
**v0.1 behavior:** An Exchange permit contained the Fox ID but not the owner who requested it. After the Fox changed hands, the new current owner could still submit the old permit before expiry.  
**Why it mattered:** The project's intended rule is that a destructive Exchange approval should become stale on ownership change, particularly because its `minRemainingBalance` was calculated from off-chain Den placement/reservation state at permit issuance.  
**v0.2 fix:** `expectedOwner` is now part of the signed EIP-712 permit. `exchange()` requires both `ownerOf(foxTokenId) == expectedOwner` and `msg.sender == expectedOwner`. A Fox transfer therefore invalidates the permit.

## FS-02 — Exchange role could use any registered item as recipe output

**Severity:** Medium  
**v0.1 behavior:** Input IDs had `exchangeInputEligible`, but there was no equivalent output policy. `exchangeMint()` could mint any registered token ID if a recipe referenced it.  
**Why it mattered:** Normal items, future Fox-bound rewards, or other registered IDs should not accidentally become Exchange rewards due to recipe misconfiguration.  
**v0.2 fix:** Item definitions now include `exchangeOutputEligible`. Recipe configuration validates both sides, and `FoxStylerItems.exchangeMint()` re-checks output eligibility at execution.

## FS-03 — Transfer policy could be changed after collectors already held an item

**Severity:** Medium  
**v0.1 behavior:** Before `freezeItem`, an admin could switch an already-minted ID between `Transferable` and `FoxBound`.  
**Why it mattered:** A later policy switch could unexpectedly trap a tradable token or make a previously bound token freely transferable.  
**v0.2 fix:** Once `totalSupply(itemId) > 0`, transfer policy is immutable. Other mutable flags can still be disabled/enabled until explicit item freeze.

## FS-04 — Finite supply cap could be expanded or removed after minting

**Severity:** Medium-Low  
**v0.1 behavior:** `maxSupply` could be raised or changed to zero (uncapped) before the item was frozen.  
**Why it mattered:** A published finite cap should not silently become larger after collectors receive the token.  
**v0.2 fix:** After first mint, an existing finite cap can only remain unchanged or decrease to a value no lower than current supply. An initially uncapped item may later receive a finite cap because that narrows, rather than expands, issuance authority.

## FS-05 — Zero claim / permit identifiers were accepted

**Severity:** Low  
**v0.1 behavior:** `bytes32(0)` was technically usable as a claim ID or permit ID.  
**Why it mattered:** It makes accidental backend defaults easier to turn into real state changes.  
**v0.2 fix:** zero claim IDs and zero Exchange permit IDs revert.

## FS-06 — Deployment admin handoff foot-gun

**Severity:** Low  
**v0.1 behavior:** `DeployCore.s.sol` granted the configured admin role and then renounced the deployer's role. If both addresses were accidentally the same, the script could remove the only default admin.  
**v0.2 fix:** deployment now requires `ADMIN_MULTISIG != deployer`, plus nonzero critical configuration addresses.

## FS-07 — Receiver interface advertisement incomplete

**Severity:** Informational  
**v0.1 behavior:** The Backpack implemented `IERC721Receiver` but did not advertise that interface through `supportsInterface`.  
**v0.2 fix:** added the interface ID. ERC-721 receipt itself did not depend on this, but introspection is now consistent with implementation.

## FS-08 — Persistent ERC-1155 operator approval could outlive Fox ownership

**Severity:** High  
**Issue found during v0.2:** Standard ERC-1155 `setApprovalForAll` stores approval against the token-holder address. For Backpack-held items, that holder is the ERC-6551 account itself. The Backpack address does **not** change when the parent Fox is sold. If a Backpack approved a marketplace/operator and the Fox later changed owners, that old operator approval could remain attached to the same Backpack address and therefore endanger the new owner's items.  
**Why it mattered:** ERC-6551 changes who controls an account without changing the account address, while ordinary ERC-1155 operator approvals are address-persistent. Those two behaviors are individually correct but unsafe together unless handled deliberately.  
**v0.2 fix for Fox Styler items:** `FoxStylerItems` detects ERC-6551 accounts through ERC-165 (`IERC6551Account` interface id `0x6faff5f1`) and refuses `setApprovalForAll` when the approver is a token-bound account. `isApprovedForAll` also defensively returns false for an ERC-6551 account. A Backpack can still directly transfer its own tradable Fox Styler items through `FoxStylerAccount.execute`. A collector who needs a standard marketplace operator approval can first move the tradable item from the Backpack to a normal wallet, then approve/list it there.

**Scope limitation:** This protection only governs the Fox Styler ERC-1155 contract. A Fox Backpack can hold third-party ERC-20/ERC-721/ERC-1155 assets too. Approval state created on those external token contracts is outside Fox Styler's control and may likewise persist after the Fox changes owners. Until a broader Backpack approval policy is explicitly designed and approved, Fox Styler should not imply that arbitrary third-party assets placed in the Backpack receive the same approval safety guarantees as native Fox Styler items.

# Remaining review items

These are not considered fixed merely because v0.2 exists:

- **Compiler/test execution:** the source still needs an actual Foundry compile and test run.
- **ERC-6551 registry bytecode:** verify directly with `eth_getCode` on chain 46630 and 4663 before deployment.
- **Third-party token approvals inside a Backpack:** Fox Styler can block persistent operator approvals for its own ERC-1155, but cannot revoke approvals stored in arbitrary external token contracts. This must remain an explicit product/security limitation unless a broader Backpack execution policy is later approved.
- **Existing Fox burn behavior:** burning the parent Fox can orphan the Backpack's control path. The app must treat this as destructive and warn accordingly.
- **Raw parent-token self-transfer:** `safeTransferFrom` into its own Backpack is rejected, but raw ERC-721 `transferFrom` can bypass receiver hooks. The UI must never offer that action.
- **Reward signer compromise:** a valid reward signer can authorize claimable supply. Scarce IDs need finite caps, signer isolation, monitoring, and emergency pause/rotation.
- **Off-chain Den reservation race:** Exchange permits should be short-lived; Fox Styler should lock Den placement changes while issuing/submitting a permit and reconcile chain transfers immediately.
- **Admin authority:** use a multisig, not a personal wallet, for production roles.
- **External review:** independent audit/review is still required before mainnet.

# v0.2 security invariants

The intended test suite now explicitly checks:

- one Fox cannot borrow another Fox's balance for Exchange;
- Exchange output returns to the same Fox Backpack;
- first/reserved balance survives Exchange;
- Fox sale invalidates an outstanding Exchange permit;
- Fox sale does **not** invalidate a Fox-earned tokenization claim;
- old Fox owner loses Backpack execution authority immediately after transfer;
- Fox-bound tokens cannot be moved independently;
- mixed ERC-1155 batch transfers containing a Fox-bound ID revert atomically;
- Fox Styler ERC-1155 operator approvals cannot be created from a token-bound Backpack;
- normal wallets can still use ordinary ERC-1155 operator approvals after a tradable item leaves the Backpack;
- claim IDs remain consumed across a replacement Claims module;
- changed recipe economics invalidate an old permit;
- output-cap failure rolls back the preceding Exchange burn;
- metadata/item freeze is irreversible;
- finite supply caps cannot expand after issuance;
- transfer policy cannot change after issuance.

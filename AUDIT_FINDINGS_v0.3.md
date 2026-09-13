# Fox Styler v0.3 — Internal Security Review Addendum

Status: **internal pre-compile review; not an independent audit.**

This addendum carries forward the v0.2 findings and records the new v0.3 hardening.

## FS-09 — Disabled recipe could revive a previously signed permit

**Severity:** Medium-Low

**v0.2 behavior:** an Exchange permit committed to `recipeHash`, but the hash did not change when a recipe was merely disabled and later re-enabled. If the permit had not expired, a permit signed before disabling could become executable again after re-enabling.

**v0.3 fix:** each recipe now has an on-chain version counter. Recipe configuration and enabled-state changes increment the version. The recipe hash commits to `recipeId + version + economics/output fields`, so any real recipe lifecycle change permanently invalidates previously signed permits.

A dedicated test covers disable → re-enable invalidation.

## Expanded fuzz coverage

v0.3 adds property-oriented tests around:

- exact claim quantity;
- replay resistance;
- Fox-bound transfer prohibition;
- explicit tradable movement between Foxes;
- Backpack authority after Fox transfer;
- Exchange minimum-retention invariants;
- no cross-Fox balance pooling.

## Remaining hard gates

- actual compilation against the pinned dependency versions;
- actual execution of all 41 Foundry tests;
- 10,000-run fuzz pass;
- compiler warning review;
- direct ERC-6551 registry bytecode check on Robinhood Chain testnet/mainnet;
- testnet deployment rehearsal;
- external security review before mainnet.

Passing local/static checks is not a substitute for any of those gates.

# Test Plan — Fox Styler Contracts v0.3

Status: **41 Foundry tests authored. Static checks: 77 PASS / 0 FAIL. Solidity execution still requires Foundry.**

## Backpack / ERC-6551

- claim lazily creates a Backpack;
- Backpack owner equals current Fox owner;
- control moves immediately when Fox transfers;
- former owner cannot execute after transfer;
- parent Fox safe-transfer into its own Backpack reverts;
- ERC-721 receiver interface is advertised.

## Claims

- relayer can submit a valid claim;
- destination is the Fox Backpack, never caller-selected;
- same claim ID cannot execute twice;
- consumed claim ID remains blocked through a replacement Claims module;
- invalid signer fails;
- expired claim fails;
- zero claim ID fails;
- signed Fox-earned claim still resolves to the Fox after ownership changes;
- Claims pause blocks tokenization;
- Items pause blocks claim minting.

## Item policy

- Fox-bound item cannot leave Backpack;
- mixed batch containing a Fox-bound ID fails atomically;
- TBA cannot create a persistent Fox Styler ERC-1155 `setApprovalForAll` approval;
- a tradable item moved to a normal wallet can use ordinary ERC-1155 operator approval;
- transfer policy cannot change after first mint;
- finite supply cap cannot increase/remove after first mint;
- finite cap can tighten if still >= current supply;
- frozen item URI/policy cannot change.

## Exchange

- one Fox with enough duplicates can exchange;
- protected original/reserved balance remains;
- output returns to the same Fox Backpack;
- balances across Foxes cannot pool;
- owner can explicitly transfer a tradable item between their Foxes;
- placement-aware `minRemainingBalance` invalidates a permit after an intervening transfer;
- Fox sale invalidates an owner-bound Exchange permit;
- old owner cannot use permit after sale;
- wrong signer fails;
- expired permit fails;
- reconfigured recipe invalidates old permit;
- **disable → re-enable also invalidates old permit through recipe versioning**;
- recipe cannot use an unauthorized output ID;
- permit cannot reserve less than recipe-required retention;
- output supply-cap failure rolls back the input burn;
- Exchange pause blocks execution.

## Fuzz/property tests

- arbitrary positive claim amounts mint exactly once;
- replay never increases balance;
- arbitrary Fox-bound quantities cannot be independently transferred;
- arbitrary transferable quantities can move between owned Fox Backpacks;
- arbitrary new Fox owner immediately removes former owner's execution authority;
- arbitrary Exchange input/retention values preserve the signed minimum;
- arbitrary balances split across two Foxes never pool for one Fox's Exchange.

## Required quality gate

```bash
./tools/bootstrap_dependencies.sh
./tools/run_quality_gate.sh
```

Equivalent manual commands:

```bash
python3 tools/static_checks.py
forge fmt --check
forge build --sizes
forge test -vvv
forge test --fuzz-runs 10000
```

Only after these pass should the project move to Robinhood testnet.

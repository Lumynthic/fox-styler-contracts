# Fox Styler Contracts v0.4

Compile/test candidate for the approved Fox Styler ownership architecture.

**Status: compiled and tested locally and in GitHub Actions with the pinned toolchain. 41 tests passed; seven fuzz tests passed 10,000 cases each. Not independently audited. Not deployed. Not mainnet-ready.**

See [VALIDATION_v0.4.md](VALIDATION_v0.4.md) for exact results, fixes, warning review, contract sizes, and CI evidence.

## What v0.4 changes

Fixes the structural checker and Foundry test harness, applies forge formatting, and records executed validation. Production contract logic and the v0.3 ownership architecture are preserved.

The next phase is Robinhood testnet preparation and chain registry verification. Historical v0.3 documents below describe the previous pre-compile state.


## What v0.3 adds

- 41 authored Foundry tests across unit, adversarial, and fuzz coverage.
- Recipe versions are now part of Exchange recipe hashes. Disabling/re-enabling or reconfiguring a recipe invalidates outstanding permits instead of allowing an old permit to become valid again.
- A pinned dependency/toolchain manifest in `DEPENDENCIES.lock`.
- One-command dependency bootstrap: `./tools/bootstrap_dependencies.sh`.
- One-command quality gate: `./tools/run_quality_gate.sh`.
- GitHub Actions CI under `.github/workflows/contracts-ci.yml`.
- Exact local/WSL instructions in `COMPILE_AND_TEST.md`.
- Static source gate currently reports **77 PASS / 0 FAIL**.

## Architecture represented in code

- Each Fox has its own canonical ERC-6551 Backpack.
- Fox-owned inventories do not pool across Foxes just because one collector owns them.
- Ordinary game rewards are earned off-chain first and may be tokenized later.
- Tokenized Fox Styler items use ERC-1155.
- Tradable items can move between Foxes/wallets through explicit on-chain transfers.
- Fox-bound tokenized items cannot be transferred independently; they remain at the same Backpack when the parent Fox changes ownership.
- Collector-profile entitlements such as Wardrobe unlocks, Treowx Starter Set, Founding Den Set, Special Moments, and permanent holder-tier profile unlocks remain outside ERC-1155 Backpack balances.
- Duplicate Exchange is strictly per-Fox: one Backpack must hold all required copies and the reward returns to that same Backpack.

## Core contracts

- `src/FoxStylerAccount.sol` — ERC-6551 Backpack implementation controlled by the current owner of the bound Fox.
- `src/FoxStylerItems.sol` — ERC-1155 tokenized item layer, item policy, caps, metadata freeze, and global claim replay state.
- `src/FoxStylerClaims.sol` — EIP-712 bridge from off-chain earned item to that Fox's Backpack.
- `src/FoxExchange.sol` — per-Fox Duplicate Exchange with owner-bound, short-lived permits and recipe-version invalidation.

## Pinned dependencies

```text
Foundry v1.7.1
forge-std v1.16.1
OpenZeppelin Contracts v5.6.1
ERC-6551 reference v0.3.1
Solidity 0.8.24
```

Install and run the gate:

```bash
./tools/bootstrap_dependencies.sh
./tools/run_quality_gate.sh
```

See `COMPILE_AND_TEST.md` for full instructions, including Windows/WSL and GitHub Actions.

## Robinhood Chain target

Production collection:

- The Fox Variable: `0xf455A9b47d720E144A5C29B32bC078E6dA5E0f76`
- Robinhood Chain mainnet: chain ID `4663`
- Robinhood Chain testnet: chain ID `46630`
- ERC-6551 canonical registry target: `0x000000006551c19487814612e58FE06813775758`

The registry address must still be checked with `eth_getCode`/`cast code` on the exact target network before deployment. The real Fox collection exists on mainnet; testnet end-to-end work will use a disposable/mock Fox collection rather than pretending the mainnet NFT exists on testnet.

## Before Robinhood testnet

1. Get a clean `forge build --sizes`.
2. Get every authored test passing.
3. Run the 10,000-case fuzz pass.
4. Review every compiler warning.
5. Verify the ERC-6551 registry bytecode on chain `46630`.
6. Deploy disposable test contracts only.
7. Rehearse role/admin/signing flows with test keys.
8. Exercise real on-chain Fox transfer, claim-after-transfer, item movement, and Exchange flows.

Do not use production private keys or mainnet admin credentials during this stage.

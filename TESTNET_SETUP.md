# Disposable Robinhood testnet setup

## Current status — 2026-09-14 UTC

The v0.4 production contract logic is unchanged. A separate testnet-only deployment script and read-only network preflight have been added.

Official network configuration: https://docs.robinhood.com/chain/add-network-to-wallet/
- RPC: https://rpc.testnet.chain.robinhood.com
- Chain ID: 46630
- Registry candidate: 0x000000006551c19487814612e58FE06813775758

Live verification is BLOCKED: local RPC calls timed out, and GitHub Actions received HTTP 403 before eth_chainId returned. Neither registry presence nor absence has been established.
Evidence: https://github.com/Lumynthic/fox-styler-contracts/actions/runs/34873530293

Do not broadcast until an authorized working RPC confirms chain ID, registry runtime identity, and expected registry behavior. Nonempty bytecode alone is insufficient. No chain transaction was sent.

## Prepared script

script/DeployTestnetSandbox.s.sol:
- Enforces chain ID 46630 and nonempty registry code.
- Creates a disposable MockFox, Account implementation, Items, Claims, and Exchange.
- Mints mock Foxes 101 and 202 to the test deployer.
- Grants Claims/Exchange module roles and test-admin roles.
- Registers three test items and a sample 3-copy burn / 1-copy retained recipe.
- Keeps administration with the throwaway deployer for rehearsal; this does not rehearse production multisig handoff.
- Uses separate reward and Exchange signer addresses.
- Prints deployed addresses and predicted Backpack addresses. Backpacks are not deployed by this script.
- Does not deploy a replacement registry or touch the mainnet collection.

MockFox minting is permissionless, its IDs/metadata are disposable, and recipe costs are arbitrary test fixtures. None is production configuration.

## Required local setup

Use throwaway test-only accounts. Do not send private keys or seed phrases in chat.
Set public addresses for TESTNET_DEPLOYER, TESTNET_REWARD_SIGNER, and TESTNET_EXCHANGE_SIGNER. These three addresses must be distinct and nonzero.
Use an authorized RPC via ROBINHOOD_TESTNET_RPC_URL. Keep authenticated URLs local.
For broadcasting later, the deployer must have faucet ETH and a matching local Foundry keystore account.

After the network gate is independently verified, simulate first:

```bash
forge script script/DeployTestnetSandbox.s.sol:DeployTestnetSandbox \
  --rpc-url "$ROBINHOOD_TESTNET_RPC_URL"
```

This command has no --broadcast and sends no transaction.
Inspect the simulation, addresses, chain ID and estimated gas before broadcasting through the local keystore. No broadcast command is enabled in CI.

Official faucet: https://faucet.testnet.chain.robinhood.com/

## Required end-to-end rehearsal after deployment

Record transaction hashes, Fox IDs, Backpack addresses and before/after balances for:
1. Claim items into Fox 101 and Fox 202, proving destinations and replay rejection.
2. Transfer Fox 101 to a second test wallet; prove old-owner rejection and new-owner control.
3. Redeem an unclaimed Fox-earned reward after transfer.
4. Attempt Exchange with split balances; verify no pooling.
5. Transfer tradable copies manually, then Exchange with sufficient balance; retain the protected copy and mint output to the same Backpack.
6. Reject Fox-bound transfers and Backpack operator approvals.
7. Check pause/unpause, stale owner permits, recipe disable/re-enable invalidation and reservation minimums.
8. Rehearse separate production-style admin handoff before mainnet consideration.

Compilation and unit/fuzz coverage do not replace these real-chain checks or independent security review.

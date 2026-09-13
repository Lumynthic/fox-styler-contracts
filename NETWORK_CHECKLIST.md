# Robinhood Chain Predeployment Checklist — v0.3

This is an operational checklist, not proof that any address is currently deployed.

## Network constants

- The Fox Variable mainnet contract: `0xf455A9b47d720E144A5C29B32bC078E6dA5E0f76`
- Robinhood Chain mainnet chain ID: `4663`
- Robinhood Chain testnet chain ID: `46630`
- expected canonical ERC-6551 registry address: `0x000000006551c19487814612e58FE06813775758`

## Before any testnet deployment

1. Configure a trusted Robinhood Chain testnet RPC endpoint.
2. Call `eth_chainId` and verify it returns `46630`.
3. Call `eth_getCode` for `0x000000006551c19487814612e58FE06813775758`; do not proceed if the result is empty (`0x`).
4. Compare the intended ERC-6551 registry interface/version against the pinned `erc6551/reference@v0.3.1` dependency.
5. Deploy `FoxStylerAccount`, `FoxStylerItems`, and `FoxStylerClaims` using test-only keys/addresses.
6. Verify deployed contract bytecode/source on the testnet explorer where supported.
7. Create at least two test Foxes so transfer and no-pooling scenarios can be exercised.
8. Run real-chain claim, Fox transfer, claim-after-transfer, Backpack item transfer, operator-approval rejection, and Exchange flows.
9. Confirm all role assignments and admin handoff after deployment.
10. Never reuse testnet private keys as production administration/signing keys.

## Before mainnet deployment

1. Re-run the complete compile/test/fuzz/invariant suite against the exact tagged source commit intended for release.
2. Call `eth_chainId` and verify `4663`.
3. Independently verify non-empty bytecode at the expected ERC-6551 registry address on mainnet.
4. Verify The Fox Variable address and expected ERC-721 behavior on the exact mainnet RPC.
5. Confirm the production admin multisig, reward signer, and Exchange signer through an out-of-band review.
6. Confirm the canonical Backpack implementation and salt. Changing either creates a different ERC-6551 account address, so this must be treated as a production identity decision.
7. Register only reviewed production item definitions.
8. Assign finite supply caps to scarce items before first issuance.
9. Verify that `CLAIMS_ROLE` and `EXCHANGE_ROLE` are granted only to reviewed module contracts.
10. Obtain independent security review/audit and resolve findings before mainnet use.
11. Perform a small controlled mainnet rollout before broad claims/Exchange are enabled.

## Useful Foundry/RPC checks

Examples only; fill RPC environment variables locally and never commit private keys.

```bash
cast chain-id --rpc-url "$ROBINHOOD_TESTNET_RPC_URL"
cast code 0x000000006551c19487814612e58FE06813775758 --rpc-url "$ROBINHOOD_TESTNET_RPC_URL"

cast chain-id --rpc-url "$ROBINHOOD_MAINNET_RPC_URL"
cast code 0x000000006551c19487814612e58FE06813775758 --rpc-url "$ROBINHOOD_MAINNET_RPC_URL"
cast code 0xf455A9b47d720E144A5C29B32bC078E6dA5E0f76 --rpc-url "$ROBINHOOD_MAINNET_RPC_URL"
```

A non-empty result is necessary but not sufficient: verify the registry's expected interface/behavior before relying on it.

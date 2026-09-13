# Fox Styler Contracts v0.4 validation — 2026-09-13 UTC

Status: local quality gate and GitHub Actions passed. Not independently audited. Not deployed.

## Scope and changes from v0.3

Continues the uploaded v0.3 architecture. Production Solidity and deployment scripts differ only in whitespace (verified against the original ZIP); no ownership, claim, approval, transfer-policy, recipe, or Exchange logic changed.

- Structural checks now scan src/, test/, and script/ only. The original checker incorrectly scanned installed dependency fixtures, producing 39 unrelated failures in CI.
- Applied Foundry v1.7.1 formatting.
- Calculated signatures before vm.prank / vm.expectRevert. Signing helpers call external hash functions; previously those calls consumed the next-call expectations before the operation under test.
- Parameterized custom errors now check their complete ABI-encoded arguments, retaining strict assertions.
- Removed one unused test variable and applied view mutability to five read-only test/helper functions.
- No authored tests removed: 34 core/adversarial tests plus 7 fuzz/property tests.

## Local executed results

Command: bash tools/run_quality_gate.sh with Foundry v1.7.1 on PATH.
Full output: validation/local-quality-gate.log.

| Gate | Actual result |
| --- | --- |
| Structural checks | 77 PASS, 0 FAIL |
| forge fmt --check | Passed |
| forge build --sizes | Passed, Solidity 0.8.24 |
| forge test -vvv | 41 passed, 0 failed, 0 skipped; 512 cases per fuzz test |
| forge test --fuzz-runs 10000 | 41 passed, 0 failed, 0 skipped; 10,000 cases per each of 7 fuzz tests (70,000 generated cases) |
| Focused security-path suite | 18 passed, 0 failed, 0 skipped |
| Final script status | QUALITY GATE PASSED, exit 0 |

The fuzz tests are property-oriented test functions, not a stateful invariant-handler campaign. Passing them does not establish correctness for all possible inputs or call sequences.

## Compiler and lint review

The initial compile reported six test-only compiler warnings: one unused variable and five functions eligible for view. Those were corrected.

Remaining forge lint warnings are retained visibly:

- Two block-timestamp warnings: Claims and Exchange compare signed expirations against block.timestamp. This is intentional deadline enforcement, not randomness. Boundary behavior is > expiresAt; zero permits no expiration. Backend signing must enforce the documented short-lived Exchange permit policy and allow for inclusion timing. This run did not validate Robinhood chain timestamp behavior.
- Twenty-one unsafe-typecast warnings: fixed string literals converted to bytes32 in core tests. All are at most 16 bytes, below the 32-byte destination width; no truncation occurs.

## Runtime contract sizes

| Contract | Runtime bytes |
| --- | ---: |
| FoxStylerAccount | 3,213 |
| FoxStylerItems | 10,815 |
| FoxStylerClaims | 6,563 |
| FoxExchange | 9,360 |

All pass forge build --sizes. Network-specific compatibility still requires testnet verification.

## Still open

Robinhood registry bytecode and chain compatibility verification; disposable testnet deployment and end-to-end ownership/claim/Exchange rehearsals; backend reservation consistency and signer operations; independent security review. Existing burn/self-transfer risks remain documented. No production keys were used and no testnet or mainnet transaction was sent.

## GitHub Actions evidence

Verified authenticated account: Lumynthic. Repository reported push/admin permissions; successful writes confirmed access.

- Original v0.3 import: 6e2bb5c26589bb45c10a0b2e78d1bcdb4d3b01b9.
- Run 34786394971: failed structural checks due to dependency scanning; Solidity steps did not execute.
- Run 34786464826: build succeeded; 29 tests passed and 12 failed due to test-harness issues described above.
- Passing tested commit: 15e8d6f0661a3ce57949b612ea1a0d48418b9602.
- Passing run: https://github.com/Lumynthic/fox-styler-contracts/actions/runs/34786570208
- Build completed with Compiler run successful! and no Solidity compiler warnings.
- Unit/adversarial suite: 41 passed, 0 failed, 0 skipped.
- High-run suite: 41 passed, 0 failed, 0 skipped; seven fuzz functions each ran 10,000 cases.
- Job and all workflow steps concluded success.
- Full job log: validation/github-actions-run-34786570208.log.

v0.4 adds release documentation and refreshed checksums to that tested source. Historical v0.3 status/audit documents are retained and explicitly marked historical.

# Fox Styler Contracts v0.4 — Compile & Test Gate

This is the next hard gate before Robinhood testnet. Do **not** deploy to mainnet from this package merely because the static checks pass.

## Pinned toolchain

- Solidity: `0.8.24`
- Foundry: `v1.7.1`
- forge-std: `v1.16.1`
- OpenZeppelin Contracts: `v5.6.1`
- ERC-6551 reference: `v0.3.1`

## Fast path on macOS / Linux / WSL2

From the project root:

```bash
# 1. Install Foundry if needed
curl -L https://foundry.paradigm.xyz | bash
foundryup -i v1.7.1

# 2. Install exact contract dependencies
./tools/bootstrap_dependencies.sh

# 3. Run the complete quality gate
./tools/run_quality_gate.sh
```

Expected final line:

```text
QUALITY GATE PASSED
```

If anything fails, stop there. Do not deploy until the failure is understood and corrected.

## Manual commands

```bash
python3 tools/static_checks.py
forge fmt --check
forge build --sizes
forge test -vvv
forge test --fuzz-runs 10000
```

For a specific failing test:

```bash
forge test --match-test <TEST_NAME> -vvvv
```

For Exchange-only debugging:

```bash
forge test --match-test 'test.*Exchange.*' -vvvv
```

## Windows

The least-friction route is WSL2 + Ubuntu.

1. Open PowerShell as Administrator and install WSL if it is not already present:

```powershell
wsl --install
```

2. Restart if Windows asks you to, open **Ubuntu**, unzip/copy this project into your Linux home directory, then run the macOS/Linux commands above.

Do not run deployment commands with a production private key during this compile/test stage.

## GitHub Actions option

The repository contains `.github/workflows/contracts-ci.yml`. If the folder is pushed to GitHub, CI will install the pinned Foundry toolchain and dependencies, build, run the unit/adversarial suite, and run the 10,000-case fuzz pass automatically.

A green CI job is useful evidence, but it is **not** an independent smart-contract audit.

## What success means

A passing gate means:

- Solidity compiles against the pinned dependencies;
- formatting is clean;
- the authored tests execute successfully;
- the fuzz suite found no failure in the configured run count.

It does **not** mean the contracts are automatically safe for mainnet. Robinhood testnet, deployment-role rehearsal, chain-level ERC-6551 checks, and external security review still follow.

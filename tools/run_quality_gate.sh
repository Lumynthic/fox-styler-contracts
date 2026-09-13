#!/usr/bin/env bash
set -euo pipefail

echo "[1/6] Static project checks"
python3 tools/static_checks.py

echo "[2/6] Solidity formatting"
forge fmt --check

echo "[3/6] Compile + contract sizes"
forge build --sizes

echo "[4/6] Unit/adversarial tests"
forge test -vvv

echo "[5/6] High-run fuzz pass"
forge test --fuzz-runs 10000

echo "[6/6] Focused security paths"
forge test --match-test 'test.*(Exchange|Replay|Owner|Approval|FoxBound).*' -vvv

echo "QUALITY GATE PASSED"

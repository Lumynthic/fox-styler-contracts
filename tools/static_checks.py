#!/usr/bin/env python3
"""Lightweight source consistency checks for environments without solc/forge.

This does NOT compile Solidity and is not a substitute for Foundry tests or an audit.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src"
TEST_DIR = ROOT / "test"

checks: list[tuple[str, bool, str]] = []


def add(name: str, condition: bool, detail: str = "") -> None:
    checks.append((name, bool(condition), detail))


def text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def delimiter_balance(source: str, opener: str, closer: str) -> bool:
    # Remove line/block comments and quoted strings enough for a structural smoke check.
    # Strip quoted strings BEFORE line comments so URLs like `ipfs://...` are not mistaken for comments.
    cleaned = re.sub(r'"(?:\\.|[^"\\])*"', '""', source)
    cleaned = re.sub(r"/\*.*?\*/", "", cleaned, flags=re.S)
    cleaned = re.sub(r"//.*", "", cleaned)
    depth = 0
    for ch in cleaned:
        if ch == opener:
            depth += 1
        elif ch == closer:
            depth -= 1
            if depth < 0:
                return False
    return depth == 0


# Inspect authored sources only; dependency fixtures are not project sources.
sol_files = sorted(p for folder in (SRC, TEST_DIR, ROOT / "script") for p in folder.rglob("*.sol"))
add("Solidity sources discovered", len(sol_files) >= 8, f"count={len(sol_files)}")

for path in sol_files:
    src = text(path)
    rel = path.relative_to(ROOT)
    add(f"balanced braces: {rel}", delimiter_balance(src, "{", "}"))
    add(f"balanced parentheses: {rel}", delimiter_balance(src, "(", ")"))

# Local imports must resolve. Package imports are intentionally left for Foundry dependency resolution.
for path in sol_files:
    src = text(path)
    for match in re.finditer(r'import\s+(?:\{[^}]*\}\s+from\s+)?"([^"]+)"\s*;', src, flags=re.S):
        imp = match.group(1)
        if imp.startswith("."):
            target = (path.parent / imp).resolve()
            add(f"local import resolves: {path.relative_to(ROOT)} -> {imp}", target.exists())

items = text(SRC / "FoxStylerItems.sol")
exchange = text(SRC / "FoxExchange.sol")
claims = text(SRC / "FoxStylerClaims.sol")
account = text(SRC / "FoxStylerAccount.sol")
tests = "\n".join(text(path) for path in sorted(TEST_DIR.rglob("*.t.sol")))

add("Exchange permit binds expectedOwner", "address expectedOwner" in exchange and "OwnerChanged" in exchange)
add("Exchange EIP-712 domain bumped to v2", 'EIP712("FoxExchange", "2")' in exchange)
add("Exchange output eligibility exists", "exchangeOutputEligible" in items and "ItemNotExchangeOutput" in items)
add("Recipe hash is versioned", "recipeVersions" in exchange and "_recipeHash" in exchange)
add("Recipe toggle invalidates permits", "++recipeVersions[recipeId]" in exchange and "testDisableReenableInvalidatesOutstandingPermit" in tests)
add("Recipe validates output eligibility", "InvalidOutputItem" in exchange and "exchangeOutputEligible" in exchange)
add("Transfer policy locks after first mint", "TransferPolicyLockedAfterMint" in items)
add("Finite cap can only tighten after mint", "SupplyCapCanOnlyTighten" in items)
add("Zero claim ID rejected", "InvalidClaimId" in claims and "c.claimId == bytes32(0)" in claims)
add("Zero permit ID rejected", "InvalidPermitId" in exchange and "p.permitId == bytes32(0)" in exchange)
add("Claim destination not caller-controlled", "items.mintClaim(backpack" in claims)
add("Exchange output returns to same backpack", "items.exchangeMint(backpack" in exchange)
add("Fox owner required for Exchange", "msg.sender != currentOwner" in exchange)
add("Parent Fox safe-transfer guard present", "ParentFoxCannotBeReceived" in account)
add("IERC721Receiver advertised", "type(IERC721Receiver).interfaceId" in account)
add("Global claim replay state remains in Items", "mapping(bytes32 claimId => bool consumed) public consumedClaimIds" in items)
add(
    "TBA ERC1155 operator approvals disabled",
    "TokenBoundAccountOperatorApprovalDisabled" in items
    and "function setApprovalForAll" in items
    and "_isERC6551Account(msg.sender)" in items,
)
add(
    "TBA approval introspection forced false",
    "function isApprovedForAll" in items and "if (_isERC6551Account(account)) return false" in items,
)
add(
    "ERC6551 account interface detection uses canonical ID",
    "0x6faff5f1" in items and "IERC165.supportsInterface" in items,
)
add(
    "Test covers blocked TBA operator approval",
    "testTbaCannotCreatePersistentERC1155OperatorApproval" in tests,
)
add(
    "Test covers normal-wallet operator approval",
    "testNormalWalletCanApproveOperatorAfterItemLeavesBackpack" in tests,
)

# Count authored Foundry tests.
test_count = len(re.findall(r"function\s+test[A-Za-z0-9_]*\s*\(", tests))
add("Expanded adversarial + fuzz test suite", test_count >= 41, f"test functions={test_count}")

# Secrets and obvious placeholders should not be hardcoded in Solidity source.
for path in sol_files:
    src = text(path)
    add(f"no PRIVATE_KEY literal in Solidity: {path.relative_to(ROOT)}", "PRIVATE_KEY=" not in src)

passed = sum(1 for _, ok, _ in checks if ok)
failed = len(checks) - passed

print("Fox Styler v0.3 static source checks")
print("=" * 38)
for name, ok, detail in checks:
    suffix = f" ({detail})" if detail else ""
    print(f"{'PASS' if ok else 'FAIL'}  {name}{suffix}")
print("-" * 38)
print(f"PASS: {passed}  FAIL: {failed}  TOTAL: {len(checks)}")
print("NOTE: These are structural checks only; Solidity still must be compiled and Foundry tests executed.")

sys.exit(1 if failed else 0)

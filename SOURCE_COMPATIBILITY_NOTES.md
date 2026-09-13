# Source Compatibility Notes — v0.3

These checks were performed at source level because this environment does not have a Solidity compiler/Foundry runtime.

## OpenZeppelin Contracts v5.6.1

The project pins `OpenZeppelin/openzeppelin-contracts@v5.6.1`.

Source review confirmed for that tag:

- Solidity baseline for `ERC1155.sol` is compatible with `pragma solidity ^0.8.24`.
- `ERC1155.setApprovalForAll(address,bool)` is `public virtual`.
- `ERC1155.isApprovedForAll(address,address)` is `public view virtual`.
- `ERC1155._update(...)` is `internal virtual`.
- `ERC1155Supply` and `ERC1155Pausable` both extend/override `_update`, matching the multiple-inheritance hook used in `FoxStylerItems`.
- `AccessControl.supportsInterface` remains virtual and compatible with the explicit `supportsInterface` override in `FoxStylerItems`.

These observations reduce API-drift risk but are **not a compiler result**.

## ERC-6551 reference v0.3.1

The project pins `erc6551/reference@v0.3.1`.

Source review confirmed:

- `IERC6551Account` interface ID is `0x6faff5f1`.
- `IERC6551Executable` interface ID is `0x51945447`.
- `execute(address,uint256,bytes,uint8)` matches the v0.3.1 executable interface.
- Registry `createAccount` and `account` signatures match the local `IERC6551Registry.sol` interface.
- The reference implementation reads the token-bound clone footer from offset `0x4d`, matching `FoxStylerAccount.token()`.

Before deployment, actual compilation against the pinned dependencies and direct chain registry verification are still mandatory.

## v0.3 reproducible compile target

The first real compile is pinned to Foundry `v1.7.1`, forge-std `v1.16.1`, Solidity `0.8.24`, OpenZeppelin Contracts `v5.6.1`, and ERC-6551 reference `v0.3.1`. See `DEPENDENCIES.lock` and `COMPILE_AND_TEST.md`.

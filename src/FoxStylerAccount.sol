// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

/// @notice ERC-6551 account implementation for one Fox Variable NFT.
/// @dev Designed to be deployed as the implementation behind the canonical ERC-6551 registry clone.
///      Only the CURRENT owner of the bound Fox is an authorized signer. ERC-721 approvals do not count.
contract FoxStylerAccount is IERC165, IERC1271, IERC721Receiver, IERC1155Receiver {
    error InvalidSigner();
    error UnsupportedOperation(uint8 operation);
    error ParentFoxCannotBeReceived();

    bytes4 private constant _ERC6551_ACCOUNT_INTERFACE_ID = 0x6faff5f1;
    bytes4 private constant _ERC6551_EXECUTABLE_INTERFACE_ID = 0x51945447;

    uint256 public state;

    receive() external payable {}

    /// @notice Execute a CALL as this Fox's Backpack.
    /// @dev operation=0 only. The current Fox owner must be msg.sender.
    function execute(address to, uint256 value, bytes calldata data, uint8 operation)
        external
        payable
        returns (bytes memory result)
    {
        if (msg.sender != owner()) revert InvalidSigner();
        if (operation != 0) revert UnsupportedOperation(operation);

        ++state;

        bool success;
        (success, result) = to.call{value: value}(data);
        if (!success) {
            assembly ("memory-safe") {
                revert(add(result, 0x20), mload(result))
            }
        }
    }

    /// @notice ERC-6551 token binding encoded by the registry clone footer.
    function token() public view returns (uint256 chainId, address tokenContract, uint256 tokenId) {
        bytes memory footer = new bytes(0x60);
        assembly ("memory-safe") {
            extcodecopy(address(), add(footer, 0x20), 0x4d, 0x60)
        }
        return abi.decode(footer, (uint256, address, uint256));
    }

    /// @notice Current owner of the bound Fox NFT.
    /// @dev Returns address(0) if the account is for another chain or the parent token no longer exists.
    function owner() public view returns (address) {
        (uint256 chainId, address tokenContract, uint256 tokenId) = token();
        if (chainId != block.chainid || tokenContract == address(0)) return address(0);

        try IERC721(tokenContract).ownerOf(tokenId) returns (address currentOwner) {
            return currentOwner;
        } catch {
            return address(0);
        }
    }

    /// @notice ERC-6551 signer validation. Only the CURRENT Fox owner is valid.
    function isValidSigner(address signer, bytes calldata) external view returns (bytes4) {
        return signer == owner() ? this.isValidSigner.selector : bytes4(0);
    }

    /// @notice ERC-1271 signature validation against the CURRENT Fox owner.
    function isValidSignature(bytes32 hash, bytes memory signature) external view returns (bytes4) {
        address currentOwner = owner();
        if (currentOwner != address(0) && SignatureChecker.isValidSignatureNow(currentOwner, hash, signature)) {
            return IERC1271.isValidSignature.selector;
        }
        return bytes4(0);
    }

    /// @dev Blocks safe-transfer of the parent Fox into its own Backpack.
    ///      Raw ERC-721 transferFrom can bypass receiver hooks, so the app must also prevent that UX path.
    function onERC721Received(address, address, uint256 receivedTokenId, bytes calldata)
        external
        view
        returns (bytes4)
    {
        (, address tokenContract, uint256 tokenId) = token();
        if (msg.sender == tokenContract && receivedTokenId == tokenId) revert ParentFoxCannotBeReceived();
        return IERC721Receiver.onERC721Received.selector;
    }

    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC1155Receiver.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        return IERC1155Receiver.onERC1155BatchReceived.selector;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == type(IERC1271).interfaceId
            || interfaceId == type(IERC721Receiver).interfaceId || interfaceId == type(IERC1155Receiver).interfaceId
            || interfaceId == _ERC6551_ACCOUNT_INTERFACE_ID || interfaceId == _ERC6551_EXECUTABLE_INTERFACE_ID;
    }
}

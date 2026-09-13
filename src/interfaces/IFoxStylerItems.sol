// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IFoxStylerItems {
    enum TransferPolicy {
        Transferable,
        FoxBound
    }

    struct ItemDefinition {
        bool registered;
        bool claimable;
        bool exchangeInputEligible;
        bool exchangeOutputEligible;
        bool frozen;
        TransferPolicy transferPolicy;
        uint256 maxSupply;
    }

    function itemDefinition(uint256 itemId) external view returns (ItemDefinition memory);

    function mintClaim(
        address to,
        uint256 itemId,
        uint256 amount,
        bytes32 claimId,
        bytes32 provenanceHash
    ) external;

    function exchangeBurn(address from, uint256 itemId, uint256 amount) external;
    function exchangeMint(address to, uint256 itemId, uint256 amount) external;
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";

import {FoxStylerAccount} from "../src/FoxStylerAccount.sol";
import {FoxStylerItems} from "../src/FoxStylerItems.sol";
import {FoxStylerClaims} from "../src/FoxStylerClaims.sol";

contract DeployCore is Script {
    bytes32 internal constant BACKPACK_SALT = keccak256("FOX_STYLER_BACKPACK_V1");

    function run() external {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(privateKey);
        address admin = vm.envAddress("ADMIN_MULTISIG");
        address rewardSigner = vm.envAddress("REWARD_SIGNER");
        address foxNft = vm.envAddress("FOX_NFT");
        address registry = vm.envAddress("ERC6551_REGISTRY");

        require(admin != address(0), "ADMIN_MULTISIG cannot be zero");
        require(admin != deployer, "ADMIN_MULTISIG must differ from deployer for safe handoff");
        require(rewardSigner != address(0), "REWARD_SIGNER cannot be zero");
        require(foxNft != address(0), "FOX_NFT cannot be zero");
        require(registry != address(0), "ERC6551_REGISTRY cannot be zero");

        vm.startBroadcast(privateKey);

        FoxStylerAccount accountImplementation = new FoxStylerAccount();
        FoxStylerItems items = new FoxStylerItems(deployer);
        FoxStylerClaims claims = new FoxStylerClaims(
            admin, rewardSigner, address(items), registry, address(accountImplementation), foxNft, BACKPACK_SALT
        );

        // Configure the stable item contract, then remove deployment-key admin authority.
        items.grantRole(items.CLAIMS_ROLE(), address(claims));
        items.grantRole(items.ITEM_REGISTRAR_ROLE(), admin);
        items.grantRole(items.METADATA_ROLE(), admin);
        items.grantRole(items.PAUSER_ROLE(), admin);
        items.grantRole(items.DEFAULT_ADMIN_ROLE(), admin);
        items.renounceRole(items.DEFAULT_ADMIN_ROLE(), deployer);

        vm.stopBroadcast();

        console2.log("FoxStylerAccount implementation:", address(accountImplementation));
        console2.log("FoxStylerItems:", address(items));
        console2.log("FoxStylerClaims:", address(claims));
        console2.log("Backpack salt:");
        console2.logBytes32(BACKPACK_SALT);
        console2.log("IMPORTANT: verify the ERC-6551 registry has code on this chain before production use.");
    }
}

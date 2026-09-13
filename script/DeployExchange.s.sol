// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {FoxExchange} from "../src/FoxExchange.sol";

contract DeployExchange is Script {
    bytes32 internal constant BACKPACK_SALT = keccak256("FOX_STYLER_BACKPACK_V1");

    function run() external {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address admin = vm.envAddress("ADMIN_MULTISIG");
        address exchangeSigner = vm.envAddress("EXCHANGE_SIGNER");
        address items = vm.envAddress("FOX_STYLER_ITEMS");
        address accountImplementation = vm.envAddress("FOX_STYLER_ACCOUNT_IMPLEMENTATION");
        address foxNft = vm.envAddress("FOX_NFT");
        address registry = vm.envAddress("ERC6551_REGISTRY");

        require(admin != address(0), "ADMIN_MULTISIG cannot be zero");
        require(exchangeSigner != address(0), "EXCHANGE_SIGNER cannot be zero");
        require(items != address(0), "FOX_STYLER_ITEMS cannot be zero");
        require(accountImplementation != address(0), "FOX_STYLER_ACCOUNT_IMPLEMENTATION cannot be zero");
        require(foxNft != address(0), "FOX_NFT cannot be zero");
        require(registry != address(0), "ERC6551_REGISTRY cannot be zero");

        vm.startBroadcast(privateKey);
        FoxExchange exchange = new FoxExchange(
            admin,
            exchangeSigner,
            items,
            registry,
            accountImplementation,
            foxNft,
            BACKPACK_SALT
        );
        vm.stopBroadcast();

        console2.log("FoxExchange:", address(exchange));
        console2.log("NEXT MULTISIG ACTION: grant FoxStylerItems.EXCHANGE_ROLE to this address.");
    }
}

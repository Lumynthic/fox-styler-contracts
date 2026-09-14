// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {MockFox} from "../test/mocks/MockFox.sol";
import {FoxStylerAccount} from "../src/FoxStylerAccount.sol";
import {FoxStylerItems} from "../src/FoxStylerItems.sol";
import {FoxStylerClaims} from "../src/FoxStylerClaims.sol";
import {FoxExchange} from "../src/FoxExchange.sol";
import {IFoxStylerItems} from "../src/interfaces/IFoxStylerItems.sol";

/// @notice Disposable testnet fixtures only. Never use these roles/items as production configuration.
contract DeployTestnetSandbox is Script {
    address internal constant REGISTRY = 0x000000006551c19487814612e58FE06813775758;
    bytes32 internal constant SALT = keccak256("FOX_STYLER_BACKPACK_V1");

    function run() external {
        require(block.chainid == 46630, "Robinhood testnet only");
        require(REGISTRY.code.length > 0, "Canonical registry missing");

        address deployer = vm.envAddress("TESTNET_DEPLOYER");
        address rewardSigner = vm.envAddress("TESTNET_REWARD_SIGNER");
        address exchangeSigner = vm.envAddress("TESTNET_EXCHANGE_SIGNER");
        require(deployer != address(0), "Zero deployer");
        require(rewardSigner != address(0) && exchangeSigner != address(0), "Zero signer");
        require(deployer != rewardSigner && deployer != exchangeSigner, "Use separate test signers");
        require(rewardSigner != exchangeSigner, "Use separate test signers");

        // The CLI selects the matching local keystore; no private key is read or logged by this script.
        vm.startBroadcast(deployer);
        MockFox fox = new MockFox();
        FoxStylerAccount implementation = new FoxStylerAccount();
        FoxStylerItems items = new FoxStylerItems(deployer);
        FoxStylerClaims claims = new FoxStylerClaims(
            deployer, rewardSigner, address(items), REGISTRY, address(implementation), address(fox), SALT
        );
        FoxExchange exchange = new FoxExchange(
            deployer, exchangeSigner, address(items), REGISTRY, address(implementation), address(fox), SALT
        );

        items.grantRole(items.CLAIMS_ROLE(), address(claims));
        items.grantRole(items.EXCHANGE_ROLE(), address(exchange));
        items.grantRole(items.ITEM_REGISTRAR_ROLE(), deployer);
        items.grantRole(items.METADATA_ROLE(), deployer);
        items.grantRole(items.PAUSER_ROLE(), deployer);

        // Arbitrary rehearsal economics, not approved gameplay balance.
        items.registerItem(
            1001, "ipfs://test-only/bowl.json", IFoxStylerItems.TransferPolicy.Transferable, true, true, false, 0
        );
        items.registerItem(
            5001,
            "ipfs://test-only/exchange-bowl.json",
            IFoxStylerItems.TransferPolicy.Transferable,
            false,
            false,
            true,
            0
        );
        items.registerItem(
            9001, "ipfs://test-only/relic.json", IFoxStylerItems.TransferPolicy.FoxBound, true, false, false, 0
        );
        exchange.configureRecipe(
            1,
            FoxExchange.Recipe({
                exists: true,
                enabled: true,
                inputItemId: 1001,
                inputAmount: 3,
                retainedAmount: 1,
                outputItemId: 5001,
                outputAmount: 1
            })
        );
        fox.mint(deployer, 101);
        fox.mint(deployer, 202);
        vm.stopBroadcast();

        console2.log("TEST ONLY: deployer retains sandbox administration", deployer);
        console2.log("MockFox", address(fox));
        console2.log("FoxStylerAccount", address(implementation));
        console2.log("FoxStylerItems", address(items));
        console2.log("FoxStylerClaims", address(claims));
        console2.log("FoxExchange", address(exchange));
        console2.log("Fox 101 Backpack (predicted, not yet created)", claims.accountFor(101));
        console2.log("Fox 202 Backpack (predicted, not yet created)", claims.accountFor(202));
    }
}

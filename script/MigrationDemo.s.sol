// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {ECDSAModule} from "../src/modules/ECDSAModule.sol";
import {HashBasedModule} from "../src/modules/HashBasedModule.sol";
import {PQAccount} from "../src/PQAccount.sol";
import {MigrationManager} from "../src/MigrationManager.sol";
import {RecoveryManager} from "../src/RecoveryManager.sol";

contract MigrationDemo is Script {
    function run() external {
        uint256 dpk = vm.envUint("PRIVATE_KEY");
        address dep = vm.addr(dpk);

        console2.log("=== Migration Demo: ECDSA -> PQ ===");
        console2.log("Dep:", dep);

        vm.startBroadcast(dpk);

        // Deploy modules
        ECDSAModule e = new ECDSAModule();
        HashBasedModule h = new HashBasedModule();

        // Account starting with ECDSA
        address[] memory g = new address[](2);
        g[0] = address(0xFEED); g[1] = address(0xBEEF);
        MigrationManager m = new MigrationManager(address(e), dep);
        RecoveryManager r = new RecoveryManager(dep, address(m), g, 2, 3 days);
        PQAccount a = new PQAccount(address(m), address(r));

        console2.log("Account:", address(a));
        console2.log("Before:", a.currentScheme());

        // Schedule migration
        m.scheduleMigration(address(h), m.MIN_MIGRATION_DELAY());
        (address pMod,) = m.getMigrationStatus();
        console2.log("Pending:", pMod);

        // Fund for later use
        payable(address(a)).transfer(0.05 ether);

        vm.stopBroadcast();

        console2.log("");
        console2.log("After 7 days, run:");
        console2.log("cast send", address(m), "executeMigration() --rpc-url arc_testnet --private-key YOUR_KEY");
        console2.log("Then:");
        console2.log("cast call", address(a), "currentScheme()(string) --rpc-url arc_testnet");
        console2.log("  -> should show: Hash-Based (Merkle-Simulated)");
    }
}

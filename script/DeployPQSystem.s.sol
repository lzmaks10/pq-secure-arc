// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {ECDSAModule} from "../src/modules/ECDSAModule.sol";
import {HashBasedModule} from "../src/modules/HashBasedModule.sol";
import {HybridModule} from "../src/modules/HybridModule.sol";
import {PQAccount} from "../src/PQAccount.sol";
import {MigrationManager} from "../src/MigrationManager.sol";
import {RecoveryManager} from "../src/RecoveryManager.sol";

contract DeployPQSystem is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address dep = vm.addr(pk);

        console2.log("=== PQ-Ready Account: Arc Testnet ===");
        console2.log("Chain:", block.chainid);
        console2.log("Dep:", dep);
        console2.log("Balance:", dep.balance);

        vm.startBroadcast(pk);

        // ------ Phase 1: Modules ------
        console2.log("--- Phase 1: Signature Modules ---");
        ECDSAModule e = new ECDSAModule();
        console2.log("ECDSA:", address(e));

        HashBasedModule h = new HashBasedModule();
        console2.log("Hash:", address(h));

        HybridModule hy = new HybridModule(address(e), address(h));
        console2.log("Hybrid:", address(hy));

        // ------ Phase 2: ECDSA Account ------
        console2.log("--- Phase 2: ECDSA Account ---");
        address[] memory g1 = new address[](3);
        g1[0] = address(0x1111); g1[1] = address(0x2222); g1[2] = address(0x3333);

        MigrationManager m1 = new MigrationManager(address(e), dep);
        console2.log("M1:", address(m1));

        RecoveryManager r1 = new RecoveryManager(dep, address(m1), g1, 2, 3 days);
        console2.log("R1:", address(r1));

        PQAccount a1 = new PQAccount(address(m1), address(r1));
        console2.log("A1:", address(a1));
        console2.log("  Scheme:", a1.currentScheme());
        console2.log("  PQ:", a1.isCurrentSchemeQuantumResistant());

        // ------ Phase 3: PQ Migration Demo ------
        console2.log("--- Phase 3: PQ Migration Demo ---");
        address[] memory g2 = new address[](2);
        g2[0] = address(0xAAAA); g2[1] = address(0xBBBB);

        MigrationManager m2 = new MigrationManager(address(e), dep);
        console2.log("M2:", address(m2));

        RecoveryManager r2 = new RecoveryManager(dep, address(m2), g2, 2, 3 days);
        console2.log("R2:", address(r2));

        PQAccount a2 = new PQAccount(address(m2), address(r2));
        console2.log("A2:", address(a2));
        console2.log("  Scheme:", a2.currentScheme());
        console2.log("  PQ:", a2.isCurrentSchemeQuantumResistant());

        // ------ Phase 4: Schedule Migration ------
        console2.log("--- Phase 4: Schedule ECDSA -> HashBased ---");
        m2.scheduleMigration(address(h), m2.MIN_MIGRATION_DELAY());

        (address pm,) = m2.getMigrationStatus();
        console2.log("  Pending:", pm);
        console2.log("  (7d timelock -> executeMigration)");

        vm.stopBroadcast();

        console2.log("");
        console2.log("=== SUMMARY ===");
        console2.log("ECDSA:", address(e));
        console2.log("Hash:", address(h));
        console2.log("Hybrid:", address(hy));
        console2.log("A1:", address(a1));
        console2.log("  M1:", address(m1));
        console2.log("  R1:", address(r1));
        console2.log("A2:", address(a2));
        console2.log("  M2:", address(m2));
        console2.log("  R2:", address(r2));
    }
}

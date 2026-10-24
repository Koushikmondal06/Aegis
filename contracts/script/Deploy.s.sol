// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Script, console2 } from "forge-std/Script.sol";
import { IEntryPoint } from "@account-abstraction/interfaces/IEntryPoint.sol";
import { AegisFactory } from "../src/AegisFactory.sol";
import { AegisPaymaster } from "../src/AegisPaymaster.sol";

/// @notice Deploys Aegis-owned contracts against an already verified EntryPoint v0.8.
/// @dev The script never deploys or substitutes an EntryPoint. Its address and bytecode
///      must be verified separately for the target network before this script is run.
contract Deploy is Script {
    function run() external returns (AegisFactory factory, AegisPaymaster paymaster) {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address entryPoint = vm.envAddress("ENTRY_POINT_ADDRESS");
        address paymasterAdmin = vm.envAddress("PAYMASTER_ADMIN");
        address sponsorSigner = vm.envAddress("SPONSOR_SIGNER");
        uint256 paymasterBudget = vm.envUint("PAYMASTER_BUDGET");

        vm.startBroadcast(deployerKey);
        factory = new AegisFactory(IEntryPoint(entryPoint));
        paymaster = new AegisPaymaster(
            IEntryPoint(entryPoint), paymasterAdmin, sponsorSigner, paymasterBudget
        );
        vm.stopBroadcast();

        console2.log("EntryPoint", entryPoint);
        console2.log("AegisFactory", address(factory));
        console2.log("AegisPaymaster", address(paymaster));
    }
}

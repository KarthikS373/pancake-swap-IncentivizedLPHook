// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Script.sol";

import {IncentivizedLPHook} from "../src/pool-cl/IncentivizedLPHook.sol";
import {MockCLPoolManager} from "../test/pool-cl/IncentivizedLPHook.t.sol";

import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

contract DeployScript is Script {
    function run() external {
        vm.startBroadcast();

        // Deploy mock tokens
        MockERC20 currency0 = new MockERC20("Token0", "TK0", 18);
        MockERC20 currency1 = new MockERC20("Token1", "TK1", 18);
        MockERC20 brevisToken = new MockERC20("Brevis", "BREVIS", 18);

        // Deploy mock pool manager
        MockCLPoolManager poolManager = new MockCLPoolManager();

        // Deploy the IncentivizedLPHook
        IncentivizedLPHook hook = new IncentivizedLPHook(
            ICLPoolManager(address(poolManager)),
            address(brevisToken)
        );

        vm.stopBroadcast();

        // Output addresses
        console.log("Currency0:", address(currency0));
        console.log("Currency1:", address(currency1));
        console.log("BrevisToken:", address(brevisToken));
        console.log("PoolManager:", address(poolManager));
        console.log("IncentivizedLPHook:", address(hook));
    }
}

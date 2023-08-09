// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";

contract DeployDSCEngine is Script {
    DSCEngine dscEngine;
    DecentralizedStableCoin dsCoin;

    function run() external returns (DSCEngine) {
        dsCoin = new DecentralizedStableCoin();
        vm.startBroadcast();
        // dscEngine = new DSCEngine();
        vm.stopBroadcast();
        return dscEngine;
    }
}

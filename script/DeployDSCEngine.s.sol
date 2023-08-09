// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployDSCEngine is Script {
    DSCEngine dscEngine;
    DecentralizedStableCoin dsCoin;
    HelperConfig helperConfig;

    address weth;
    address wbtc;
    address wethUsdPriceFeed;
    address wbtcUsdPriceFeed;
    uint256 deployerKey;

    address[] private tokenAddresses;
    address[] private priceFeedAddresses;

    function run() external returns (DSCEngine, DecentralizedStableCoin, HelperConfig) {
        dsCoin = new DecentralizedStableCoin();
        helperConfig = new HelperConfig();
        (weth, wbtc, wethUsdPriceFeed, wbtcUsdPriceFeed, deployerKey) = helperConfig.activeNetworkConfig();

        tokenAddresses.push(weth);
        tokenAddresses.push(wbtc);

        priceFeedAddresses.push(wethUsdPriceFeed);
        priceFeedAddresses.push(wbtcUsdPriceFeed);

        vm.startBroadcast();
        dscEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsCoin));
        vm.stopBroadcast();
        return (dscEngine, dsCoin, helperConfig);
    }
}

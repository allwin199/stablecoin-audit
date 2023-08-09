// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        address weth;
        address wbtc;
        address wethUsdPriceFeed;
        address wbtcUsdPriceFeed;
        uint256 deployerKey;
    }

    NetworkConfig public activeNetworkConfig;

    uint8 public constant DECIMALS = 8;
    int256 public constant ETH_USD_PRICE = 2000e8;
    int256 public constant BTC_USD_PRICE = 1000e8;

    constructor() {
        if (block.chainid == 11155111) {
            // activeNetworkConfig = sepoliaConfig();
        } else {
            activeNetworkConfig = anvilConfig();
        }
    }

    function sepoliaConfig() public returns (NetworkConfig memory) {
        // return NetworkConfig({
        //      weth =
        //  wbtc;
        //  wethUsdPriceFeed;
        //  wbtcUsdPriceFeed;
        //  deployerKey;
        // })
    }

    function anvilConfig() public returns (NetworkConfig memory) {
        if (activeNetworkConfig.weth != address(0)) {
            return activeNetworkConfig;
        }

        vm.startBroadcast();

        ERC20Mock wethMock = new ERC20Mock();
        MockV3Aggregator ethUsdPriceFeed = new MockV3Aggregator(DECIMALS,
            ETH_USD_PRICE);

        ERC20Mock wbtcMock = new ERC20Mock();
        MockV3Aggregator btcUsdPriceFeed = new MockV3Aggregator(
            DECIMALS,
            BTC_USD_PRICE
        );

        vm.stopBroadcast();

        return NetworkConfig({
            weth: address(wethMock),
            wbtc: address(wbtcMock),
            wethUsdPriceFeed: address(ethUsdPriceFeed),
            wbtcUsdPriceFeed: address(btcUsdPriceFeed),
            deployerKey: vm.envUint("PRIVATE_KEY")
        });
    }
}

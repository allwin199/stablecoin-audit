// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

// This contract will contain our invariant aka properties

// What are our invariants?

// 1. The total supply of DSC should be less than the total value of collateral
// 2. Getter view functions should never revert

import {Test, console2} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";

import {Handler} from "./Handler.t.sol";
import {DeployDSCEngine} from "../../script/DeployDSCEngine.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract OpenInvariantsTest is StdInvariant, Test {
    DSCEngine public dscEngine;
    DecentralizedStableCoin public dsCoin;
    HelperConfig public helperConfig;

    address public weth;
    address public wbtc;
    address public ethUsdPriceFeed;
    address public btcUsdPriceFeed;
    uint256 public deployerKey;
    Handler handler;

    address public user = address(1);
    uint256 public constant STARTING_USER_BALANCE = 10e18;

    function setUp() public {
        DeployDSCEngine deployer = new DeployDSCEngine();
        (dscEngine, dsCoin, helperConfig) = deployer.run();
        (weth, wbtc, ethUsdPriceFeed, btcUsdPriceFeed, deployerKey) = helperConfig.activeNetworkConfig();
        if (block.chainid == 31337) {
            vm.deal(user, STARTING_USER_BALANCE);
        }

        // targeted contract
        // targetContract(address(dscEngine));
        // if we say target contract as dscEngine, then fuzz will call the functions randomly
        // for eg, redeemCollateral can be called before depositCollateral
        // so address this, we have to create a handler
        handler = new Handler(dscEngine, dsCoin);

        targetContract(address(handler));
    }

    function invariant_ProtocolMustHave_MoreValue_ThanDSC() public {
        // get the value of all the collateral in the protocol
        // compare it to all the debt (DSC)

        uint256 totalSupployOfDSC = dsCoin.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dscEngine));
        uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(dscEngine));

        uint256 wethValue = dscEngine.getUsdValue(weth, totalWethDeposited);
        uint256 wbtcValue = dscEngine.getUsdValue(wbtc, totalWbtcDeposited);

        console2.log("wethValue", wethValue);
        console2.log("wbtcValue", wbtcValue);
        console2.log("totalSupployOfDSC", totalSupployOfDSC);

        assertGe(wethValue + wbtcValue, totalSupployOfDSC);
    }

    function invariant_gettersShouldNotRevert() public view {
        dscEngine.getLiquidationThreshold();
        dscEngine.getAdditionalFeedPrecision();
    }
}

// for open based testing, keep fail_on_revert as false

// forge inspect DSCEngine methods
// to get all the methods

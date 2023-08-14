// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

// Handler is going to narrow down the way we call function

import {Test, console2, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";

import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

contract Handler is Test {
    DSCEngine public dscEngine;
    DecentralizedStableCoin public dsCoin;
    HelperConfig public helperConfig;
    ERC20Mock weth;
    ERC20Mock wbtc;

    uint96 public constant MAX_DEPOSIT_SIZE = type(uint96).max;
    address[] public usersWithCollateralDeposited;

    constructor(DSCEngine _dscEngine, DecentralizedStableCoin _dsCoin) {
        dscEngine = _dscEngine;
        dsCoin = _dsCoin;

        address[] memory collateralTokens = dscEngine.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);
    }

    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollaterlFromSeed(collateralSeed);

        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(dscEngine), amountCollateral);
        dscEngine.depositCollateral(address(collateral), amountCollateral);
        usersWithCollateralDeposited.push(msg.sender);
        vm.stopPrank();
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollaterlFromSeed(collateralSeed);

        uint256 wethBalanceOfUser = dscEngine.getCollateralBalanceOfUser(msg.sender, address(weth));
        // uint256 wbtcBalanceOfUser = dscEngine.getCollateralBalanceOfUser(msg.sender, address(wbtc));

        uint256 maxCollateralToRedeem = wethBalanceOfUser;
        // user can only redeem the max collateral deposited

        amountCollateral = bound(amountCollateral, 0, maxCollateralToRedeem);

        if (amountCollateral == 0) {
            return;
        }

        dscEngine.redeemCollateral(address(collateral), amountCollateral);
    }

    function mintDSC(uint256 amountDSCToMint, uint256 addressSeed) public {
        uint256 usersLength = usersWithCollateralDeposited.length;
        if (usersLength == 0) {
            return;
        }
        uint256 userIndex = addressSeed % usersLength;
        address sender = usersWithCollateralDeposited[userIndex];

        (uint256 totalDSCMinted, uint256 collateralValueInUsd) = dscEngine.getAccountInformation(sender);

        int256 maxDSCToMint = (int256(collateralValueInUsd) / 2) - int256(totalDSCMinted);

        if (maxDSCToMint < 0) {
            return;
        }

        amountDSCToMint = bound(amountDSCToMint, 0, uint256(maxDSCToMint));

        if (amountDSCToMint == 0) {
            console.log("amountDSCToMint", amountDSCToMint);
            return;
        }

        vm.startPrank(sender);
        dscEngine.mintDSC(MAX_DEPOSIT_SIZE);
        vm.stopPrank();
    }

    // Helper Functions
    function _getCollaterlFromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        } else {
            return wbtc;
        }
    }
}

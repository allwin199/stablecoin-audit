// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console2} from "forge-std/Test.sol";
import {DeployDSCEngine} from "../../script/DeployDSCEngine.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockFailedTransferFrom} from "../mocks/MockFailedTransferFrom.sol";
import {MockFailedTransfer} from "../mocks/MockFailedTransfer.sol";
import {MockFailedMintDSC} from "../mocks/MockFailedMintDSC.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract DSCEngineTest is Test {
    DSCEngine public dscEngine;
    DecentralizedStableCoin public dsCoin;
    HelperConfig public helperConfig;

    address public weth;
    address public wbtc;
    address public ethUsdPriceFeed;
    address public btcUsdPriceFeed;
    uint256 public deployerKey;

    address public user = address(1);
    uint256 public constant STARTING_USER_BALANCE = 10e18;
    uint256 public constant AMOUNT_COLLATERAL = 10e18;
    uint256 public constant AMOUNT_DSC_To_Mint = 100e18;

    function setUp() public {
        DeployDSCEngine deployer = new DeployDSCEngine();
        (dscEngine, dsCoin, helperConfig) = deployer.run();
        (weth, wbtc, ethUsdPriceFeed, btcUsdPriceFeed, deployerKey) = helperConfig.activeNetworkConfig();
        if (block.chainid == 31337) {
            vm.deal(user, STARTING_USER_BALANCE);
        }

        /// @dev user should have some balance.
        ERC20Mock(weth).mint(user, STARTING_USER_BALANCE);
        ERC20Mock(wbtc).mint(user, STARTING_USER_BALANCE);
    }

    /*/////////////////////////////////////////////////////////////////////////////
                                    EVENTS
    /////////////////////////////////////////////////////////////////////////////*/
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event DSCMinted(address indexed user, uint256 indexed amount);
    event DSCBurned(address indexed user, uint256 indexed amount);
    event CollateralRedeemed(
        address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount
    );

    /*/////////////////////////////////////////////////////////////////////////////
                                CONSTRUCTOR TESTS
    /////////////////////////////////////////////////////////////////////////////*/
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function test_RevertsIf_TokenAddressesAnd_PriceFeedAddresses_HasDifferentLength() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddresses_PriceFeedAddresses_DifferentLength.selector);
        new DSCEngine(tokenAddresses,priceFeedAddresses,address(dsCoin));
    }

    function test_RevertsIf_DSCoin_IsZeroAddress() public {
        tokenAddresses.push(weth);
        tokenAddresses.push(wbtc);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__DSCoinIs_NotAValidAddress.selector);
        new DSCEngine(tokenAddresses,priceFeedAddresses,address(0));
    }

    /*/////////////////////////////////////////////////////////////////////////////
                                PRICEFEED TESTS
    /////////////////////////////////////////////////////////////////////////////*/
    function test_GetUsdValue() public {
        uint256 ethAmount = 15e18;
        uint256 priceFeedValue = dscEngine.getUsdValue(weth, ethAmount);
        uint256 expectedValue = 30000e18; // (15e18*2000e18)/1e18 = 30000e18
        assertEq(priceFeedValue, expectedValue, "getUsdValue");
    }

    function test_GetTokenAmount_FromUsd() public {
        uint256 ethAmount = 15e18;
        uint256 priceFeedValue = dscEngine.getUsdValue(weth, ethAmount);
        uint256 expectedValue = dscEngine.getTokenAmountFromUsd(weth, priceFeedValue);
        assertEq(expectedValue, ethAmount, "getTokenAmountFromUsd");
    }

    /*/////////////////////////////////////////////////////////////////////////////
                                DEPOSIT COLLATERAL TESTS
    /////////////////////////////////////////////////////////////////////////////*/
    function test_RevertsIf_CollateralAmount_IsZero() public {
        vm.startPrank(user);

        vm.expectRevert(DSCEngine.DSCEngine__ZeroAmount.selector);
        dscEngine.depositCollateral(weth, 0);

        vm.stopPrank();
    }

    function test_RevertsIf_CollateralToken_IsNotAllowed() public {
        ERC20Mock testToken = new ERC20Mock();
        vm.startPrank(user);

        /// While deploying this contract, we create a weth and wbtc mock and told the contract those are the only two
        /// accepted tokenAddresses, if we use anyother address, it should revert
        vm.expectRevert(DSCEngine.DSCEngine__TokenNotAllowed.selector);
        dscEngine.depositCollateral(address(testToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function test_UserCan_DepositCollateral_UpdatesBalance() public {
        vm.startPrank(user);

        /// @dev inside the setup fn, we are minting erc20 token for the user
        // ERC20Mock(weth).mint(user, STARTING_USER_BALANCE);
        // now user has some erc20 balance of weth token
        // when we call the deposit collateral
        // we have transferFrom fn inside it
        // IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        // dscEngine will be making the above call
        // for dscEngine to make the above call, user have to approve that

        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);

        // since the user has approved that, address(dscEngine) can spend behalf of the user,
        // dscEngine can do transferFrom

        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);

        vm.stopPrank();

        uint256 userCollateralBalance = dscEngine.getCollateralBalanceOfUser(user, weth);
        assertEq(userCollateralBalance, AMOUNT_COLLATERAL, "despositCollateral");
    }

    modifier depositedCollateral() {
        vm.startPrank(user);

        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);

        vm.stopPrank();

        _;
    }

    function test_UserCan_DepositCollateral_AndGet_AccountInfo() public depositedCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine.getAccountInformation(user);
        uint256 collateralDeposited = dscEngine.getTokenAmountFromUsd(weth, collateralValueInUsd);

        assertEq(totalDscMinted, 0, "despositCollateral");
        assertEq(collateralDeposited, AMOUNT_COLLATERAL, "depositCollateral");
    }

    function test_UserCan_DepositCollateral_EmitsEvent() public {
        vm.startPrank(user);

        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);

        vm.expectEmit({emitter: address(dscEngine)});
        emit CollateralDeposited(user, weth, AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);

        vm.stopPrank();
    }

    /// @dev this fn needs it own setup
    function test_RevertsIf_CollateralDepositing_Failed() public {
        // instead of weth, we creating a mockWeth
        MockFailedTransferFrom mockWeth = new MockFailedTransferFrom();

        tokenAddresses = [address(mockWeth)];
        priceFeedAddresses = [ethUsdPriceFeed];

        DSCEngine mockDSCEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(mockWeth));

        // since it is a new mockWeth, we have to mint some balance for the user
        ERC20Mock(address(mockWeth)).mint(user, STARTING_USER_BALANCE);

        vm.startPrank(user);

        // this Weth will be transferedFrom, user to dscEngine
        // this transfer will be performed by dscEngine
        // so the user has to approve, that dscEngine can spend on behalf of the user
        ERC20Mock(address(mockWeth)).approve(address(mockDSCEngine), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__Collateral_DepositingFailed.selector);
        mockDSCEngine.depositCollateral(address(mockWeth), AMOUNT_COLLATERAL);

        vm.stopPrank();
    }

    /*/////////////////////////////////////////////////////////////////////////////
                                    MINT DSC TESTS
    /////////////////////////////////////////////////////////////////////////////*/
    function test_RevertsIf_MintingWith_ZeroAmount() public {
        vm.startPrank(user);

        vm.expectRevert(DSCEngine.DSCEngine__ZeroAmount.selector);
        dscEngine.mintDSC(0);

        vm.stopPrank();
    }

    function test_RevertsIf_UserMintDSC_WithoutCollateral() public {
        vm.startPrank(user);

        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, 0));
        dscEngine.mintDSC(AMOUNT_DSC_To_Mint);

        vm.stopPrank();
    }

    function test_RevertsIf_UserMintDSC_MoreThanCollateral() public depositedCollateral {
        vm.startPrank(user);

        vm.expectRevert();
        dscEngine.mintDSC(AMOUNT_DSC_To_Mint * 10e18);

        // Amount Collateral = 10e18
        // amountCollaterlInUsd = 20000e18
        // AMOUNT_DSC_To_Mint = 100e18*10e18 = 1000e36
        // user should be 200% overcollateralized, but here user is undercollateralized
        // so it will break the MIN_HEALTH_FACTOR and it will revert

        vm.stopPrank();
    }

    function test_RevertsIf_MintDSC_BreaksHelathFactor() public depositedCollateral {
        uint256 amountToMint = dscEngine.getUsdValue(weth, AMOUNT_COLLATERAL);

        vm.startPrank(user);

        uint256 healthFactor =
            dscEngine.calculateHealthFactor(amountToMint, dscEngine.getUsdValue(weth, AMOUNT_COLLATERAL));

        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, healthFactor));
        dscEngine.mintDSC(amountToMint);

        vm.stopPrank();
    }

    modifier mintedDSC() {
        vm.startPrank(user);

        dscEngine.mintDSC(AMOUNT_DSC_To_Mint);

        vm.stopPrank();

        _;
    }

    function test_UserCan_MintDSC_UpdatesBalance() public depositedCollateral mintedDSC {
        uint256 expectedBalance = dsCoin.balanceOf(user);
        assertEq(expectedBalance, AMOUNT_DSC_To_Mint, "mintDSC");
    }

    function test_UserCan_MintDSC_GetAccountInfo() public depositedCollateral mintedDSC {
        (uint256 totalDscMinted,) = dscEngine.getAccountInformation(user);
        assertEq(totalDscMinted, AMOUNT_DSC_To_Mint, "mintDSC");
    }

    function test_UserCan_MintDSC_EmitsEvent() public depositedCollateral {
        vm.startPrank(user);

        vm.expectEmit({emitter: address(dscEngine)});
        emit DSCMinted(user, AMOUNT_DSC_To_Mint);
        dscEngine.mintDSC(AMOUNT_DSC_To_Mint);

        vm.stopPrank();
    }

    // this test needs its own setup
    function test_RevertsIf_MintDSC_Failed() public {
        MockFailedMintDSC mockDSCoin = new MockFailedMintDSC();

        tokenAddresses = [weth];
        priceFeedAddresses = [ethUsdPriceFeed];

        DSCEngine mockDSCEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(mockDSCoin));

        mockDSCoin.transferOwnership(address(mockDSCEngine));

        vm.startPrank(user);

        ERC20Mock(weth).approve(address(mockDSCEngine), AMOUNT_COLLATERAL);
        mockDSCEngine.depositCollateral(weth, AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__Minting_Failed.selector);
        mockDSCEngine.mintDSC(AMOUNT_DSC_To_Mint);

        vm.stopPrank();
    }

    /*/////////////////////////////////////////////////////////////////////////////
                        DEPOSIT COLLATERAL AND MINT DSC TESTS
    /////////////////////////////////////////////////////////////////////////////*/

    modifier despositedCollateralAndMintedDSC() {
        vm.startPrank(user);

        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.despositCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, AMOUNT_DSC_To_Mint);

        vm.stopPrank();

        _;
    }

    function test_UserCan_DepositCollateral_AndMintDSC_InOneTransaction() public despositedCollateralAndMintedDSC {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine.getAccountInformation(user);

        assertEq(totalDscMinted, AMOUNT_DSC_To_Mint, "depositCollateralAndMintDSC");
        assertEq(collateralValueInUsd, dscEngine.getUsdValue(weth, AMOUNT_COLLATERAL), "depositCollateralAndMintDSC");
    }

    function test_UserCan_DepositCollateral_AndMintDSC_UpdatesBalance() public despositedCollateralAndMintedDSC {
        uint256 expectedBalance = dsCoin.balanceOf(user);

        assertEq(expectedBalance, AMOUNT_DSC_To_Mint, "depositCollateralAndMintDSC");
    }

    /*/////////////////////////////////////////////////////////////////////////////
                                    BURN DSC TESTS
    /////////////////////////////////////////////////////////////////////////////*/
    function test_RevertsIf_BurnDSC_ZeroAmount() public {
        vm.startPrank(user);

        vm.expectRevert(DSCEngine.DSCEngine__ZeroAmount.selector);
        dscEngine.burnDSC(0);

        vm.stopPrank();
    }

    function test_RevertsIf_BurnDSCAmount_ExceedsMintedDSC() public despositedCollateralAndMintedDSC {
        vm.startPrank(user);

        vm.expectRevert(DSCEngine.DSCEngine__DSCBurnAmount_ExceedsBalance.selector);
        dscEngine.burnDSC(AMOUNT_DSC_To_Mint * 2e18);

        vm.stopPrank();
    }

    function test_UserCan_BurnDSC() public despositedCollateralAndMintedDSC {
        vm.startPrank(user);

        dsCoin.approve(address(dscEngine), AMOUNT_DSC_To_Mint);
        // dscCoin has all the mintedDSC
        // dscEngine is responsible for burning the DSC
        // dsCoin has to give approval to the dscEngine, that dscEngine can transfer dsc from dscCoin to dscEngine
        dscEngine.burnDSC(AMOUNT_DSC_To_Mint);

        vm.stopPrank();

        uint256 expectedBalance = dsCoin.balanceOf(user);

        assertEq(expectedBalance, 0, "burnDSC");
    }

    function test_UserCan_BurnDSC_UpdatesAccountInfo() public despositedCollateralAndMintedDSC {
        vm.startPrank(user);

        dsCoin.approve(address(dscEngine), AMOUNT_DSC_To_Mint);
        dscEngine.burnDSC(AMOUNT_DSC_To_Mint);

        vm.stopPrank();

        (uint256 totalDscMinted,) = dscEngine.getAccountInformation(user);

        assertEq(totalDscMinted, 0, "burnDSC");
    }

    function test_UserCan_BurnDSC_EmitsEvent() public despositedCollateralAndMintedDSC {
        vm.startPrank(user);

        dsCoin.approve(address(dscEngine), AMOUNT_DSC_To_Mint);

        vm.expectEmit({emitter: address(dscEngine)});
        emit DSCBurned(user, AMOUNT_DSC_To_Mint);
        dscEngine.burnDSC(AMOUNT_DSC_To_Mint);

        vm.stopPrank();
    }

    /*/////////////////////////////////////////////////////////////////////////////
                                    REDEEM COLLATERAL TESTS
    /////////////////////////////////////////////////////////////////////////////*/
    function test_RevertsIf_RedeemCollateral_ZeroAmount() public {
        vm.startPrank(user);

        vm.expectRevert(DSCEngine.DSCEngine__ZeroAmount.selector);
        dscEngine.redeemCollateral(weth, 0);

        vm.stopPrank();
    }

    function test_RevertsIf_RedeemCollateral_NotTokenAllowed() public {
        ERC20Mock testToken = new ERC20Mock();
        vm.startPrank(user);

        vm.expectRevert(DSCEngine.DSCEngine__TokenNotAllowed.selector);
        dscEngine.redeemCollateral(address(testToken), AMOUNT_COLLATERAL);

        vm.stopPrank();
    }

    function test_UserCan_RedeemCollateral_UpdatesAccountInfo() public depositedCollateral {
        vm.startPrank(user);

        dscEngine.redeemCollateral(weth, AMOUNT_COLLATERAL);

        vm.stopPrank();

        uint256 expectedBalance = dscEngine.getCollateralBalanceOfUser(user, weth);

        assertEq(expectedBalance, 0, "redeemCollateral");
    }

    function test_UserCan_RedeemCollateral_EmitsEvent() public depositedCollateral {
        vm.startPrank(user);

        vm.expectEmit({emitter: address(dscEngine)});
        emit CollateralRedeemed(user, user, weth, AMOUNT_COLLATERAL);
        dscEngine.redeemCollateral(weth, AMOUNT_COLLATERAL);

        vm.stopPrank();
    }

    function test_RevertsIf_RedeemCollateral_TransferFailed() public {
        MockFailedTransfer mockWeth = new MockFailedTransfer();

        tokenAddresses = [address(mockWeth)];
        priceFeedAddresses = [ethUsdPriceFeed];

        DSCEngine mockDSCEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(mockWeth));

        ERC20Mock(address(mockWeth)).mint(user, STARTING_USER_BALANCE);

        vm.startPrank(user);

        ERC20Mock(address(mockWeth)).approve(address(mockDSCEngine), AMOUNT_COLLATERAL);

        mockDSCEngine.depositCollateral(address(mockWeth), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__RedeemCollateral_TransferFailed.selector);
        mockDSCEngine.redeemCollateral(address(mockWeth), AMOUNT_COLLATERAL);

        vm.stopPrank();
    }

    /*/////////////////////////////////////////////////////////////////////////////
                            REDEEM COLLATERAL AND BURN DSC TESTS
    /////////////////////////////////////////////////////////////////////////////*/
    function test_UserCan_RedeemCollateral_BurnDSC_InOneTransaction() public despositedCollateralAndMintedDSC {
        vm.startPrank(user);

        dsCoin.approve(address(dscEngine), AMOUNT_DSC_To_Mint);

        dscEngine.redeemCollateralAndBurnDSC(weth, AMOUNT_COLLATERAL, AMOUNT_DSC_To_Mint);

        vm.stopPrank();

        uint256 userBalance = dsCoin.balanceOf(user);
        assertEq(userBalance, 0, "redeemCollateralForDSC");

        uint256 expectedBalance = dscEngine.getCollateralBalanceOfUser(user, weth);
        assertEq(expectedBalance, 0, "redeemCollateral");
    }

    /*/////////////////////////////////////////////////////////////////////////////
                                HEALTH FACTOR TESTS
    /////////////////////////////////////////////////////////////////////////////*/
    function test_ProperlyReports_HealthFactor() public despositedCollateralAndMintedDSC {
        uint256 healthFactor = dscEngine.getHealthFactor(user);

        // collateralValueInUsd = 20000e18
        // totalDSCMinted = 100e18
        // uint256 collateralAdjustedForThreshold =
        // ((collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION);
        // (20000e18 * 50)/100 = 10000e18
        // return ((collateralAdjustedForThreshold * PRECISION) / totalDSCMinted);
        // (10000e18 * 1e18) / 100e18 = 100e18

        assertEq(healthFactor, 100e18, "healthFactor");
    }

    function test_HealthFactor_CanGo_BelowOne() public despositedCollateralAndMintedDSC {
        int256 ethUsdUpdatedPrice = 18e8;
        // previously 1eth was 2000e8, now 18e8

        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);

        // collateralValueInUsd = 180e18
        // totalDSCMinted = 100e18
        // uint256 collateralAdjustedForThreshold =
        // ((collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION);
        // (180e18 * 50)/100 = 90e18
        // return ((collateralAdjustedForThreshold * PRECISION) / totalDSCMinted);
        // (90e18 * 1e18) / 100e18 = 0.9e18

        uint256 healthFactor = dscEngine.getHealthFactor(user);

        assertEq(healthFactor, 0.9e18);
    }
}

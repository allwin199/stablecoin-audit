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
    uint256 public constant STARTING_USER_BALANCE = 10 ether;
    uint256 public constant AMOUNT_COLLATERAL = 10e18;
    uint256 public constant AMOUNT_DSC_To_Mint = 100e18;

    function setUp() public {
        DeployDSCEngine deployer = new DeployDSCEngine();
        (dscEngine, dsCoin, helperConfig) = deployer.run();
        (weth, wbtc, ethUsdPriceFeed, btcUsdPriceFeed, deployerKey) = helperConfig.activeNetworkConfig();
        if (block.chainid == 31337) {
            vm.deal(user, STARTING_USER_BALANCE);
        }

        ERC20Mock(weth).mint(user, STARTING_USER_BALANCE);
        ERC20Mock(wbtc).mint(user, STARTING_USER_BALANCE);
    }

    /*/////////////////////////////////////////////////////////////////////////////
                                    EVENTS
    /////////////////////////////////////////////////////////////////////////////*/
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);

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
        assertEq(priceFeedValue, expectedValue);
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
        vm.expectRevert(DSCEngine.DSCEngine__TokenNotAllowed.selector);
        dscEngine.depositCollateral(address(testToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    modifier depositedCollateral() {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function test_userCan_DepositCollateral_WithoutMinting() public depositedCollateral {
        uint256 userBalance = dsCoin.balanceOf(user);
        assertEq(userBalance, 0);
    }

    function test_userCan_DepositCollateral_UpdatesBalance() public depositedCollateral {
        uint256 userBalance = dscEngine.getCollateralBalanceOfUser(user, weth);
        assertEq(userBalance, AMOUNT_COLLATERAL);
    }

    function test_userCan_DepositCollateral_EmitsEvent() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        vm.expectEmit({emitter: address(dscEngine)});
        emit CollateralDeposited(user, weth, AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    /// @dev this test needs it's own setup
    // function test_RevertsIf_TransferFromFails() public {
    //     // Arrange - Setup
    //     address owner = msg.sender;
    //     vm.prank(owner);
    //     MockFailedTransferFrom mockDsc = new MockFailedTransferFrom();
    //     tokenAddresses = [address(mockDsc)];
    //     priceFeedAddresses = [ethUsdPriceFeed];
    //     vm.prank(owner);
    //     DSCEngine mockDsce = new DSCEngine(
    //         tokenAddresses,
    //         priceFeedAddresses,
    //         address(mockDsc)
    //     );
    //     mockDsc.mint(user, AMOUNT_COLLATERAL);

    //     vm.prank(owner);
    //     mockDsc.transferOwnership(address(mockDsce));
    //     // Arrange - User
    //     vm.startPrank(user);
    //     ERC20Mock(address(mockDsc)).approve(address(mockDsce), AMOUNT_COLLATERAL);
    //     // Act / Assert
    //     vm.expectRevert(DSCEngine.DSCEngine__Collateral_DepositingFailed.selector);
    //     mockDsce.depositCollateral(address(mockDsc), AMOUNT_COLLATERAL);
    //     vm.stopPrank();
    // }

    // this test needs its own setup
    function test_RevertsIf_TransferFromFails() public {
        // Arrange - Setup
        // instead of dsCoin, we are creating a mock
        MockFailedTransferFrom mockDsCoin = new MockFailedTransferFrom();

        tokenAddresses = [address(mockDsCoin)];
        priceFeedAddresses = [ethUsdPriceFeed];

        DSCEngine mockDscEngine = new DSCEngine(
            tokenAddresses,
            priceFeedAddresses,
            address(mockDsCoin)
        );

        mockDsCoin.mint(user, AMOUNT_COLLATERAL);

        // Arrange - User
        vm.startPrank(user);

        ERC20Mock(address(mockDsCoin)).approve(address(mockDscEngine), AMOUNT_COLLATERAL);
        // Act / Assert
        vm.expectRevert(DSCEngine.DSCEngine__Collateral_DepositingFailed.selector);
        mockDscEngine.depositCollateral(address(mockDsCoin), AMOUNT_COLLATERAL);

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

    function test_RevertIf_MintDSC_BreaksHealthFactor() public {
        uint256 collateralAmount = 0;
        uint256 userHealthFactor = dscEngine.calculateHealthFactor(AMOUNT_DSC_To_Mint, collateralAmount);

        vm.startPrank(user);

        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, userHealthFactor));
        dscEngine.mintDSC(AMOUNT_DSC_To_Mint);

        vm.stopPrank();
    }

    function test_UserCan_MintDSC() public depositedCollateral {
        vm.startPrank(user);

        dscEngine.mintDSC(AMOUNT_DSC_To_Mint);

        (uint256 userBalance,) = dscEngine.getAccountInformation(user);

        assertEq(userBalance, AMOUNT_DSC_To_Mint);
        vm.stopPrank();
    }

    function test_RevertsIf_MintingFailed() public {
        vm.startPrank(user);

        MockFailedMintDSC mockDsCoin = new MockFailedMintDSC();

        tokenAddresses = [weth];
        priceFeedAddresses = [ethUsdPriceFeed];

        DSCEngine mockDscEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(mockDsCoin));
        mockDsCoin.transferOwnership(address(mockDscEngine));

        ERC20Mock(weth).approve(address(mockDscEngine), AMOUNT_COLLATERAL);

        mockDscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__Minting_Failed.selector);
        mockDscEngine.mintDSC(AMOUNT_DSC_To_Mint);

        vm.stopPrank();
    }

    /*/////////////////////////////////////////////////////////////////////////////
                    DESPOSIT COLLATERAL AND MINT DSC TESTS
    /////////////////////////////////////////////////////////////////////////////*/

    modifier depositedCollateralAndMintedDSC() {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.despositCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, AMOUNT_DSC_To_Mint);
        vm.stopPrank();
        _;
    }

    function test_UserCan_DepositCollateral_AndMintDSC() public depositedCollateralAndMintedDSC {
        vm.startPrank(user);

        (uint256 userBalance,) = dscEngine.getAccountInformation(user);
        uint256 collateralBalance = dscEngine.getCollateralBalanceOfUser(user, weth);

        vm.stopPrank();

        assertEq(userBalance, AMOUNT_DSC_To_Mint);
        assertEq(collateralBalance, AMOUNT_COLLATERAL);
    }

    /*/////////////////////////////////////////////////////////////////////////////
                            REDEEM COLLATERAL TESTS
    /////////////////////////////////////////////////////////////////////////////*/
    function test_RevertsIf_ReddemCollateral_WithZeroAmount() public {
        vm.startPrank(user);
        vm.expectRevert(DSCEngine.DSCEngine__ZeroAmount.selector);
        dscEngine.redeemCollateral(weth, 0);
        vm.stopPrank();
    }

    function test_RevertsIf_RedeemCollateralAmount_ExceedsBalance() public depositedCollateral {
        vm.startPrank(user);
        vm.expectRevert();
        dscEngine.redeemCollateral(weth, AMOUNT_COLLATERAL * 2);
        vm.stopPrank();
    }

    function test_UserCan_RedeemCollaterl_UpdatesBalance() public depositedCollateral {
        vm.startPrank(user);
        uint256 startingUserBalance = dscEngine.getCollateralBalanceOfUser(user, weth);
        dscEngine.redeemCollateral(weth, AMOUNT_COLLATERAL);
        uint256 endingUserBalance = dscEngine.getCollateralBalanceOfUser(user, weth);
        vm.stopPrank();

        assertEq(endingUserBalance, 0);
        assertGt(startingUserBalance, endingUserBalance);
    }

    function test__RevertsIf_ReddemCollateral_TransferFailed() public {
        MockFailedTransfer mockDsCoin = new MockFailedTransfer();

        tokenAddresses = [address(mockDsCoin)];
        priceFeedAddresses = [ethUsdPriceFeed];

        DSCEngine mockDscEngine = new DSCEngine(
            tokenAddresses,
            priceFeedAddresses,
            address(mockDsCoin)
        );

        mockDsCoin.mint(user, AMOUNT_COLLATERAL);

        // Arrange - User
        vm.startPrank(user);

        ERC20Mock(address(mockDsCoin)).approve(address(mockDscEngine), AMOUNT_COLLATERAL);
        // Act / Assert

        mockDscEngine.depositCollateral(address(mockDsCoin), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__RedeemCollateral_TransferFailed.selector);
        mockDscEngine.redeemCollateral(address(mockDsCoin), AMOUNT_COLLATERAL);

        vm.stopPrank();
    }

    /*/////////////////////////////////////////////////////////////////////////////
                                    BURN DSC TESTS
    /////////////////////////////////////////////////////////////////////////////*/
    function test_RevertsIf_BurnDSC_ZeroAmount() public depositedCollateralAndMintedDSC {
        vm.startPrank(user);
        vm.expectRevert(DSCEngine.DSCEngine__ZeroAmount.selector);
        dscEngine.burnDSC(0);
        vm.stopPrank();
    }

    function test_RevertsIf_BurnDSC_ExceedsBalance() public depositedCollateralAndMintedDSC {
        vm.startPrank(user);
        vm.expectRevert(DSCEngine.DSCEngine__DSCBurnAmount_ExceedsBalance.selector);
        dscEngine.burnDSC(AMOUNT_DSC_To_Mint * 2);
        vm.stopPrank();
    }

    function test_UserCan_BurnDSC() public depositedCollateralAndMintedDSC {
        vm.startPrank(user);
        dsCoin.approve(address(dscEngine), AMOUNT_DSC_To_Mint);

        dscEngine.burnDSC(AMOUNT_DSC_To_Mint);

        vm.stopPrank();

        uint256 userBalance = dsCoin.balanceOf(user);
        assertEq(userBalance, 0);
    }

    /*/////////////////////////////////////////////////////////////////////////////
                            REDEEM COLLATERAL & BURN DSC TESTS
    /////////////////////////////////////////////////////////////////////////////*/
    function test_RevertsIf_ReddemCollateral_AndBurnDSC_WithZeroAmount() public depositedCollateralAndMintedDSC {
        vm.startPrank(user);
        dsCoin.approve(address(dscEngine), AMOUNT_DSC_To_Mint);
        vm.expectRevert(DSCEngine.DSCEngine__ZeroAmount.selector);
        dscEngine.redeemCollateralAndBurnDSC(weth, 0, AMOUNT_DSC_To_Mint);
        vm.stopPrank();
    }

    function test_UserCan_BurnDSCAnd_RedeemCollateral() public depositedCollateralAndMintedDSC {
        vm.startPrank(user);
        dsCoin.approve(address(dscEngine), AMOUNT_DSC_To_Mint);
        dscEngine.redeemCollateralAndBurnDSC(weth, AMOUNT_COLLATERAL, AMOUNT_DSC_To_Mint);
        vm.stopPrank();
    }

    /*/////////////////////////////////////////////////////////////////////////////
                                HEALTHFACTOR TESTS
    /////////////////////////////////////////////////////////////////////////////*/
    function test_ProperlyReports_HealthFactor() public depositedCollateralAndMintedDSC {
        uint256 userHealthFactor = dscEngine.getHealthFactor(user);
        assertEq(userHealthFactor, 100e18);
        // collateral = 10e18
        // usd value of 10e18 => (10e18*2000e18)/1e18 = 20000e18
        // (20000 * 50)/100 = 1000000 / 100 = 10000e18
        // 10000e18/100e18 = 100e18;
    }

    function test_HealthFactor_CanGo_BelowOne() public depositedCollateralAndMintedDSC {
        int256 ethUsdUpdatedPrice = 15e8; // 1 ETH = $15

        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);

        uint256 userHealthFactor = dscEngine.getHealthFactor(user);
        assertEq(userHealthFactor, 0.75e18);
        // collateral = 10e18
        // usd value of 10e18 => (10e18*15e18)/1e18 = 150e18
        // (150 * 50)/100 = 7500 / 100 = 75e18
        // 75e18/100e18 = 0.75e18;
    }
}

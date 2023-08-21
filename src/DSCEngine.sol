// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {console2} from "forge-std/console2.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "./libraries/OracleLib.sol";

// https://github.com/byterocket/c4-common-issues/blob/main/2-Low-Risk.md

/// @title DSCEngine
/// @author Prince Allwin
/// @notice This system is designed to be as minimal as possible, and have the tokens maintain a 1 DSC token == $1
/// @notice This stable has the following properties
/// - Exogenous Collateral
/// - Dollar Pegged
/// - Algorathmically Stable
/// @notice Our DSC system should be "OverCollateralized". At no point, should the value of all collateral <= the $ backed value of all the DSC.
/// @notice It is similar to DAI if DAI had no governance, no fees, was only backed by wETH and wBTC.
/// @notice This contract is the core of the DSC system. It handles all the logic for minting and redeeming DSC, as well as depositing and redeeming collateral.
/// @notice This contract is VERY loosely based on the MakerDAO DSS (DAI) system.
contract DSCEngine is ReentrancyGuard {
    /*/////////////////////////////////////////////////////////////////////////////
                                STATE VARIABLES
    /////////////////////////////////////////////////////////////////////////////*/

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDSCMinted) private s_dscMinted;
    address[] private s_collateralTokens;

    DecentralizedStableCoin private immutable i_dsCoin;

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; //user should be 200% overcollateralized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10; // this means a 10% bonus

    /*/////////////////////////////////////////////////////////////////////////////
                                    TYPES
    /////////////////////////////////////////////////////////////////////////////*/
    using OracleLib for AggregatorV3Interface;

    /*/////////////////////////////////////////////////////////////////////////////
                                    EVENTS
    /////////////////////////////////////////////////////////////////////////////*/
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event DSCMinted(address indexed user, uint256 indexed amount);
    event CollateralRedeemed(
        address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount
    );
    event DSCBurned(address indexed user, uint256 indexed amount);

    /*/////////////////////////////////////////////////////////////////////////////
                                    CUSTOM ERRORS
    /////////////////////////////////////////////////////////////////////////////*/
    error DSCEngine__ZeroAmount();
    error DSCEngine__TokenNotAllowed();
    error DSCEngine__TokenAddresses_PriceFeedAddresses_DifferentLength();
    error DSCEngine__DSCoinIs_NotAValidAddress();
    error DSCEngine__Collateral_DepositingFailed();
    error DSCEngine__Minting_Failed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__RedeemCollateral_TransferFailed();
    error DSCEngine__DSCBurnAmount_ExceedsBalance();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactor_NotImproved();

    /*/////////////////////////////////////////////////////////////////////////////
                                    MODIFIERS
    /////////////////////////////////////////////////////////////////////////////*/
    modifier moreThanZero(uint256 amount) {
        // @audit != can be used
        if (amount <= 0) {
            revert DSCEngine__ZeroAmount();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__TokenNotAllowed();
        }
        _;
    }

    /*/////////////////////////////////////////////////////////////////////////////
                                    FUNCTIONS
    /////////////////////////////////////////////////////////////////////////////*/

    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dsCoinAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddresses_PriceFeedAddresses_DifferentLength();
        }
        if (dsCoinAddress == address(0)) {
            revert DSCEngine__DSCoinIs_NotAValidAddress();
        }
        // @audit unchecked can be used
        // @audit variable initialized
        for (uint256 index = 0; index < tokenAddresses.length; index++) {
            s_priceFeeds[tokenAddresses[index]] = priceFeedAddresses[index];
            s_collateralTokens.push(tokenAddresses[index]);
        }

        i_dsCoin = DecentralizedStableCoin(dsCoinAddress);
    }

    /*/////////////////////////////////////////////////////////////////////////////
                            PUBLIC & EXTERNAL FUNCTIONS
    /////////////////////////////////////////////////////////////////////////////*/

    /// @dev follows CEI
    /// @param tokenCollateralAddress The address of the token to deposit as collateral, token can be either wETH or wBTC
    /// @param amountCollateral The amount of collateral to desposit
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] =
            s_collateralDeposited[msg.sender][tokenCollateralAddress] + amountCollateral;

        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        /// we have updated our mappings, now we have to get the token from the user using transferFrom()
        /// user is transferring the tokens to DSCEngine
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__Collateral_DepositingFailed();
        }
    }

    /// follows CEI
    /// @param amountDSCToMint The amount of decentralized stablecoin to mint
    /// @notice user must have more collateral value than the minimum threshold
    function mintDSC(uint256 amountDSCToMint) public moreThanZero(amountDSCToMint) nonReentrant {
        s_dscMinted[msg.sender] = s_dscMinted[msg.sender] + amountDSCToMint;
        emit DSCMinted(msg.sender, amountDSCToMint);
        _revertIfHealthFactorIsBroken(msg.sender);

        bool minted = i_dsCoin.mint(msg.sender, amountDSCToMint);
        if (!minted) {
            revert DSCEngine__Minting_Failed();
        }
    }

    /// @dev follows CEI
    /// @param tokenCollateralAddress The address of the token to deposit as collateral, token can be either wETH or wBTC
    /// @param amountCollateral The amount of collateral to desposit
    /// @param amountDSCToMint The amount of decentralized stablecoin to mint
    /// @notice this function will deposit your collateral and mint dsc in one transaction
    function despositCollateralAndMintDSC(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDSCToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDSC(amountDSCToMint);
    }

    // Inorder to redeem collateral
    // 1. Health factor must be over 1 after collateral pulled
    /// @param tokenCollateralAddress The collateral address to redeem
    /// @param amountCollateral The amount of collateral to redeem
    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        _reddemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);

        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /// @param amountDSCToBurn The amount of DSC to burn
    function burnDSC(uint256 amountDSCToBurn) public moreThanZero(amountDSCToBurn) {
        // since we are burning the debt, it will not hurt the healthfactor.
        _burnDSC(amountDSCToBurn, msg.sender, msg.sender);
    }

    /// @param tokenCollateralAddress The collateral address to redeem
    /// @param amountCollateral The amount of collateral to redeem
    /// @param amountDSCToBurn The amount of DSC to burn
    /// @notice This function burns DSC and redeems underlying collateral in one transaction
    function redeemCollateralAndBurnDSC(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDSCToBurn
    ) public {
        // we have to burn DSC before redeeming the collateral
        burnDSC(amountDSCToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
    }

    /// @param collateral The erc20 collateral address to liquidate from the user
    /// @param user The user who has broken the healthFactor. Their healthfactor should be below MIN_HEALTH_FACTOR
    /// @param debtToCover The amount of DSC you want to improve the users health factor
    /// @notice You can partially liquidate a user
    /// @notice You will get a liquidation bonus for taking the users funds
    /// @notice This function working assumes the protocol will be roughly 200% overcollateralized in order for this to work
    /// @notice The reason protocol should be overcollateralized is, we should incentivize the liquidator
    /// @notice A known bug would be if the protocol we 100% or less collateralized, then we wouldn't be able to incentivize the liquidator
    /// For example, if the price of the collateral plummeted before anyone could be liquidated
    function liquidate(address collateral, address user, uint256 debtToCover)
        public
        moreThanZero(debtToCover)
        isAllowedToken(collateral)
        nonReentrant
    {
        // Before allowing someone to liquidate
        // check the healthfactor of the user
        uint256 startingUserHalthFactor = _healthFactor(user);
        if (startingUserHalthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }
        // the liquidator will burn the users "debt" DSC
        // the liquidator can take the collateral of the user
        // Bad User: $140 ETH backing $100 DSC
        // this user is undercollateralized
        // now the liquidator will pay back the $100 worth of DSC
        // first we need to get what is $100 worth of DSC in ETH
        // then give them a 10% bonus
        // we are giving $110 worth of wETH for covering $100 DSC

        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);

        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        // if tokenAmountFromDebtCovered = 5e18
        // (5e18 * 10) / 100
        // 10% of 5e18 is 0.5e18
        // liquidator will get 0.5 ether for paying a debt of 5 ether

        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;

        // now we have to redeem this totalCollateralToRedeem for the liquidator
        _reddemCollateral(collateral, totalCollateralToRedeem, user, msg.sender);

        _burnDSC(debtToCover, user, msg.sender);

        uint256 endingUserHalthFactor = _healthFactor(user);

        // if the health factor is not improved, then it should revert
        if (endingUserHalthFactor <= startingUserHalthFactor) {
            revert DSCEngine__HealthFactor_NotImproved();
        }

        // we should also the check whether healthfactor of the liquidator is broken
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /*/////////////////////////////////////////////////////////////////////////////
                            PUBLIC & EXTERNAL VIEW FUNCTIONS
    /////////////////////////////////////////////////////////////////////////////*/

    function getAccountCollateralValue(address user) public view returns (uint256) {
        // loop through each collateral token, get the amount they have deosited, and map it to the price to get the USD value

        uint256 totalCollateralValueInUsd = 0;
        // @audit variable initialized
        // @audit collateralTokensLength can be cached
        // @audit unchecked can be used
        for (uint256 index = 0; index < s_collateralTokens.length; index++) {
            address token = s_collateralTokens[index];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd = totalCollateralValueInUsd + getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        return (((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION);
    }

    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        return ((usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION));

        // if usdAmountInWei = 1000e18
        // price = 2000e18
        // usdAmountInWei * PRECISION = 1000e18*1e18 = 1000e36
        // uint256(price) * ADDITIONAL_FEED_PRECISION = 2000e8*1e10 = 2000e18
        // 1000e36/2000e18 = 0.5e18
    }

    /*/////////////////////////////////////////////////////////////////////////////
                            PRIVATE & INTERNAL VIEW FUNCTIONS
    /////////////////////////////////////////////////////////////////////////////*/

    function _reddemCollateral(address tokenCollateralAddress, uint256 amountCollateral, address from, address to)
        private
    {
        s_collateralDeposited[from][tokenCollateralAddress] =
            s_collateralDeposited[from][tokenCollateralAddress] - amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);

        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert DSCEngine__RedeemCollateral_TransferFailed();
        }
    }

    /// @dev Low-level internal function, do not call unless the function calling it is checking for health factors being broken
    function _burnDSC(uint256 amountDSCToBurn, address onBehalfOf, address dscFrom) private {
        if (amountDSCToBurn > s_dscMinted[onBehalfOf]) {
            revert DSCEngine__DSCBurnAmount_ExceedsBalance();
        }
        s_dscMinted[onBehalfOf] = s_dscMinted[onBehalfOf] - amountDSCToBurn;
        emit DSCBurned(onBehalfOf, amountDSCToBurn);

        i_dsCoin.transferFrom(dscFrom, address(this), amountDSCToBurn);
        // we are getting the amount from user and bringing it to dscEngine and then burning it
        i_dsCoin.burn(amountDSCToBurn);
    }

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDSCMinted, uint256 collateralValueInUsd)
    {
        totalDSCMinted = s_dscMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    /// Returns how close to liquidation a user is
    /// If a user's healthfactor goes below 1, then they can be liquidated
    function _healthFactor(address user) private view returns (uint256) {
        // To determine the health factor
        // 1. Get total DSC minted by the user
        // 2. Total VALUE of collateral deposited
        (uint256 totalDSCMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        return _calculateHealthFactor(totalDSCMinted, collateralValueInUsd);
    }

    // 1. Check health factor (do they have enough collateral?)
    // 2. Revert if they don't
    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    function _calculateHealthFactor(uint256 totalDSCMinted, uint256 collateralValueInUsd)
        internal
        pure
        returns (uint256)
    {
        if (totalDSCMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedForThreshold =
            ((collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION);
        return ((collateralAdjustedForThreshold * PRECISION) / totalDSCMinted);
        // if collateralValueInUsd = $1000 of ETH, but if totalDSCMinted = 0, we cannot divide by 0
    }

    /*/////////////////////////////////////////////////////////////////////////////
                        EXTERNAL & PUBLIC VIEW & PURE FUNCTIONS
    /////////////////////////////////////////////////////////////////////////////*/
    function getAccountInformation(address user)
        external
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        (totalDscMinted, collateralValueInUsd) = _getAccountInformation(user);
    }

    function getCollateralBalanceOfUser(address user, address token) public view returns (uint256) {
        return s_collateralDeposited[user][token];
    }

    function getDSC() public view returns (address) {
        return address(i_dsCoin);
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getMinHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }

    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }

    function calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd)
        external
        pure
        returns (uint256)
    {
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getCollateralTokenPriceFeed(address token) public view returns (address) {
        return s_priceFeeds[token];
    }
}

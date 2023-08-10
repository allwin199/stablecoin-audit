// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

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
    uint256 private constant MIN_HEALTH_FACTOR = 1;

    /*/////////////////////////////////////////////////////////////////////////////
                                    EVENTS
    /////////////////////////////////////////////////////////////////////////////*/
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event DSCMinted(address indexed user, uint256 indexed amount);

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

    /*/////////////////////////////////////////////////////////////////////////////
                                    MODIFIERS
    /////////////////////////////////////////////////////////////////////////////*/
    modifier moreThanZero(uint256 amount) {
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
        for (uint256 index = 0; index < tokenAddresses.length; index++) {
            s_priceFeeds[tokenAddresses[index]] = priceFeedAddresses[index];
            s_collateralTokens.push(tokenAddresses[index]);
        }

        i_dsCoin = DecentralizedStableCoin(dsCoinAddress);
    }

    /*/////////////////////////////////////////////////////////////////////////////
                                PUBLIC FUNCTIONS
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
        _revertIfHealthFactorIsBroken(msg.sender);
        emit DSCMinted(msg.sender, amountDSCToMint);

        bool minted = i_dsCoin.mint(address(this), amountDSCToMint);
        if (!minted) {
            revert DSCEngine__Minting_Failed();
        }
    }

    function despositCollateralAndMintDSC() public {}

    function redeemCollateral() public {}

    function burnDSC() public {}

    function redeemCollateralAndBurnDSC() public {}

    function liquidate() public {}

    function healthFactor() public {}

    /*/////////////////////////////////////////////////////////////////////////////
                            PUBLIC & EXTERNAL VIEW FUNCTIONS
    /////////////////////////////////////////////////////////////////////////////*/

    function getAccountCollateralValue(address user) public view returns (uint256) {
        // loop through each collateral token, get the amount they have deosited, and map it to the price to get the USD value

        uint256 totalCollateralValueInUsd = 0;
        for (uint256 index = 0; index < s_collateralTokens.length; index++) {
            address token = s_collateralTokens[index];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd = totalCollateralValueInUsd + getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return (((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION);
    }

    /*/////////////////////////////////////////////////////////////////////////////
                            PRIVATE & INTERNAL VIEW FUNCTIONS
    /////////////////////////////////////////////////////////////////////////////*/

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
}

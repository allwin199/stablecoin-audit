// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {IERC20} from "@openzeppelin/contracts/";

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

    mapping(address token => address priceFeed) s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) s_collateralDeposited;

    DecentralizedStableCoin private immutable i_dsCoin;

    /*/////////////////////////////////////////////////////////////////////////////
                                    EVENTS
    /////////////////////////////////////////////////////////////////////////////*/
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);

    /*/////////////////////////////////////////////////////////////////////////////
                                    CUSTOM ERRORS
    /////////////////////////////////////////////////////////////////////////////*/
    error DSCEngine__ZeroAmount();
    error DSCEngine__TokenNotAllowed();
    error DSCEngine__TokenAddresses_PriceFeedAddresses_DifferentLength();
    error DSCEngine__DSCoinIs_NotAValidAddress();
    error DSCEngine__Collateral_DepositingFailed();

    /*/////////////////////////////////////////////////////////////////////////////
                                    MODIFIERS
    /////////////////////////////////////////////////////////////////////////////*/
    modifier ZeroAmount(uint256 amount) {
        if (amount <= 0) {
            revert DSCEngine__ZeroAmount();
        }
        _;
    }

    modifier IsAllowedToken(address token) {
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
        ZeroAmount(amountCollateral)
        IsAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] =
            s_collateralDeposited[msg.sender][tokenCollateralAddress] + amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        /// we have updated our mappings, now we have to get the token from the user using transferFrom()
        /// user is transferring the token to DSCEngine
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__Collateral_DepositingFailed();
        }
    }

    function mintDSC() public {}

    function despositCollateralAndMintDSC() public {}

    function redeemCollateral() public {}

    function burnDSC() public {}

    function redeemCollateralAndBurnDSC() public {}

    function liquidate() public {}

    function healthFactor() public {}
}

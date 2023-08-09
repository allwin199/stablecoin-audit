// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

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
contract DSCEngine {
    /*/////////////////////////////////////////////////////////////////////////////
                                Functions
    /////////////////////////////////////////////////////////////////////////////*/

    function depositCollateral() public {}

    function mintDSC() public {}

    function despositCollateralAndMintDSC() public {}

    function redeemCollateral() public {}

    function burnDSC() public {}

    function redeemCollateralAndBurnDSC() public {}

    function liquidate() public {}

    function healthFactor() public {}
}

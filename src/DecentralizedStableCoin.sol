// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {console2} from "forge-std/console2.sol";
import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title DecentralizedStableCoin
/// @author Prince Allwin
/// @notice Collateral: Exogenous (wETH & wBTC)
/// @notice Minting: Algorathmic
/// @notice Relative Stability: Pegged to USD
/// @notice This is the contract governed by DSCEngine. This contract is just the ERC20 implementation of our StableCoin system.
contract DecentralizedStableCoin is ERC20Burnable, Ownable {
    /*/////////////////////////////////////////////////////////////////////////////
                                CUSTOM ERRORS
    /////////////////////////////////////////////////////////////////////////////*/
    error DecentralizedStableCoin__ZeroAmount();
    error DecentralizedStableCoin__BurnAmount_ExceedsBalance();
    error DecentralizedStableCoin__ZeroAddress();

    /*/////////////////////////////////////////////////////////////////////////////
                                MODIFIERS
    /////////////////////////////////////////////////////////////////////////////*/

    modifier moreThanZero(uint256 amount) {
        if (amount <= 0) {
            revert DecentralizedStableCoin__ZeroAmount();
        }
        _;
    }

    /*/////////////////////////////////////////////////////////////////////////////
                                FUNCTIONS
    /////////////////////////////////////////////////////////////////////////////*/
    constructor() ERC20("DecentralizedStableCoin", "DSC") {}

    /*/////////////////////////////////////////////////////////////////////////////
                            PUBLIC AND EXTERNAL FUNCTIONS
    /////////////////////////////////////////////////////////////////////////////*/

    /// @param to address of the minter
    /// @param amount amount to be minted
    /// @dev onlyOwner modifier is implemented
    /// @dev returns true, if minting is successful
    function mint(address to, uint256 amount) external onlyOwner moreThanZero(amount) returns (bool) {
        if (to == address(0)) {
            revert DecentralizedStableCoin__ZeroAddress();
        }
        _mint(to, amount);
        return true;
    }

    /// @param amount amount to be burned
    /// @dev super.burn() knows it has to burn from msg.sender
    /// @dev onlyOwner modifier is implemented
    function burn(uint256 amount) public override onlyOwner moreThanZero(amount) {
        uint256 userDSCbalance = balanceOf(msg.sender);
        if (userDSCbalance < amount) {
            revert DecentralizedStableCoin__BurnAmount_ExceedsBalance();
        }
        super.burn(amount);
    }
}

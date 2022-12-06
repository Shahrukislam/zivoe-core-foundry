// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.16;

import "../lib/OpenZeppelin/Governance/ERC20Votes.sol";

/// @notice  This ERC20 contract represents the ZivoeDAO governance token.
///          This contract should support the following functionalities:
///           - Burnable
contract ZivoeToken is ERC20Votes {

    // ---------------------
    //    State Variables
    // ---------------------

    address private _GBL;   /// @dev Zivoe globals contract.



    // -----------
    // Constructor
    // -----------

    /// @notice Initializes the ZivoeToken.sol contract ($ZVE).
    /// @param name_ The name of $ZVE (Zivoe).
    /// @param symbol_ The symbol of $ZVE (ZVE).
    /// @param init The initial address to escrow $ZVE supply, prior to distribution.
    /// @param GBL_ The Zivoe globals contract.
    constructor(
        string memory name_,
        string memory symbol_,
        address init,
        address GBL_
    ) ERC20(name_, symbol_) ERC20Permit(name_) {
        _GBL = GBL_;
        _mint(init, 25000000 ether);
    }



    // ---------------
    //    Functions
    // ---------------

    /// @notice Returns the address of the Zivoe globals contract.
    /// @return GBL_ The address of the Zivoe globals contract.
    function GBL() public view virtual override returns (address GBL_) {
        return _GBL;
    }

    /// @notice Burns $ZVE tokens.
    /// @param  amount The number of $ZVE tokens to burn.
    function burn(uint256 amount) public virtual {
        _burn(_msgSender(), amount);
    }
    
}

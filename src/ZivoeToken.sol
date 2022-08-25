// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.6;

import "./OpenZeppelin/Governance/ERC20Votes.sol";

/// @dev    This ERC20 contract represents the ZivoeDAO governance token.
///         This contract should support the following functionalities:
///          - Burnable
contract ZivoeToken is ERC20Votes {

    // -----------
    // Constructor
    // -----------

    address public immutable GBL;  /// @dev Zivoe globals contract.

    /// @notice Initializes the ZivoeToken.sol contract ($ZVE).
    /// @param name_ The name of $ZVE (Zivoe).
    /// @param symbol_ The symbol of $ZVE (ZVE).
    /// @param init The initial address to escrow $ZVE supply, prior to distribution.
    /// @param _GBL The Zivoe globals contract.
    constructor(
        string memory name_,
        string memory symbol_,
        address init,
        address _GBL
    ) ERC20(name_, symbol_, init) ERC20Permit(name_) { 
        GBL = _GBL;
    }

    /// @notice Burns $ZVE tokens.
    /// @param  amount The number of $ZVE tokens to burn.
    function burn(uint256 amount) public virtual {
         _burn(_msgSender(), amount);
    }

    function getGBL() public view virtual override returns (address) {
        return GBL;
    }
    
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

/// @title Presale Liquefied AERO (pLAERO)
/// @notice The presale receipt, redeemable 1:1 for LAERO through PresaleClaim.
/// @dev The presale that deploys this token is its only minter, fixed at construction. Only
///      holders, and those they approve, can burn. There is no owner.
contract PresaleLAERO is ERC20, ERC20Burnable {
    /// @notice The presale; the only address that may mint.
    address public immutable minter;

    error NotMinter();
    error ZeroMinter();

    /// @param _name "Presale Liquefied AERO" on mainnet.
    /// @param _symbol "pLAERO" on mainnet.
    /// @param _minter The presale.
    constructor(string memory _name, string memory _symbol, address _minter) ERC20(_name, _symbol) {
        if (_minter == address(0)) revert ZeroMinter();
        minter = _minter;
    }

    /// @notice Mint pLAERO. The presale only.
    function mint(address to, uint256 amount) external {
        if (msg.sender != minter) revert NotMinter();
        _mint(to, amount);
    }
}

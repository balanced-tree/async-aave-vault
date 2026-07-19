// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Interfaces
import {ISupplyBorrowVault} from "./interfaces/ISupplyBorrowVault.sol";

// OpenZeppelin
import {Math} from "openzeppelin/utils/math/Math.sol";
import {ERC20} from "openzeppelin/token/ERC20/ERC20.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {IERC4626} from "openzeppelin/interfaces/IERC4626.sol";
import {AccessControl} from "openzeppelin/access/AccessControl.sol";
import {IERC165} from "openzeppelin/utils/introspection/IERC165.sol";
import {ReentrancyGuard} from "openzeppelin/utils/ReentrancyGuard.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "openzeppelin/interfaces/IERC20Metadata.sol";

/// @title SupplyBorrowVault
/// @author balanced-tree
/// @notice Vault that deposits into Aave v4 Spoke as strategy, borrows against supplied assets and uses the borrowed assets to deposit into another vault.
/// @dev Has synchronous deposits and asynchronous redemptions.
contract SupplyBorrowVault is ERC20 {
    using SafeERC20 for IERC20;
    using Math for uint256;

    /*//////////////////////////////////////////////////////////////
                                STATE
    //////////////////////////////////////////////////////////////*/

    address public manager;

    // Immutable state
    IERC20 public immutable ASSET;
    uint8 public immutable UNDERLYING_DECIMALS;

    address private immutable TREASURY;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor(
        address asset_,
        address admin_,
        address treasury_,
        string memory name_,
        string memory symbol_
    ) ERC20(name_, symbol_) {}

}
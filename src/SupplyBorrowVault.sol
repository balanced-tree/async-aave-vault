// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ISupplyBorrowVault} from "./interfaces/ISupplyBorrowVault.sol";

/// @title SupplyBorrowVault
/// @author balanced-tree
/// @notice Vault that deposits into Aave v4 Spoke as strategy, borrows against supplied assets and uses the borrowed assets to deposit into another vault.
/// @dev Has synchronous deposits and asynchronous redemptions.
contract SupplyBorrowVault {

}
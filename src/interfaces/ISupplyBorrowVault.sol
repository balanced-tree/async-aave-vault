// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC4626} from "openzeppelin/interfaces/IERC4626.sol";
import {IERC7540Redeem} from "centrifuge/misc/interfaces/IERC7540.sol";

interface ISupplyBorrowVault is IERC4626, IERC7540Redeem {
    /*//////////////////////////////////////////////////////////////
                                STATE
    //////////////////////////////////////////////////////////////*/
    struct RedeemRequestData {
        uint256 pendingShares;
        uint256 claimableShares;
        uint256 claimableAssets;
    }

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/
    error ZERO_AMOUNT();
    error ZERO_SHARES();
    error ZERO_ADDRESS();
    error UNAUTHORIZED();
    error INVALID_ASSET();
    error INVALID_MANAGER();
    error NOT_IMPLEMENTED();
    error INVALID_OPERATOR();
    error INVALID_FEE_AMOUNT();

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    event managerSet(address indexed newManager);
    event performanceFeeSet(uint256 indexed newFee);

    /*//////////////////////////////////////////////////////////////
                                FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Set the manager of the vault
     * @param newManager The address of the vault manager
     * @dev Only the default admin can set the manager
     */
    function setManager(address newManager) external;

    /**
     * @notice Set the performance fee
     * @param newFee The new performance fee
     * @dev Only the default admin can set the performance fee
     */
    function setPerformanceFee(uint256 newFee) external;
}
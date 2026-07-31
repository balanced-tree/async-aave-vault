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

    struct StrategyExecutionData {
        uint256 borrowAmount;
        uint256 depositAmount;
        uint256 minSharesRequired;
    }

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/
    error HF_TOO_LOW();
    error ZERO_AMOUNT();
    error ZERO_SHARES();
    error ZERO_ADDRESS();
    error UNAUTHORIZED();
    error INVALID_ASSET();
    error INVALID_AMOUNT();
    error INVALID_MANAGER();
    error NOT_IMPLEMENTED();
    error INVALID_OPERATOR();
    error MAX_MINT_EXCEEDED();
    error INVALID_FEE_AMOUNT();
    error MAX_DEPOSIT_EXCEEDED();
    error INSUFFICIENT_LIQUIDITY();

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    event ManagerSet(address indexed newManager);
    event PerformanceFeeSet(uint256 indexed newFee);
    event TargetIdleBpsSet(uint256 indexed newTargetIdleBps);
    event MinSupplyAmountSet(uint256 indexed newMinSupplyAmount);
    event MinHealthFactorSet(uint256 indexed newMinHealthFactor);
    event CostBasisUpdated(address indexed shareHolder, uint256 costBasisPerShare);

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

    /**
     * @notice Set the target ratio of funds to be kept idle in the vault in basis points
     * @param targetIdleBps The target ratio of funds to be kept idle in the vault in basis points
     * @dev Only the default admin can set the target ratio
     */
    function setTargetIdleBps(uint256 targetIdleBps) external;

    /**
     * @notice Set the minimum amount of idle assets to supply to Aave to avoid dust size supply() calls
     * @param minSupplyAmount_ The minimum amount of idle assets to supply
     * @dev Only the vault manager can set the minimum amount of idle assets to supply
     */
    function setMinSupplyAmount(uint256 minSupplyAmount_) external;

    /**
     * @notice Set the minimum health factor
     * @param minHealthFactor The minimum health factor
     * @dev Only the vault manager can set the minimum health factor
     */
    function setMinHealthFactor(uint256 minHealthFactor) external;

    /**
     * @notice Execute a strategy
     * @param strategy The data for the strategy execution
     * @dev Only the vault manager can execute a strategy
     */
    function executeStrategy(StrategyExecutionData memory strategy) external;
}

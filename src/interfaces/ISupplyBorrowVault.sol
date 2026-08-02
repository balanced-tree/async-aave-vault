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
    error ZERO_AMOUNT();
    error ZERO_SHARES();
    error ZERO_ADDRESS();
    error INVALID_ASSET();
    error INVALID_AMOUNT();
    error MAX_MINT_EXCEEDED();
    error MAX_DEPOSIT_EXCEEDED();
    error INSUFFICIENT_LIQUIDITY();
    error INSUFFICIENT_SHARES();
    error INVALID_FEE_AMOUNT();
    error INVALID_OPERATOR();
    error INVALID_MANAGER();
    error NOT_IMPLEMENTED();
    error UNAUTHORIZED();
    error HF_TOO_LOW();

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    event ManagerSet(address indexed newManager);
    event PerformanceFeeSet(uint256 indexed newFee);
    event TargetIdleBpsSet(uint256 indexed newTargetIdleBps);
    event MinSupplyAmountSet(uint256 indexed newMinSupplyAmount);
    event MinHealthFactorSet(uint256 indexed newMinHealthFactor);
    event StrategyExecuted(uint256 indexed sharesAcquired, uint256 
    indexed amountBorrowed);
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
     * @notice Manager leverage step: Execute a strategy to optionally borrow from Aave, then deploy held BORROW funds into the underlying vault.
     * @dev Only the vault manager can execute a strategy
     * @param strategy The data for the strategy execution
     * @return sharesAcquired The number of shares acquired from the strategy execution
     */
    function executeStrategy(StrategyExecutionData memory strategy) external returns (uint256 sharesAcquired);

    /**
     * @notice Manager deleverage step: unwind (part of) the leveraged position to refill the idle buffer that funds redemptions.
     * @dev Only the vault manager can deleverage
     * @param downstreamShares The number of shares to unwind
     * @param repayAmount The amount of debt to repay
     * @param collateralToWithdraw The amount of collateral to withdraw
     */
    function deleverage(uint256 downstreamShares, uint256 repayAmount, uint256 collateralToWithdraw) external;
}

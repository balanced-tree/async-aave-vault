// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {TestBase} from "./utils/TestBase.sol";
import {ISupplyBorrowVault} from "../src/interfaces/ISupplyBorrowVault.sol";

import {IERC20} from "openzeppelin/interfaces/IERC20.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";

contract StrategyExecutionTest is TestBase {
    using SafeERC20 for IERC20;

    function setUp() public override {
        super.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                       EXECUTE STRATEGY TESTS
    //////////////////////////////////////////////////////////////*/
    function test_ExecuteStrategy_revertsIfNotManager() public {
        ISupplyBorrowVault.StrategyExecutionData memory strategy = ISupplyBorrowVault.StrategyExecutionData({
            borrowAmount: 0,
            depositAmount: 100e6,
            minSharesRequired: 1
        });

        vm.prank(alice);
        vm.expectRevert();
        vault.executeStrategy(strategy);
    }

    function test_ExecuteStrategy_revertsOnZeroDepositAmount() public {
        ISupplyBorrowVault.StrategyExecutionData memory strategy = ISupplyBorrowVault.StrategyExecutionData({
            borrowAmount: 0,
            depositAmount: 0,
            minSharesRequired: 1
        });

        vm.prank(admin);
        vm.expectRevert(ISupplyBorrowVault.ZERO_AMOUNT.selector);
        vault.executeStrategy(strategy);
    }

    function test_ExecuteStrategy_revertsOnZeroMinShares() public {
        ISupplyBorrowVault.StrategyExecutionData memory strategy = ISupplyBorrowVault.StrategyExecutionData({
            borrowAmount: 0,
            depositAmount: 100e6,
            minSharesRequired: 0
        });

        vm.prank(admin);
        vm.expectRevert(ISupplyBorrowVault.ZERO_AMOUNT.selector);
        vault.executeStrategy(strategy);
    }

    function test_ExecuteStrategy_revertsOnInsufficientShares() public {
        // Supply USDT as collateral, then demand impossibly many downstream shares
        _depositAs(alice, 1000e6);

        ISupplyBorrowVault.StrategyExecutionData memory strategy = ISupplyBorrowVault.StrategyExecutionData({
            borrowAmount: 300e6,
            depositAmount: 300e6,
            minSharesRequired: type(uint256).max
        });

        vm.prank(admin);
        vm.expectRevert(ISupplyBorrowVault.INSUFFICIENT_SHARES.selector);
        vault.executeStrategy(strategy);
    }

    function test_ExecuteStrategy_withoutBorrow() public {
        // Deposit collateral, borrow 300 USDC but only deploy half — leaves 150 in accountedBorrowAssets
        _depositAs(alice, 1000e6);

        uint256 borrowAmount = 300e6;
        vm.prank(admin);
        vault.executeStrategy(
            ISupplyBorrowVault.StrategyExecutionData({
                borrowAmount: borrowAmount,
                depositAmount: borrowAmount / 2,
                minSharesRequired: 1
            })
        );

        uint256 sharesBefore = vault.UNDERLYING_VAULT().balanceOf(address(vault));
        uint256 debtBefore = spoke.getUserTotalDebt(USDC_RESERVE_ID, address(vault));

        // Deploy the remaining 150 USDC without borrowing more
        vm.prank(admin);
        uint256 sharesAcquired = vault.executeStrategy(
            ISupplyBorrowVault.StrategyExecutionData({
                borrowAmount: 0,
                depositAmount: borrowAmount / 2,
                minSharesRequired: 1
            })
        );

        assertGt(sharesAcquired, 0, "acquired additional downstream shares");
        assertGt(vault.UNDERLYING_VAULT().balanceOf(address(vault)), sharesBefore, "downstream shares increased");

        uint256 debtAfter = spoke.getUserTotalDebt(USDC_RESERVE_ID, address(vault));
        assertApproxEqAbs(debtAfter, debtBefore, 1, "Aave debt unchanged - no new borrow");
    }

    function test_ExecuteStrategy_withBorrow() public {
        // Deposit 1000e6 USDT → 700e6 rebalances to Aave as collateral
        _depositAs(alice, 1000e6);

        uint256 borrowAmount = 300e6;
        ISupplyBorrowVault.StrategyExecutionData memory strategy = ISupplyBorrowVault.StrategyExecutionData({
            borrowAmount: borrowAmount,
            depositAmount: borrowAmount,
            minSharesRequired: 1
        });

        vm.prank(admin);
        uint256 sharesAcquired = vault.executeStrategy(strategy);

        assertGt(sharesAcquired, 0, "acquired downstream shares");
        assertEq(vault.UNDERLYING_VAULT().balanceOf(address(vault)), sharesAcquired, "vault holds downstream shares");

        uint256 debt = spoke.getUserTotalDebt(USDC_RESERVE_ID, address(vault));
        assertApproxEqAbs(debt, borrowAmount, 1, "Aave debt matches borrowed amount");
    }

    function test_ExecuteStrategy_revertsIfHfTooLow() public {
        // 700e6 USDT as collateral; borrowing 1000e6 USDC gives HF ≈ 0.68 — below the 1.3 floor
        _depositAs(alice, 1000e6);

        ISupplyBorrowVault.StrategyExecutionData memory strategy = ISupplyBorrowVault.StrategyExecutionData({
            borrowAmount: 1000e6,
            depositAmount: 1000e6,
            minSharesRequired: 1
        });

        vm.prank(admin);
        vm.expectRevert(ISupplyBorrowVault.HF_TOO_LOW.selector);
        vault.executeStrategy(strategy);
    }

    function test_ExecuteStrategy_revertsWhenHfBelowConfiguredFloor() public {
        // 700e6 USDT in Aave → effective collateral ≈ 679 USDC (97% CF)
        // Borrowing 450e6 USDC → HF ≈ 1.51; passes the 1.3 constant floor but fails a 1.8 configured floor
        _depositAs(alice, 1000e6);

        vm.prank(admin);
        vault.setMinHealthFactor(1.8e18);

        ISupplyBorrowVault.StrategyExecutionData memory strategy = ISupplyBorrowVault.StrategyExecutionData({
            borrowAmount: 450e6,
            depositAmount: 450e6,
            minSharesRequired: 1
        });

        vm.prank(admin);
        vm.expectRevert(ISupplyBorrowVault.HF_TOO_LOW.selector);
        vault.executeStrategy(strategy);
    }

    function test_ExecuteStrategy_emitsEventOnBorrow() public {
        _depositAs(alice, 1000e6);

        uint256 borrowAmount = 300e6;
        uint256 expectedShares = vault.UNDERLYING_VAULT().previewDeposit(borrowAmount);

        vm.prank(admin);
        vm.expectEmit(true, true, false, false, address(vault));
        emit ISupplyBorrowVault.StrategyExecuted(expectedShares, borrowAmount);
        vault.executeStrategy(
            ISupplyBorrowVault.StrategyExecutionData({
                borrowAmount: borrowAmount,
                depositAmount: borrowAmount,
                minSharesRequired: 1
            })
        );
    }

    function test_ExecuteStrategy_emitsEventWithoutBorrow() public {
        _depositAs(alice, 1000e6);

        uint256 borrowAmount = 300e6;
        vm.prank(admin);
        vault.executeStrategy(
            ISupplyBorrowVault.StrategyExecutionData({
                borrowAmount: borrowAmount,
                depositAmount: borrowAmount / 2,
                minSharesRequired: 1
            })
        );

        uint256 expectedShares = vault.UNDERLYING_VAULT().previewDeposit(borrowAmount / 2);

        vm.prank(admin);
        vm.expectEmit(true, true, false, false, address(vault));
        emit ISupplyBorrowVault.StrategyExecuted(expectedShares, 0);
        vault.executeStrategy(
            ISupplyBorrowVault.StrategyExecutionData({
                borrowAmount: 0,
                depositAmount: borrowAmount / 2,
                minSharesRequired: 1
            })
        );
    }
}
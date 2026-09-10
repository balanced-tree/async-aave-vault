// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {TestBase} from "./utils/TestBase.sol";
import {ISupplyBorrowVault} from "../src/interfaces/ISupplyBorrowVault.sol";

contract AccountingTest is TestBase {
    function setUp() public override {
        super.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                       TOTAL ASSETS ACCOUNTING TESTS
    //////////////////////////////////////////////////////////////*/

    // Deposit 60e6 USDT: targetIdle = 18e6, excess = 42e6 < minSupplyAmount (50e6),
    // so no rebalance fires. totalAssets equals the idle balance only.
    function test_TotalAssets_idleOnly() public {
        _depositAs(alice, 60e6);

        assertEq(spoke.getUserSuppliedAssets(USDT_RESERVE_ID, address(vault)), 0, "nothing supplied to Aave");
        assertEq(vault.totalAssets(), 60e6, "totalAssets equals idle deposit");
    }

    // Deposit 1000e6: excess = 700e6 > minSupplyAmount (50e6), rebalance supplies to Aave.
    // totalAssets = idle (300e6) + Aave supply (700e6) = 1000e6.
    function test_TotalAssets_withAaveSupply() public {
        _depositAs(alice, 1000e6);

        assertGt(spoke.getUserSuppliedAssets(USDT_RESERVE_ID, address(vault)), 0, "USDT in Aave");
        assertApproxEqAbs(vault.totalAssets(), 1000e6, 1, "totalAssets matches deposit");
    }

    // After borrowing 300e6 USDC with 150e6 held in vault and 150e6 deployed to Morpho,
    // totalAssets should reflect BOTH the held borrow assets AND the underlying vault position
    // minus the debt. Net USDC exposure = (150 held + 150 in Morpho) - 300 debt = 0.
    // totalAssets should remain approximately equal to the original deposit.
    function test_TotalAssets_withBorrowAndDebt() public {
        _depositAs(alice, 1000e6);
        uint256 totalAfterDeposit = vault.totalAssets();

        // Borrow 300e6 USDC, deploy only 150e6 to Morpho, keep 150e6 in _accountedBorrowAssets
        vm.prank(admin);
        vault.executeStrategy(
            ISupplyBorrowVault.StrategyExecutionData({
                borrowAmount: 300e6,
                depositAmount: 150e6,
                minSharesRequired: 1
            })
        );

        // Net borrow exposure: (150e6 held + ~150e6 in Morpho) - 300e6 debt = ~0
        // totalAssets should be approximately unchanged from the pre-strategy value
        assertApproxEqAbs(
            vault.totalAssets(), totalAfterDeposit, 1e6, "underlying vault position offsets debt in totalAssets"
        );

        // Confirm downstream shares are correctly contributing to the total
        assertGt(vault.UNDERLYING_VAULT().balanceOf(address(vault)), 0, "vault holds downstream shares");
    }

    // After warping 30 days, both Aave supply interest and Morpho yield accrue.
    // Aave yield is visible immediately via getUserSuppliedAssets.
    // Morpho yield is visible via previewRedeem growing while debt (stale view) stays flat.
    function test_TotalAssets_afterYieldAccrual() public {
        _depositAs(alice, 1000e6);

        // Deploy borrowed USDC to Morpho so Morpho yield is also captured in totalAssets
        vm.prank(admin);
        vault.executeStrategy(
            ISupplyBorrowVault.StrategyExecutionData({
                borrowAmount: 300e6,
                depositAmount: 300e6,
                minSharesRequired: 1
            })
        );

        uint256 totalBefore = vault.totalAssets();

        vm.warp(block.timestamp + 30 days);

        assertGt(vault.totalAssets(), totalBefore, "yield accrual increases totalAssets");
    }
}

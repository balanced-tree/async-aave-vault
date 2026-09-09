// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {TestBase} from "./utils/TestBase.sol";
import {ISupplyBorrowVault} from "../src/interfaces/ISupplyBorrowVault.sol";

import {IERC20} from "openzeppelin/interfaces/IERC20.sol";
import {ISpoke} from "aave-v4/spoke/interfaces/ISpoke.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";

contract DeleverageTest is TestBase {
    using SafeERC20 for IERC20;

    // Deposit USDT, borrow USDC, deploy all USDC to Morpho. Returns downstream shares acquired.
    function _setupLeveragedPosition(uint256 depositAmount, uint256 borrowAmount)
        internal
        returns (uint256 downstreamShares)
    {
        _depositAs(alice, depositAmount);
        vm.prank(admin);
        downstreamShares = vault.executeStrategy(
            ISupplyBorrowVault.StrategyExecutionData({
                borrowAmount: borrowAmount, depositAmount: borrowAmount, minSharesRequired: 1
            })
        );
    }

    function setUp() public override {
        super.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                          DELEVERAGE TESTS
    //////////////////////////////////////////////////////////////*/
    function test_Deleverage_revertsIfNotManager() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.deleverage(0, 0, 100e6);
    }

    function test_Deleverage_partialUnwind() public {
        uint256 allShares = _setupLeveragedPosition(1000e6, 300e6);
        uint256 halfShares = allShares / 2;

        uint256 debtBefore = spoke.getUserTotalDebt(USDC_RESERVE_ID, address(vault));

        // ERC4626 floor-rounding means redeeming half the shares gives slightly less than half
        // the deposited USDC. Use previewRedeem to get the exact amount so the repay transfer
        // doesn't exceed the vault's balance.
        uint256 repayAmount = vault.UNDERLYING_VAULT().previewRedeem(halfShares);

        vm.prank(admin);
        vault.deleverage(halfShares, repayAmount, 0);

        assertApproxEqAbs(
            vault.UNDERLYING_VAULT().balanceOf(address(vault)),
            allShares - halfShares,
            1,
            "half downstream shares redeemed"
        );
        assertLt(spoke.getUserTotalDebt(USDC_RESERVE_ID, address(vault)), debtBefore, "Aave debt reduced");
        assertApproxEqAbs(
            spoke.getUserTotalDebt(USDC_RESERVE_ID, address(vault)),
            debtBefore - repayAmount,
            2,
            "debt reduced by repay amount"
        );
    }

    function test_Deleverage_fullUnwind() public {
        uint256 allShares = _setupLeveragedPosition(1000e6, 300e6);
        IERC20 borrowAsset = IERC20(vault.UNDERLYING_VAULT().asset());

        // Step 1: pull all USDC back from Morpho into _accountedBorrowAssets
        vm.prank(admin);
        vault.deleverage(allShares, 0, 0);

        assertEq(vault.UNDERLYING_VAULT().balanceOf(address(vault)), 0, "no downstream shares remain");

        // Use actual vault USDC balance as repayAmount — Morpho floor-rounding means it may be
        // slightly less than the outstanding debt, which is fine for a near-full repayment.
        uint256 repayAmount = borrowAsset.balanceOf(address(vault));
        uint256 aaveSupply = spoke.getUserSuppliedAssets(USDT_RESERVE_ID, address(vault));
        uint256 vaultUsdtBefore = asset.balanceOf(address(vault));

        vm.prank(admin);
        vault.deleverage(0, repayAmount, aaveSupply);

        assertApproxEqAbs(spoke.getUserTotalDebt(USDC_RESERVE_ID, address(vault)), 0, 10, "Aave debt nearly cleared");
        assertApproxEqAbs(spoke.getUserSuppliedAssets(USDT_RESERVE_ID, address(vault)), 0, 1e6, "Aave supply cleared");
        assertApproxEqAbs(
            asset.balanceOf(address(vault)),
            vaultUsdtBefore + aaveSupply,
            1e6,
            "vault USDT balance reflects freed collateral"
        );
    }

    function test_Deleverage_revertsIfHfDropsBelowFloor() public {
        // HF after setup is ~1.7-2.3 (300e6 USDC debt against 700e6 USDT)
        // Setting minHealthFactor = 3.0e18 means any residual-debt deleverage fails the vault's floor.
        // Withdrawing 50e6 USDT is within Aave's own health limits but below our custom floor.
        _setupLeveragedPosition(1000e6, 300e6);

        vm.prank(admin);
        vault.setMinHealthFactor(3.0e18);

        vm.prank(admin);
        vm.expectRevert(ISupplyBorrowVault.HF_TOO_LOW.selector);
        vault.deleverage(0, 0, 50e6);
    }

    function test_Deleverage_withZeroDebtFreesCollateralDirectly() public {
        // Deposit without borrowing — 700e6 USDT flows to Aave, debt stays zero
        _depositAs(alice, 1000e6);

        uint256 aaveSupplyBefore = spoke.getUserSuppliedAssets(USDT_RESERVE_ID, address(vault));
        uint256 vaultUsdtBefore = asset.balanceOf(address(vault));

        // HF check is skipped when debt == 0 — collateral withdrawal goes through freely
        vm.prank(admin);
        vault.deleverage(0, 0, 100e6);

        assertApproxEqAbs(
            spoke.getUserSuppliedAssets(USDT_RESERVE_ID, address(vault)),
            aaveSupplyBefore - 100e6,
            1e6,
            "Aave supply reduced"
        );
        assertApproxEqAbs(asset.balanceOf(address(vault)), vaultUsdtBefore + 100e6, 1e6, "vault USDT balance increased");
    }
}

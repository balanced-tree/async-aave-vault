// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {TestBase} from "./utils/TestBase.sol";
import {ISupplyBorrowVault} from "../src/interfaces/ISupplyBorrowVault.sol";

contract E2ETest is TestBase {
    function setUp() public override {
        super.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                     END-TO-END INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    // Full leveraged lifecycle: deposit → borrow + downstream deploy → yield → deleverage → redeem.
    // The USDC surplus from Morpho outperforming Aave interest stays in _accountedBorrowAssets and
    // shows up in totalAssets, but can only be redeemed as USDT up to (idle + Aave supply).
    // We convert that exact USDT amount back to shares and claim it — still yielding more than the
    // initial deposit thanks to Aave's USDT supply interest accruing over 30 days.
    function test_E2E_leveragedCycle() public {
        uint256 initialDeposit = 1000e6;
        uint256 aliceShares = _depositAs(alice, initialDeposit);

        // Enter leveraged position: borrow 300 USDC, deploy all to Morpho
        vm.prank(admin);
        uint256 downstreamShares = vault.executeStrategy(
            ISupplyBorrowVault.StrategyExecutionData({
                borrowAmount: 300e6,
                depositAmount: 300e6,
                minSharesRequired: 1
            })
        );

        vm.warp(block.timestamp + 30 days);

        // totalAssets includes Morpho position value — verify yield accrued
        assertGt(vault.totalAssets(), initialDeposit, "totalAssets grew from yield");

        // Exit: redeem Morpho shares and repay Aave debt in one call.
        // After 30 days, Morpho yield > Aave interest, so previewRedeem covers the full debt.
        uint256 repayAmount = vault.UNDERLYING_VAULT().previewRedeem(downstreamShares);
        vm.prank(admin);
        vault.deleverage(downstreamShares, repayAmount, 0);

        assertEq(vault.UNDERLYING_VAULT().balanceOf(address(vault)), 0, "no downstream shares remain");
        assertApproxEqAbs(spoke.getUserTotalDebt(USDC_RESERVE_ID, address(vault)), 0, 10, "debt cleared");

        // Post-deleverage: the USDC surplus from Morpho yield inflates totalAssets above what
        // can be sourced as USDT. Claim only the USDT-backed portion of alice's shares.
        uint256 availableUsdt =
            asset.balanceOf(address(vault)) + spoke.getUserSuppliedAssets(USDT_RESERVE_ID, address(vault));
        uint256 sharesToClaim = vault.convertToShares(availableUsdt);

        // sharesToClaim is always < aliceShares (USDC surplus holds the remainder)
        assertLt(sharesToClaim, aliceShares, "USDC surplus prevents claiming all shares as USDT");

        vm.prank(alice);
        vault.requestRedeem(sharesToClaim, alice, alice);

        assertEq(vault.pendingRedeemRequest(0, alice), sharesToClaim, "request recorded");
        assertEq(vault.maxRedeem(alice), 0, "nothing claimable before fulfillment");

        vm.prank(admin);
        uint256 fulfilledAssets = vault.fulfillRedeemRequest(alice, sharesToClaim);

        assertEq(vault.pendingRedeemRequest(0, alice), 0, "pending cleared after fulfillment");
        assertEq(vault.maxRedeem(alice), sharesToClaim, "shares claimable after fulfillment");

        vm.prank(alice);
        uint256 finalAssets = vault.redeem(sharesToClaim, alice, alice);

        assertEq(finalAssets, fulfilledAssets, "claimed equals fulfilled");
        assertGt(finalAssets, initialDeposit, "alice receives more USDT than her initial deposit");
    }

    // Two users deposit at different times; both request and receive correct independent redemptions.
    // Alice deposits first and benefits from 30 days of Aave USDT supply yield before Bob joins.
    // Each user's redemption is tracked separately; one fulfillment does not affect the other.
    function test_E2E_multiUser_independentRedemptions() public {
        // Alice deposits at initial price
        uint256 aliceShares = _depositAs(alice, 1000e6);

        // Yield accrues before Bob deposits — his shares will cost more per USDT
        vm.warp(block.timestamp + 30 days);

        // Bob deposits at the higher price (fewer shares for the same USDT)
        uint256 bobShares = _depositAs(bob, 1000e6);
        assertLt(bobShares, aliceShares, "bob gets fewer shares at higher price");

        // Both request full redemption
        vm.prank(alice);
        vault.requestRedeem(aliceShares, alice, alice);

        vm.prank(bob);
        vault.requestRedeem(bobShares, bob, bob);

        // Fulfill both — no debt, vault pulls from Aave as needed
        vm.prank(admin);
        vault.fulfillRedeemRequest(alice, aliceShares);

        vm.prank(admin);
        vault.fulfillRedeemRequest(bob, bobShares);

        assertEq(vault.pendingRedeemRequest(0, alice), 0, "alice pending cleared");
        assertEq(vault.pendingRedeemRequest(0, bob), 0, "bob pending cleared");

        // Both claim their USDT
        uint256 aliceBalBefore = asset.balanceOf(alice);
        vm.prank(alice);
        vault.redeem(aliceShares, alice, alice);
        uint256 aliceAssets = asset.balanceOf(alice) - aliceBalBefore;

        uint256 bobBalBefore = asset.balanceOf(bob);
        vm.prank(bob);
        vault.redeem(bobShares, bob, bob);
        uint256 bobAssets = asset.balanceOf(bob) - bobBalBefore;

        // Alice held for 30 days before Bob joined — she earns meaningful yield
        assertGt(aliceAssets, 1000e6, "alice receives more than she deposited");
        // Bob deposited and immediately redeemed — gets back approximately his deposit
        assertApproxEqAbs(bobAssets, 1000e6, 1e6, "bob receives approximately his deposit");
        // Alice's yield advantage is reflected in what she receives
        assertGt(aliceAssets, bobAssets, "alice earned more than bob");

        // Vault is fully wound down
        assertEq(vault.maxRedeem(alice), 0, "alice request fully consumed");
        assertEq(vault.maxRedeem(bob), 0, "bob request fully consumed");
    }
}

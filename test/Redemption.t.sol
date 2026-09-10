// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

// Internal
import {TestBase} from "./utils/TestBase.sol";
import {SupplyBorrowVault} from "../src/SupplyBorrowVault.sol";
import {ISupplyBorrowVault} from "../src/interfaces/ISupplyBorrowVault.sol";

import {IERC20} from "openzeppelin/interfaces/IERC20.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {ISpoke} from "aave-v4/spoke/interfaces/ISpoke.sol";

contract RedemptionTest is TestBase {
    using SafeERC20 for IERC20;

    function setUp() public override {
        super.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                            OPERATOR TESTS
    //////////////////////////////////////////////////////////////*/
    function test_SetOperator() public {
        vm.startPrank(alice);

        vm.expectRevert(ISupplyBorrowVault.INVALID_OPERATOR.selector);
        vault.setOperator(alice, true);

        vm.expectRevert(ISupplyBorrowVault.ZERO_ADDRESS.selector);
        vault.setOperator(address(0), true);

        vault.setOperator(bob, true);
        vm.stopPrank();

        assertEq(vault.operators(alice, bob), true);
    }

    /*//////////////////////////////////////////////////////////////
                            REDEEM TESTS
    //////////////////////////////////////////////////////////////*/
    function test_RequestRedeem_auth() public {
        uint256 shares = _depositAs(alice, 1000e6);

        vm.prank(bob);
        vm.expectRevert(ISupplyBorrowVault.UNAUTHORIZED.selector);
        vault.requestRedeem(shares, alice, alice);

        vm.prank(alice);
        vault.setOperator(bob, true);

        vm.prank(bob);
        vault.requestRedeem(shares, alice, alice);

        assertEq(vault.pendingRedeemRequest(0, alice), shares, "operator request recorded for owner");
    }

    function test_RequestRedeem_revertsOnZeroShares() public {
        vm.prank(alice);
        vm.expectRevert(ISupplyBorrowVault.ZERO_SHARES.selector);
        vault.requestRedeem(0, alice, alice);
    }

    function test_RequestRedeem_revertsOnZeroController() public {
        vm.prank(alice);
        vm.expectRevert(ISupplyBorrowVault.ZERO_ADDRESS.selector);
        vault.requestRedeem(1000e6, address(0), alice);
    }

    function test_RequestRedeem_revertsOnZeroOwner() public {
        vm.prank(alice);
        vm.expectRevert(ISupplyBorrowVault.ZERO_ADDRESS.selector);
        vault.requestRedeem(1000e6, alice, address(0));
    }

    function test_RequestRedeem_escrowed() public {
        uint256 shares = _depositAs(alice, 1000e6);

        vm.prank(alice);
        vault.requestRedeem(shares, alice, alice);

        assertEq(vault.balanceOf(alice), 0, "alice shares transferred out");
        assertEq(vault.balanceOf(address(vault)), shares, "vault holds escrowed shares");
        assertEq(vault.totalSupply(), shares, "escrowed shares still in totalSupply");
    }

    function test_RequestRedeem_accumulatesMultipleRequests() public {
        uint256 shares = _depositAs(alice, 2000e6);
        uint256 half = shares / 2;

        vm.prank(alice);
        vault.requestRedeem(half, alice, alice);
        assertEq(vault.pendingRedeemRequest(0, alice), half);

        vm.prank(alice);
        vault.requestRedeem(half, alice, alice);
        assertEq(vault.pendingRedeemRequest(0, alice), shares, "pending accumulates");
    }

    /*//////////////////////////////////////////////////////////////
                        FULFILL REDEEM TESTS
    //////////////////////////////////////////////////////////////*/
    function test_FulfillRedeemRequest_revertsOnZeroShares() public {
        vm.prank(admin);
        vm.expectRevert(ISupplyBorrowVault.ZERO_SHARES.selector);
        vault.fulfillRedeemRequest(alice, 0);
    }

    function test_FulfillRedeemRequest_revertsIfNotManager() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.fulfillRedeemRequest(alice, 1000e6);
    }

    function test_FulfillRedeemRequest_revertsIfSharesExceedPending() public {
        uint256 shares = _depositAs(alice, 1000e6);

        vm.prank(alice);
        vault.requestRedeem(shares / 2, alice, alice);

        vm.prank(admin);
        vm.expectRevert(ISupplyBorrowVault.INVALID_AMOUNT.selector);
        vault.fulfillRedeemRequest(alice, shares); // more than the pending half
    }

    function test_FulfillRedeemRequests_revertsOnLengthMismatch() public {
        address[] memory controllers = new address[](2);
        controllers[0] = alice;
        controllers[1] = bob;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1000e6;

        vm.prank(admin);
        vm.expectRevert(ISupplyBorrowVault.INVALID_AMOUNT.selector);
        vault.fulfillRedeemRequests(controllers, amounts);
    }

    function test_FulfillRedeemRequest_withDebtRevertsIfIdleInsufficient() public {
        // Deposit 1000e6: 700e6 rebalances to Aave, leaving 300e6 idle
        uint256 shares = _depositAs(alice, 1000e6);

        vm.prank(alice);
        vault.requestRedeem(shares, alice, alice);

        // Mock outstanding Aave debt so _ensureIdleAssets blocks collateral withdrawal
        vm.mockCall(
            address(spoke),
            abi.encodeCall(ISpoke.getUserTotalDebt, (USDC_RESERVE_ID, address(vault))),
            abi.encode(100e6)
        );

        // 300e6 idle < ~900e6 needed, and debt != 0 → INSUFFICIENT_LIQUIDITY
        vm.prank(admin);
        vm.expectRevert(ISupplyBorrowVault.INSUFFICIENT_LIQUIDITY.selector);
        vault.fulfillRedeemRequest(alice, shares);
    }

    function test_FulfillRedeemRequests_batchFulfillsCorrectly() public {
        uint256 aliceShares = _depositAs(alice, 1000e6);
        uint256 bobShares = _depositAs(bob, 500e6);

        vm.prank(alice);
        vault.requestRedeem(aliceShares, alice, alice);
        vm.prank(bob);
        vault.requestRedeem(bobShares, bob, bob);

        address[] memory controllers = new address[](2);
        controllers[0] = alice;
        controllers[1] = bob;

        uint256[] memory shares = new uint256[](2);
        shares[0] = aliceShares;
        shares[1] = bobShares;

        vm.prank(admin);
        uint256[] memory assets = vault.fulfillRedeemRequests(controllers, shares);

        assertEq(vault.maxRedeem(alice), aliceShares, "alice claimable shares");
        assertEq(vault.maxRedeem(bob), bobShares, "bob claimable shares");
        assertEq(vault.maxWithdraw(alice), assets[0], "alice claimable assets");
        assertEq(vault.maxWithdraw(bob), assets[1], "bob claimable assets");
        assertEq(vault.pendingRedeemRequest(0, alice), 0, "alice pending cleared");
        assertEq(vault.pendingRedeemRequest(0, bob), 0, "bob pending cleared");
    }

    function test_FulfillRedeemRequest_pullsFromAaveWhenNoDebt() public {
        // Deposit 1000e6: 700e6 rebalances to Aave, 300e6 stays idle
        uint256 shares = _depositAs(alice, 1000e6);

        uint256 aaveSupplyBefore = spoke.getUserSuppliedAssets(USDT_RESERVE_ID, address(vault));
        assertGt(aaveSupplyBefore, 0, "some assets supplied to Aave after deposit");

        vm.prank(alice);
        vault.requestRedeem(shares, alice, alice);

        // No debt: fulfill succeeds by pulling collateral from Aave to cover the idle shortfall
        vm.prank(admin);
        uint256 assets = vault.fulfillRedeemRequest(alice, shares);

        assertEq(vault.maxWithdraw(alice), assets, "claimable assets set");
        assertEq(vault.maxRedeem(alice), shares, "claimable shares set");
        assertEq(vault.pendingRedeemRequest(0, alice), 0, "pending cleared");

        uint256 aaveSupplyAfter = spoke.getUserSuppliedAssets(USDT_RESERVE_ID, address(vault));
        assertLt(aaveSupplyAfter, aaveSupplyBefore, "Aave supply reduced to fund redemption");
    }

    /// @dev E2E test of redeem flow without borrowing and underlying deposit
    function test_Redeem_E2E() public {
        uint256 shares = _depositAs(alice, 1000e6);
        vm.prank(alice);
        vault.requestRedeem(shares, alice, alice);

        assertEq(vault.balanceOf(alice), 0, "shares escrowed out of alice");
        assertEq(vault.pendingRedeemRequest(0, alice), shares, "pending == requested");
        assertEq(vault.maxRedeem(alice), 0, "nothing claimable before fulfillment");

        vm.prank(admin);
        uint256 fulfilledAssets = vault.fulfillRedeemRequest(alice, shares);

        assertEq(vault.pendingRedeemRequest(0, alice), 0, "pending cleared");
        assertEq(vault.maxRedeem(alice), shares, "claimable shares after fulfillment");
        assertEq(vault.maxWithdraw(alice), fulfilledAssets, "claimable assets after fulfillment");
        assertEq(vault.totalSupply(), 0, "escrowed shares burned at fulfillment");

        uint256 balBefore = asset.balanceOf(alice);
        vm.prank(alice);
        uint256 claimed = vault.redeem(shares, alice, alice);

        assertEq(claimed, fulfilledAssets, "claimed == fulfilled");
        assertEq(asset.balanceOf(alice) - balBefore, fulfilledAssets, "assets paid out");
        assertEq(vault.maxRedeem(alice), 0, "request fully consumed");

        assertApproxEqAbs(claimed, 1000e6, 10, "round-trip ~= deposit");
    }

    function test_Withdraw() public {
        uint256 shares = _depositAs(alice, 1000e6);
        vm.prank(alice);
        vault.requestRedeem(shares, alice, alice);

        vm.prank(admin);
        vault.fulfillRedeemRequest(alice, shares);

        uint256 claimableAssets = vault.maxWithdraw(alice);
        assertGt(claimableAssets, 0, "has claimable assets");

        uint256 balBefore = asset.balanceOf(alice);
        vm.prank(alice);
        uint256 burnedShares = vault.withdraw(claimableAssets, alice, alice);

        assertEq(asset.balanceOf(alice) - balBefore, claimableAssets, "assets paid out");
        assertEq(burnedShares, shares, "withdrawing all assets consumes all claimable shares");
        assertEq(vault.maxWithdraw(alice), 0, "no claimable assets left");
        assertEq(vault.maxRedeem(alice), 0, "no claimable shares left");
    }

    /*//////////////////////////////////////////////////////////////
                      WITHDRAW CLAIM GAP-FILLS
    //////////////////////////////////////////////////////////////*/
    function test_Withdraw_revertsOnZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(ISupplyBorrowVault.ZERO_AMOUNT.selector);
        vault.withdraw(0, alice, alice);
    }

    function test_Withdraw_revertsOnZeroReceiver() public {
        vm.prank(alice);
        vm.expectRevert(ISupplyBorrowVault.ZERO_ADDRESS.selector);
        vault.withdraw(1000e6, address(0), alice);
    }

    function test_Withdraw_revertsIfUnauthorized() public {
        vm.prank(bob);
        vm.expectRevert(ISupplyBorrowVault.UNAUTHORIZED.selector);
        vault.withdraw(1000e6, alice, alice);
    }

    function test_Withdraw_revertsIfExceedsClaimable() public {
        uint256 shares = _depositAs(alice, 1000e6);
        vm.prank(alice);
        vault.requestRedeem(shares, alice, alice);
        vm.prank(admin);
        vault.fulfillRedeemRequest(alice, shares);

        uint256 claimable = vault.maxWithdraw(alice);

        vm.prank(alice);
        vm.expectRevert(ISupplyBorrowVault.INVALID_AMOUNT.selector);
        vault.withdraw(claimable + 1, alice, alice);
    }

    function test_Withdraw_partial() public {
        uint256 shares = _depositAs(alice, 1000e6);
        vm.prank(alice);
        vault.requestRedeem(shares, alice, alice);
        vm.prank(admin);
        uint256 assets = vault.fulfillRedeemRequest(alice, shares);

        uint256 half = assets / 2;
        uint256 balBefore = asset.balanceOf(alice);
        vm.prank(alice);
        vault.withdraw(half, alice, alice);

        assertEq(asset.balanceOf(alice) - balBefore, half, "received half the assets");
        assertEq(vault.maxWithdraw(alice), assets - half, "remaining claimable assets");
        assertGt(vault.maxRedeem(alice), 0, "remaining claimable shares");
    }

    function test_Withdraw_operatorCanWithdraw() public {
        uint256 shares = _depositAs(alice, 1000e6);
        vm.prank(alice);
        vault.requestRedeem(shares, alice, alice);
        vm.prank(admin);
        uint256 assets = vault.fulfillRedeemRequest(alice, shares);

        vm.prank(alice);
        vault.setOperator(bob, true);

        uint256 balBefore = asset.balanceOf(alice);
        vm.prank(bob);
        vault.withdraw(assets, alice, alice);

        assertEq(asset.balanceOf(alice) - balBefore, assets, "alice received assets via operator");
        assertEq(vault.maxWithdraw(alice), 0, "nothing left claimable");
    }

    /*//////////////////////////////////////////////////////////////
                       REDEEM CLAIM GAP-FILLS
    //////////////////////////////////////////////////////////////*/
    function test_Redeem_revertsOnZeroShares() public {
        vm.prank(alice);
        vm.expectRevert(ISupplyBorrowVault.ZERO_AMOUNT.selector);
        vault.redeem(0, alice, alice);
    }

    function test_Redeem_revertsOnZeroReceiver() public {
        vm.prank(alice);
        vm.expectRevert(ISupplyBorrowVault.ZERO_ADDRESS.selector);
        vault.redeem(1000e6, address(0), alice);
    }

    function test_Redeem_revertsIfUnauthorized() public {
        vm.prank(bob);
        vm.expectRevert(ISupplyBorrowVault.UNAUTHORIZED.selector);
        vault.redeem(1000e6, alice, alice);
    }

    function test_Redeem_revertsIfExceedsClaimable() public {
        uint256 shares = _depositAs(alice, 1000e6);
        vm.prank(alice);
        vault.requestRedeem(shares, alice, alice);
        vm.prank(admin);
        vault.fulfillRedeemRequest(alice, shares);

        vm.prank(alice);
        vm.expectRevert(ISupplyBorrowVault.INVALID_AMOUNT.selector);
        vault.redeem(shares + 1, alice, alice);
    }

    function test_Redeem_partial() public {
        uint256 shares = _depositAs(alice, 1000e6);
        vm.prank(alice);
        vault.requestRedeem(shares, alice, alice);
        vm.prank(admin);
        uint256 assets = vault.fulfillRedeemRequest(alice, shares);

        uint256 halfShares = shares / 2;
        uint256 balBefore = asset.balanceOf(alice);
        vm.prank(alice);
        uint256 assetsReceived = vault.redeem(halfShares, alice, alice);

        assertEq(asset.balanceOf(alice) - balBefore, assetsReceived, "received correct assets");
        assertApproxEqAbs(assetsReceived, assets / 2, 1, "roughly half the total assets");
        assertEq(vault.maxRedeem(alice), shares - halfShares, "remaining claimable shares");
        assertGt(vault.maxWithdraw(alice), 0, "remaining claimable assets");
    }

    // Fuzz deposit amount and the share subset redeemed. Invariants across the full
    // request → fulfill → redeem cycle: pending clears, claimable tracks the fulfilled
    // amount, assets paid out match, and the vault is left in consistent state.
    function testFuzz_RequestAndFulfillRedeem(uint256 depositAmount, uint256 redeemFraction) public {
        depositAmount = bound(depositAmount, 1e6, 1e12);
        uint256 shares = _depositAs(alice, depositAmount);

        // redeemFraction ∈ [1, shares] so we always redeem at least 1 share
        uint256 sharesToRedeem = bound(redeemFraction, 1, shares);

        vm.prank(alice);
        vault.requestRedeem(sharesToRedeem, alice, alice);

        assertEq(vault.pendingRedeemRequest(0, alice), sharesToRedeem, "pending set after request");
        assertEq(vault.balanceOf(alice), shares - sharesToRedeem, "escrowed shares leave alice");
        assertEq(vault.maxRedeem(alice), 0, "nothing claimable before fulfillment");

        vm.prank(admin);
        uint256 fulfilledAssets = vault.fulfillRedeemRequest(alice, sharesToRedeem);

        assertGt(fulfilledAssets, 0, "fulfilled assets must be > 0");
        assertEq(vault.pendingRedeemRequest(0, alice), 0, "pending cleared after fulfillment");
        assertEq(vault.maxRedeem(alice), sharesToRedeem, "claimable shares set");
        assertEq(vault.maxWithdraw(alice), fulfilledAssets, "claimable assets set");

        uint256 balBefore = asset.balanceOf(alice);
        vm.prank(alice);
        uint256 claimed = vault.redeem(sharesToRedeem, alice, alice);

        assertEq(claimed, fulfilledAssets, "claimed equals fulfilled");
        assertEq(asset.balanceOf(alice) - balBefore, claimed, "assets paid out to alice");
        assertEq(vault.maxRedeem(alice), 0, "claimable fully consumed");
        assertEq(vault.maxWithdraw(alice), 0, "no claimable assets remain");
    }

    function test_Redeem_operatorCanRedeem() public {
        uint256 shares = _depositAs(alice, 1000e6);
        vm.prank(alice);
        vault.requestRedeem(shares, alice, alice);
        vm.prank(admin);
        uint256 assets = vault.fulfillRedeemRequest(alice, shares);

        vm.prank(alice);
        vault.setOperator(bob, true);

        uint256 balBefore = asset.balanceOf(alice);
        vm.prank(bob);
        vault.redeem(shares, alice, alice);

        assertEq(asset.balanceOf(alice) - balBefore, assets, "alice received assets via operator");
        assertEq(vault.maxRedeem(alice), 0, "nothing left claimable");
    }

    // Fuzz deposit amount and the share subset redeemed. Invariants across the full
    // request → fulfill → redeem cycle: pending clears, claimable tracks the fulfilled
    // amount, assets paid out match, and the vault is left in consistent state.
    function testFuzz_RequestAndFulfillRedeem(uint256 depositAmount, uint256 redeemFraction) public {
        depositAmount = bound(depositAmount, 1e6, 1e12);
        uint256 shares = _depositAs(alice, depositAmount);

        // redeemFraction ∈ [1, shares] so we always redeem at least 1 share
        uint256 sharesToRedeem = bound(redeemFraction, 1, shares);

        vm.prank(alice);
        vault.requestRedeem(sharesToRedeem, alice, alice);

        assertEq(vault.pendingRedeemRequest(0, alice), sharesToRedeem, "pending set after request");
        assertEq(vault.balanceOf(alice), shares - sharesToRedeem, "escrowed shares leave alice");
        assertEq(vault.maxRedeem(alice), 0, "nothing claimable before fulfillment");

        vm.prank(admin);
        uint256 fulfilledAssets = vault.fulfillRedeemRequest(alice, sharesToRedeem);

        // fulfilledAssets may be 0 for dust (1 share when Aave rounding makes pps < 1)
        assertEq(vault.pendingRedeemRequest(0, alice), 0, "pending cleared after fulfillment");
        assertEq(vault.maxRedeem(alice), sharesToRedeem, "claimable shares set");
        assertEq(vault.maxWithdraw(alice), fulfilledAssets, "claimable assets set");

        uint256 balBefore = asset.balanceOf(alice);
        vm.prank(alice);
        uint256 claimed = vault.redeem(sharesToRedeem, alice, alice);

        assertEq(claimed, fulfilledAssets, "claimed equals fulfilled");
        assertEq(asset.balanceOf(alice) - balBefore, claimed, "assets paid out to alice");
        assertEq(vault.maxRedeem(alice), 0, "claimable fully consumed");
        assertEq(vault.maxWithdraw(alice), 0, "no claimable assets remain");
    }
}
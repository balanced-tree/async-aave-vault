// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

// Internal
import {TestBase} from "./utils/TestBase.sol";
import {ISupplyBorrowVault} from "../src/interfaces/ISupplyBorrowVault.sol";

import {IERC20} from "openzeppelin/interfaces/IERC20.sol";
import {ISpoke} from "aave-v4/spoke/interfaces/ISpoke.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";

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

    /*//////////////////////////////////////////////////////////////
                            WITHDRAW TESTS
    //////////////////////////////////////////////////////////////*/

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

}
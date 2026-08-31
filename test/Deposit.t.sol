// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

// Internal
import {TestBase} from "./utils/TestBase.sol";
import {ISupplyBorrowVault} from "../src/interfaces/ISupplyBorrowVault.sol";

import {IERC20} from "openzeppelin/interfaces/IERC20.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {ISpoke, ReserveFlags} from "aave-v4/spoke/interfaces/ISpoke.sol";

// Deposit and mint tests
contract DepositTest is TestBase {
    using SafeERC20 for IERC20;

    function setUp() public override {
        super.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                             DEPOSIT TESTS
    //////////////////////////////////////////////////////////////*/
    function test_Deposit_revertsOnZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(ISupplyBorrowVault.ZERO_AMOUNT.selector);
        vault.deposit(0, alice);
    }

    function test_Deposit_revertsOnZeroReceiver() public {
        vm.startPrank(alice);
        asset.forceApprove(address(vault), 1000e6);
        vm.expectRevert(ISupplyBorrowVault.ZERO_ADDRESS.selector);
        vault.deposit(1000e6, address(0));
        vm.stopPrank();
    }

    function test_Deposit_revertsWhenReservePaused() public {
        ISpoke.Reserve memory reserve = spoke.getReserve(USDT_RESERVE_ID);
        reserve.flags = ReserveFlags.wrap(ReserveFlags.unwrap(reserve.flags) | 0x01);

        vm.mockCall(
            address(spoke),
            abi.encodeCall(ISpoke.getReserve, (USDT_RESERVE_ID)),
            abi.encode(reserve)
        );

        vm.startPrank(alice);
        asset.forceApprove(address(vault), 1000e6);
        vm.expectRevert(ISupplyBorrowVault.MAX_DEPOSIT_EXCEEDED.selector);
        vault.deposit(1000e6, alice);
        vm.stopPrank();
    }

    function test_Deposit_firstSharesAtParity() public {
        uint256 depositAmount = 1000e6;
        uint256 shares = _depositAs(alice, depositAmount);

        // With virtual assets/shares of 1, first deposit is exactly 1:1
        assertEq(shares, depositAmount);
        assertEq(vault.balanceOf(alice), shares);
        assertEq(vault.totalSupply(), shares);
    }

    function test_Deposit_rebalancesIdleToAave() public {
        // targetIdleBps = 3000 (30%), minSupplyAmount = 50e6
        // deposit 1000e6: excessIdle = 700e6 > 50e6, so 700e6 is supplied to Aave
        uint256 depositAmount = 1000e6;
        _depositAs(alice, depositAmount);

        uint256 targetIdle = depositAmount * 3000 / 10_000;
        uint256 expectedSupplied = depositAmount - targetIdle;

        uint256 aaveSupply = spoke.getUserSuppliedAssets(USDT_RESERVE_ID, address(vault));
        assertApproxEqAbs(aaveSupply, expectedSupplied, 1, "excess idle should be supplied to Aave");
    }

    function test_Deposit_doesNotRebalanceIfExcessBelowMinSupply() public {
        // With minSupplyAmount = 50e6 and targetIdleBps = 3000,
        // a 40e6 deposit has excessIdle = 28e6 < 50e6 — no supply to Aave
        _depositAs(alice, 40e6);

        uint256 aaveSupply = spoke.getUserSuppliedAssets(USDT_RESERVE_ID, address(vault));
        assertEq(aaveSupply, 0, "small deposit should stay idle");
    }

    function test_Deposit_multipleUsersSharesProportional() public {
        uint256 sharesAlice = _depositAs(alice, 1000e6);
        uint256 sharesBob = _depositAs(bob, 500e6);

        // No yield between deposits, so pps is unchanged — Bob gets exactly half Alice's shares
        assertEq(sharesBob, sharesAlice / 2);
        assertEq(vault.totalSupply(), sharesAlice + sharesBob);
    }

    /*//////////////////////////////////////////////////////////////
                              MINT TESTS
    //////////////////////////////////////////////////////////////*/
    function test_Mint_revertsOnZeroShares() public {
        vm.prank(alice);
        vm.expectRevert(ISupplyBorrowVault.ZERO_AMOUNT.selector);
        vault.mint(0, alice);
    }

    function test_Mint_revertsOnZeroReceiver() public {
        vm.prank(alice);
        vm.expectRevert(ISupplyBorrowVault.ZERO_ADDRESS.selector);
        vault.mint(1000e6, address(0));
    }

    function test_Mint_revertsWhenReservePaused() public {
        ISpoke.Reserve memory reserve = spoke.getReserve(USDT_RESERVE_ID);
        reserve.flags = ReserveFlags.wrap(ReserveFlags.unwrap(reserve.flags) | 0x01);

        vm.mockCall(
            address(spoke),
            abi.encodeCall(ISpoke.getReserve, (USDT_RESERVE_ID)),
            abi.encode(reserve)
        );

        vm.prank(alice);
        vm.expectRevert(ISupplyBorrowVault.MAX_MINT_EXCEEDED.selector);
        vault.mint(1000e6, alice);
    }

    function test_Mint_correctAssetsCharged() public {
        uint256 sharesToMint = 1000e6;
        uint256 previewedAssets = vault.previewMint(sharesToMint);

        uint256 balBefore = asset.balanceOf(alice);
        vm.startPrank(alice);
        asset.forceApprove(address(vault), previewedAssets);
        uint256 assetsCharged = vault.mint(sharesToMint, alice);
        vm.stopPrank();

        assertEq(assetsCharged, previewedAssets, "charged assets match previewMint");
        assertEq(asset.balanceOf(alice), balBefore - assetsCharged, "correct assets deducted from alice");
        assertEq(vault.balanceOf(alice), sharesToMint, "correct shares minted to alice");
    }
}
// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

// Internal
import {TestBase} from "./utils/TestBase.sol";
import {SupplyBorrowVault} from "../src/SupplyBorrowVault.sol";
import {ISupplyBorrowVault} from "../src/interfaces/ISupplyBorrowVault.sol";

import {IERC20} from "openzeppelin/interfaces/IERC20.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {ISpoke, ReserveFlags} from "aave-v4/spoke/interfaces/ISpoke.sol";

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
}
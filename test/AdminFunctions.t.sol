// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

// Internal
import {TestBase} from "./utils/TestBase.sol";
import {SupplyBorrowVault} from "../src/SupplyBorrowVault.sol";
import {ISupplyBorrowVault} from "../src/interfaces/ISupplyBorrowVault.sol";

import {IERC20} from "openzeppelin/interfaces/IERC20.sol";
import {ISpoke} from "aave-v4/spoke/interfaces/ISpoke.sol";
import {IERC4626} from "openzeppelin/interfaces/IERC4626.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";

contract AdminFunctionsTest is TestBase {
    using SafeERC20 for IERC20;

    function setUp() public override {
        super.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// --- Set Manager --- ///

    function test_SetManager() public {
        assertEq(vault.manager(), admin);

        vm.prank(admin);
        vault.setManager(alice);
        assertEq(vault.manager(), alice);
    }

    function test_SetManager_revertsOnZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(ISupplyBorrowVault.ZERO_ADDRESS.selector);
        vault.setManager(address(0));
    }

    function test_SetManager_revertsIfAlreadyManager() public {
        // admin already holds MANAGER_ROLE from construction
        vm.prank(admin);
        vm.expectRevert(ISupplyBorrowVault.INVALID_MANAGER.selector);
        vault.setManager(admin);
    }

    function test_SetManager_revokesOldManagerRole() public {
        vm.prank(admin);
        vault.setManager(alice);

        assertEq(vault.manager(), alice);
        assertFalse(vault.hasRole(keccak256("MANAGER_ROLE"), admin), "old manager should lose role");

        // admin can no longer call manager-only functions
        vm.prank(admin);
        vm.expectRevert();
        vault.setMinSupplyAmount(100e6);
    }

    /// --- Set Target Idle Bps --- ///

    function test_SetTargetIdleBps() public {
        assertEq(vault.targetIdleBps(), 3000);

        vm.expectRevert();
        vault.setTargetIdleBps(4000);

        vm.startPrank(admin);

        vm.expectRevert();
        vault.setTargetIdleBps(7000);

        vault.setTargetIdleBps(4000);
        vm.stopPrank();
        assertEq(vault.targetIdleBps(), 4000);
    }

    function test_SetTargetIdleBps_allowsZero() public {
        // setTargetIdleBps has no lower-bound guard (unlike constructor), so 0 is accepted
        vm.prank(admin);
        vault.setTargetIdleBps(0);
        assertEq(vault.targetIdleBps(), 0);
    }

    /// --- Set Performance Fee --- ///

    function test_SetPerformanceFee() public {
        vm.expectRevert();
        vault.setPerformanceFee(4000);

        vm.startPrank(admin);
        vm.expectRevert();
        vault.setPerformanceFee(7000);

        vault.setPerformanceFee(4000);
        vm.stopPrank();

        assertEq(vault.performanceFee(), 4000);
    }

    function test_SetPerformanceFee_allowsMaxFee() public {
        vm.prank(admin);
        vault.setPerformanceFee(5000);
        assertEq(vault.performanceFee(), 5000);
    }

    /// --- Set Min Supply Amount --- ///

    function test_SetMinSupplyAmount() public {
        assertEq(vault.minSupplyAmount(), 50000000);

        vm.expectRevert();
        vault.setMinSupplyAmount(1000e6);

        vm.startPrank(admin);
        vault.setMinSupplyAmount(100e6);
        vm.stopPrank();
        assertEq(vault.minSupplyAmount(), 100e6);
    }

    function test_SetMinSupplyAmount_revertsOnZero() public {
        vm.prank(admin);
        vm.expectRevert(ISupplyBorrowVault.ZERO_AMOUNT.selector);
        vault.setMinSupplyAmount(0);
    }

    /// --- Set Min Health Factor --- ///

    function test_SetMinHealthFactor() public {
        assertEq(vault.minHealthFactor(), 1.3e18);

        vm.expectRevert();
        vault.setMinHealthFactor(11000);

        vm.startPrank(admin);
        vm.expectRevert();
        vault.setMinHealthFactor(1.2e18);

        vault.setMinHealthFactor(1.7e18);
        vm.stopPrank();
        assertEq(vault.minHealthFactor(), 1.7e18);
    }
}
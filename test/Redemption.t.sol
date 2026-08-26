// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

// Internal
import {TestBase} from "./utils/TestBase.sol";
import {SupplyBorrowVault} from "../src/SupplyBorrowVault.sol";
import {ISupplyBorrowVault} from "../src/interfaces/ISupplyBorrowVault.sol";

import {IERC20} from "openzeppelin/interfaces/IERC20.sol";
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

}
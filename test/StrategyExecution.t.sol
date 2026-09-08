// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {TestBase} from "./utils/TestBase.sol";
import {ISupplyBorrowVault} from "../src/interfaces/ISupplyBorrowVault.sol";

import {IERC20} from "openzeppelin/interfaces/IERC20.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {ISpoke} from "aave-v4/spoke/interfaces/ISpoke.sol";

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
}
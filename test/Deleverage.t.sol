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
}

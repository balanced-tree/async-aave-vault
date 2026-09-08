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

        vm.prank(admin);
        vault.deleverage(halfShares, 150e6, 0);

        assertApproxEqAbs(
            vault.UNDERLYING_VAULT().balanceOf(address(vault)),
            allShares - halfShares,
            1,
            "half downstream shares redeemed"
        );
        assertLt(spoke.getUserTotalDebt(USDC_RESERVE_ID, address(vault)), debtBefore, "Aave debt reduced");
        assertApproxEqAbs(
            spoke.getUserTotalDebt(USDC_RESERVE_ID, address(vault)),
            debtBefore - 150e6,
            1e6,
            "debt reduced by repay amount"
        );
    }

    function test_Deleverage_fullUnwind() public {
        uint256 allShares = _setupLeveragedPosition(1000e6, 300e6);

        // Step 1: pull all USDC back from Morpho into _accountedBorrowAssets
        vm.prank(admin);
        vault.deleverage(allShares, 0, 0);

        assertEq(vault.UNDERLYING_VAULT().balanceOf(address(vault)), 0, "no downstream shares remain");

        // Step 2: repay all Aave debt then free all collateral
        uint256 debt = spoke.getUserTotalDebt(USDC_RESERVE_ID, address(vault));
        uint256 aaveSupply = spoke.getUserSuppliedAssets(USDT_RESERVE_ID, address(vault));
        uint256 vaultUsdtBefore = asset.balanceOf(address(vault));

        vm.prank(admin);
        vault.deleverage(0, debt, aaveSupply);

        assertApproxEqAbs(spoke.getUserTotalDebt(USDC_RESERVE_ID, address(vault)), 0, 1, "Aave debt cleared");
        assertApproxEqAbs(spoke.getUserSuppliedAssets(USDT_RESERVE_ID, address(vault)), 0, 1e6, "Aave supply cleared");
        assertApproxEqAbs(
            asset.balanceOf(address(vault)),
            vaultUsdtBefore + aaveSupply,
            1e6,
            "vault USDT balance reflects freed collateral"
        );
    }
}

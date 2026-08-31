// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {TestBase} from "./utils/TestBase.sol";
import {ISupplyBorrowVault} from "../src/interfaces/ISupplyBorrowVault.sol";

import {IERC20} from "openzeppelin/interfaces/IERC20.sol";
import {IERC4626} from "openzeppelin/interfaces/IERC4626.sol";
import {IERC165} from "openzeppelin/utils/introspection/IERC165.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {ISpoke, ReserveFlags} from "aave-v4/spoke/interfaces/ISpoke.sol";
import {IERC7540Operator, IERC7540Redeem} from "centrifuge/misc/interfaces/IERC7540.sol";

contract ViewFunctionsTest is TestBase {
    using SafeERC20 for IERC20;

    function setUp() public override {
        super.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                          ERC4626 VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function test_PreviewWithdraw_reverts() public {
        vm.expectRevert(ISupplyBorrowVault.NOT_IMPLEMENTED.selector);
        vault.previewWithdraw(1000e6);
    }

    function test_PreviewRedeem_reverts() public {
        vm.expectRevert(ISupplyBorrowVault.NOT_IMPLEMENTED.selector);
        vault.previewRedeem(1000e6);
    }

    function test_ConvertToShares_roundTrip() public {
        _depositAs(alice, 1000e6);

        uint256 x = 500e6;
        uint256 shares = vault.convertToShares(x);
        uint256 back = vault.convertToAssets(shares);

        // Double-floor rounding may lose at most 1 wei
        assertApproxEqAbs(back, x, 1, "round-trip within 1 wei");
    }

    function test_MaxDeposit_zeroWhenPaused() public {
        ISpoke.Reserve memory reserve = spoke.getReserve(USDT_RESERVE_ID);
        reserve.flags = ReserveFlags.wrap(ReserveFlags.unwrap(reserve.flags) | 0x01);

        vm.mockCall(
            address(spoke),
            abi.encodeCall(ISpoke.getReserve, (USDT_RESERVE_ID)),
            abi.encode(reserve)
        );

        assertEq(vault.maxDeposit(alice), 0);
    }

    function test_MaxMint_zeroWhenPaused() public {
        ISpoke.Reserve memory reserve = spoke.getReserve(USDT_RESERVE_ID);
        reserve.flags = ReserveFlags.wrap(ReserveFlags.unwrap(reserve.flags) | 0x01);

        vm.mockCall(
            address(spoke),
            abi.encodeCall(ISpoke.getReserve, (USDT_RESERVE_ID)),
            abi.encode(reserve)
        );

        assertEq(vault.maxMint(alice), 0);
    }

    function test_MaxWithdraw_maxRedeem_beforeAndAfterFulfill() public {
        uint256 shares = _depositAs(alice, 1000e6);

        assertEq(vault.maxWithdraw(alice), 0, "nothing claimable before request");
        assertEq(vault.maxRedeem(alice), 0, "nothing claimable before request");

        vm.prank(alice);
        vault.requestRedeem(shares, alice, alice);

        assertEq(vault.maxWithdraw(alice), 0, "nothing claimable while pending");
        assertEq(vault.maxRedeem(alice), 0, "nothing claimable while pending");

        vm.prank(admin);
        uint256 assets = vault.fulfillRedeemRequest(alice, shares);

        assertEq(vault.maxWithdraw(alice), assets, "claimable assets after fulfillment");
        assertEq(vault.maxRedeem(alice), shares, "claimable shares after fulfillment");
    }

    /*//////////////////////////////////////////////////////////////
                          SUPPORTS INTERFACE
    //////////////////////////////////////////////////////////////*/
    function test_SupportsInterface_ERC4626() public view {
        assertTrue(vault.supportsInterface(type(IERC4626).interfaceId));
    }

    function test_SupportsInterface_ERC165() public view {
        assertTrue(vault.supportsInterface(type(IERC165).interfaceId));
    }

    function test_SupportsInterface_ERC7540Redeem() public view {
        assertTrue(vault.supportsInterface(type(IERC7540Redeem).interfaceId));
    }

    function test_SupportsInterface_ERC7540Operator() public view {
        assertTrue(vault.supportsInterface(type(IERC7540Operator).interfaceId));
    }

    function test_SupportsInterface_unknownReturnsFalse() public view {
        assertFalse(vault.supportsInterface(0xdeadbeef));
    }
}
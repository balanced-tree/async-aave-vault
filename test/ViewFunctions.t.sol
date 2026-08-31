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
}
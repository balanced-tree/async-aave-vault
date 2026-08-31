// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

// Internal
import {TestBase} from "./utils/TestBase.sol";
import {SupplyBorrowVault} from "../src/SupplyBorrowVault.sol";
import {ISupplyBorrowVault} from "../src/interfaces/ISupplyBorrowVault.sol";

import {IERC20} from "openzeppelin/interfaces/IERC20.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";

contract ViewFunctionsTest is TestBase {
    using SafeERC20 for IERC20;

    function setUp() public override {
        super.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/
}
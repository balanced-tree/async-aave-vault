// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

// Internal
import {TestBase} from "./TestBase.sol";
import {SupplyBorrowVault} from "../src/SupplyBorrowVault.sol";
import {ISupplyBorrowVault} from "../src/interfaces/ISupplyBorrowVault.sol";

import {IERC20} from "openzeppelin/interfaces/IERC20.sol";

contract SupplyBorrowVaultTest is TestBase {
    IERC20 public asset;
    IERC20 public borrowAsset;

    SupplyBorrowVault public vault;
    string public name = "SupplyBorrowVault";
    string public symbol = "SBV";

    function setUp() public override {
        super.setUp();

        vm.selectFork(forks[ETH]);

        asset = IERC20(tokens[ETH][USDT_KEY]);
        borrowAsset = IERC20(tokens[ETH][USDC_KEY]);

        vault = new SupplyBorrowVault(tokens[ETH][USDT_KEY], admin, treasury, 3000, name, symbol);
    }

    function testConstructor() public view {
        assertEq(vault.asset(), tokens[ETH][USDT_KEY]);
        assertEq(vault.name(), name);
        assertEq(vault.symbol(), symbol);
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function test_SetManager() public {
        assertEq(vault.manager(), admin);

        vm.expectRevert();
        vault.setManager(alice);

        vm.prank(admin);
        vault.setManager(alice);
        assertEq(vault.manager(), alice);
    }
}

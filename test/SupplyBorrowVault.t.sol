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

        vault = new SupplyBorrowVault(tokens[ETH][USDT_KEY], admin, treasury, spokeAddresses[ETH], USDT_RESERVE_ID, 3000, 3000, name, symbol);
    }

    function test_Constructor() public view {
        assertEq(vault.asset(), tokens[ETH][USDT_KEY]);
        assertEq(vault.SPOKE_ADDRESS(), spokeAddresses[ETH]);
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

    /*//////////////////////////////////////////////////////////////
                           HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function _depositAs(address user, uint256 amount) internal returns (uint256 shares) {
        vm.startPrank(user);
        asset.forceApprove(address(vault), amount);
        shares = vault.deposit(amount, user);
        vm.stopPrank();
    }

    function _mintAs(address user, uint256 shares) internal returns (uint256 assets) {
        vm.startPrank(user);
        asset.forceApprove(address(vault), shares);
        assets = vault.mint(shares, user);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        COST BASIS TESTS
    //////////////////////////////////////////////////////////////*/
    function test_CostBasis_firstDeposit() public {
        // Empty vault so pps should be 1
        _depositAs(alice, 1000e6);

        assertEq(vault.costBasisPerShare(alice), 1e18);
    }
}

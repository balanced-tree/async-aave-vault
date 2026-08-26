// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

// Internal
import {TestBase} from "./utils/TestBase.sol";
import {SupplyBorrowVault} from "../src/SupplyBorrowVault.sol";
import {ISupplyBorrowVault} from "../src/interfaces/ISupplyBorrowVault.sol";

import {IERC20} from "openzeppelin/interfaces/IERC20.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";

contract VaultCreationTest is TestBase {
    using SafeERC20 for IERC20;

    function setUp() public override {
        super.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                       CONSTRUCTOR VALIDATION
    //////////////////////////////////////////////////////////////*/
    function test_Constructor_revertsOnZeroAdmin() public {
        vm.expectRevert(ISupplyBorrowVault.ZERO_ADDRESS.selector);
        new SupplyBorrowVault(
            tokens[ETH][USDT_KEY],
            address(0),
            treasury,
            spokeAddresses[ETH],
            ETH_MORPHO_VAULT,
            USDT_RESERVE_ID,
            USDC_RESERVE_ID,
            3000,
            3000,
            "Test",
            "TST"
        );
    }

    function test_Constructor_revertsOnZeroTreasury() public {
        vm.expectRevert(ISupplyBorrowVault.ZERO_ADDRESS.selector);
        new SupplyBorrowVault(
            tokens[ETH][USDT_KEY],
            admin,
            address(0),
            spokeAddresses[ETH],
            ETH_MORPHO_VAULT,
            USDT_RESERVE_ID,
            USDC_RESERVE_ID,
            3000,
            3000,
            "Test",
            "TST"
        );
    }

    function test_Constructor_revertsOnZeroAsset() public {
        vm.expectRevert(ISupplyBorrowVault.INVALID_ASSET.selector);
        new SupplyBorrowVault(
            address(0),
            admin,
            treasury,
            spokeAddresses[ETH],
            ETH_MORPHO_VAULT,
            USDT_RESERVE_ID,
            USDC_RESERVE_ID,
            3000,
            3000,
            "Test",
            "TST"
        );
    }

    function test_Constructor_revertsOnNonContractAsset() public {
        vm.expectRevert(ISupplyBorrowVault.INVALID_ASSET.selector);
        new SupplyBorrowVault(
            makeAddr("eoa"),
            admin,
            treasury,
            spokeAddresses[ETH],
            ETH_MORPHO_VAULT,
            USDT_RESERVE_ID,
            USDC_RESERVE_ID,
            3000,
            3000,
            "Test",
            "TST"
        );
    }

    function test_Constructor_revertsOnZeroSpoke() public {
        vm.expectRevert(ISupplyBorrowVault.ZERO_ADDRESS.selector);
        new SupplyBorrowVault(
            tokens[ETH][USDT_KEY],
            admin,
            treasury,
            address(0),
            ETH_MORPHO_VAULT,
            USDT_RESERVE_ID,
            USDC_RESERVE_ID,
            3000,
            3000,
            "Test",
            "TST"
        );
    }

    function test_Constructor_revertsOnZeroDownstreamVault() public {
        vm.expectRevert(ISupplyBorrowVault.ZERO_ADDRESS.selector);
        new SupplyBorrowVault(
            tokens[ETH][USDT_KEY],
            admin,
            treasury,
            spokeAddresses[ETH],
            address(0),
            USDT_RESERVE_ID,
            USDC_RESERVE_ID,
            3000,
            3000,
            "Test",
            "TST"
        );
    }

    function test_Constructor_revertsOnMatchingReserveIds() public {
        vm.expectRevert(ISupplyBorrowVault.INVALID_ASSET.selector);
        new SupplyBorrowVault(
            tokens[ETH][USDT_KEY],
            admin,
            treasury,
            spokeAddresses[ETH],
            ETH_MORPHO_VAULT,
            USDT_RESERVE_ID,
            USDT_RESERVE_ID,
            3000,
            3000,
            "Test",
            "TST"
        );
    }

    function test_Constructor_revertsOnReserveAssetMismatch() public {
        // USDC reserve as the supply reserve, but asset is USDT — reserve.underlying (USDC) != asset (USDT)
        vm.expectRevert(ISupplyBorrowVault.INVALID_ASSET.selector);
        new SupplyBorrowVault(
            tokens[ETH][USDT_KEY],
            admin,
            treasury,
            spokeAddresses[ETH],
            ETH_MORPHO_VAULT,
            USDC_RESERVE_ID,
            USDT_RESERVE_ID,
            3000,
            3000,
            "Test",
            "TST"
        );
    }

    function test_Constructor_revertsOnDownstreamVaultAssetMismatch() public {
        // Morpho vault asset is USDC; WETH borrow reserve underlying is WETH — mismatch
        vm.expectRevert(ISupplyBorrowVault.INVALID_ASSET.selector);
        new SupplyBorrowVault(
            tokens[ETH][USDT_KEY],
            admin,
            treasury,
            spokeAddresses[ETH],
            ETH_MORPHO_VAULT,
            USDT_RESERVE_ID,
            WETH_RESERVE_ID,
            3000,
            3000,
            "Test",
            "TST"
        );
    }

    function test_Constructor_revertsOnZeroTargetIdleBps() public {
        vm.expectRevert(ISupplyBorrowVault.INVALID_AMOUNT.selector);
        new SupplyBorrowVault(
            tokens[ETH][USDT_KEY],
            admin,
            treasury,
            spokeAddresses[ETH],
            ETH_MORPHO_VAULT,
            USDT_RESERVE_ID,
            USDC_RESERVE_ID,
            0,
            3000,
            "Test",
            "TST"
        );
    }

    function test_Constructor_revertsOnExcessiveTargetIdleBps() public {
        vm.expectRevert(ISupplyBorrowVault.INVALID_AMOUNT.selector);
        new SupplyBorrowVault(
            tokens[ETH][USDT_KEY],
            admin,
            treasury,
            spokeAddresses[ETH],
            ETH_MORPHO_VAULT,
            USDT_RESERVE_ID,
            USDC_RESERVE_ID,
            4001,
            3000,
            "Test",
            "TST"
        );
    }

    function test_Constructor_revertsOnExcessivePerformanceFee() public {
        vm.expectRevert(ISupplyBorrowVault.INVALID_FEE_AMOUNT.selector);
        new SupplyBorrowVault(
            tokens[ETH][USDT_KEY],
            admin,
            treasury,
            spokeAddresses[ETH],
            ETH_MORPHO_VAULT,
            USDT_RESERVE_ID,
            USDC_RESERVE_ID,
            3000,
            5001,
            "Test",
            "TST"
        );
    }

    function test_Constructor_setsRolesCorrectly() public view {
        bytes32 defaultAdminRole = bytes32(0);
        bytes32 managerRole = keccak256("MANAGER_ROLE");

        assertTrue(vault.hasRole(defaultAdminRole, admin));
        assertTrue(vault.hasRole(managerRole, admin));
        assertEq(vault.manager(), admin);
    }

    /*//////////////////////////////////////////////////////////////
                            REDEEM TESTS
    //////////////////////////////////////////////////////////////*/
    function test_RequestRedeem_auth() public {
        uint256 shares = _depositAs(alice, 1000e6);

        vm.prank(bob);
        vm.expectRevert(ISupplyBorrowVault.UNAUTHORIZED.selector);
        vault.requestRedeem(shares, alice, alice);

        vm.prank(alice);
        vault.setOperator(bob, true);

        vm.prank(bob);
        vault.requestRedeem(shares, alice, alice);

        assertEq(vault.pendingRedeemRequest(0, alice), shares, "operator request recorded for owner");
    }

    /// @dev E2E test of redeem flow without borrowing and underlying deposit
    function test_Redeem_E2E() public {
        uint256 shares = _depositAs(alice, 1000e6);
        vm.prank(alice);
        vault.requestRedeem(shares, alice, alice);

        assertEq(vault.balanceOf(alice), 0, "shares escrowed out of alice");
        assertEq(vault.pendingRedeemRequest(0, alice), shares, "pending == requested");
        assertEq(vault.maxRedeem(alice), 0, "nothing claimable before fulfillment");

        vm.prank(admin);
        uint256 fulfilledAssets = vault.fulfillRedeemRequest(alice, shares);

        assertEq(vault.pendingRedeemRequest(0, alice), 0, "pending cleared");
        assertEq(vault.maxRedeem(alice), shares, "claimable shares after fulfillment");
        assertEq(vault.maxWithdraw(alice), fulfilledAssets, "claimable assets after fulfillment");
        assertEq(vault.totalSupply(), 0, "escrowed shares burned at fulfillment");

        uint256 balBefore = asset.balanceOf(alice);
        vm.prank(alice);
        uint256 claimed = vault.redeem(shares, alice, alice);

        assertEq(claimed, fulfilledAssets, "claimed == fulfilled");
        assertEq(asset.balanceOf(alice) - balBefore, fulfilledAssets, "assets paid out");
        assertEq(vault.maxRedeem(alice), 0, "request fully consumed");

        assertApproxEqAbs(claimed, 1000e6, 10, "round-trip ~= deposit");
    }

    function test_Withdraw() public {
        uint256 shares = _depositAs(alice, 1000e6);
        vm.prank(alice);
        vault.requestRedeem(shares, alice, alice);

        vm.prank(admin);
        vault.fulfillRedeemRequest(alice, shares);

        uint256 claimableAssets = vault.maxWithdraw(alice);
        assertGt(claimableAssets, 0, "has claimable assets");

        uint256 balBefore = asset.balanceOf(alice);
        vm.prank(alice);
        uint256 burnedShares = vault.withdraw(claimableAssets, alice, alice);

        assertEq(asset.balanceOf(alice) - balBefore, claimableAssets, "assets paid out");
        assertEq(burnedShares, shares, "withdrawing all assets consumes all claimable shares");
        assertEq(vault.maxWithdraw(alice), 0, "no claimable assets left");
        assertEq(vault.maxRedeem(alice), 0, "no claimable shares left");
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

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
}

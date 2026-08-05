// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

// Internal
import {TestBase} from "./TestBase.sol";
import {SupplyBorrowVault} from "../src/SupplyBorrowVault.sol";
import {ISupplyBorrowVault} from "../src/interfaces/ISupplyBorrowVault.sol";

import {IERC20} from "openzeppelin/interfaces/IERC20.sol";
import {ISpoke} from "aave-v4/spoke/interfaces/ISpoke.sol";
import {IERC4626} from "openzeppelin/interfaces/IERC4626.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";

contract SupplyBorrowVaultTest is TestBase {
    using SafeERC20 for IERC20;

    IERC20 public asset;
    IERC20 public borrowAsset;

    ISpoke public spoke;
    IERC4626 public downstreamVault;

    SupplyBorrowVault public vault;
    string public name = "SupplyBorrowVault";
    string public symbol = "SBV";

    function setUp() public override {
        super.setUp();

        vm.selectFork(forks[ETH]);

        asset = IERC20(tokens[ETH][USDT_KEY]);
        borrowAsset = IERC20(tokens[ETH][USDC_KEY]);

        spoke = ISpoke(spokeAddresses[ETH]);
        downstreamVault = IERC4626(ETH_MORPHO_VAULT);

        vault = new SupplyBorrowVault(
            tokens[ETH][USDT_KEY],
            admin,
            treasury,
            spokeAddresses[ETH],
            ETH_MORPHO_VAULT,
            USDT_RESERVE_ID,
            USDC_RESERVE_ID,
            3000,
            3000,
            name,
            symbol
        );
    }

    function test_Constructor() public view {
        assertEq(vault.asset(), tokens[ETH][USDT_KEY]);
        assertEq(vault.SPOKE_ADDRESS(), spokeAddresses[ETH]);
        assertEq(vault.name(), name);
        assertEq(vault.symbol(), symbol);
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

    function test_SetMinSupplyAmount() public {
        assertEq(vault.minSupplyAmount(), 50000000);

        vm.expectRevert();
        vault.setMinSupplyAmount(1000e6);

        vm.startPrank(admin);
        vault.setMinSupplyAmount(100e6);
        vm.stopPrank();
        assertEq(vault.minSupplyAmount(), 100e6);
    }

    function test_SetMinHealthFactor() public {
        assertEq(vault.minHealthFactor(), 1.3e18);

        vm.expectRevert();
        vault.setMinHealthFactor(11000);

        vm.startPrank(admin);
        vm.expectRevert();
        vault.setMinHealthFactor(1.2e18);

        vault.setMinHealthFactor(1.7e18);
        vm.stopPrank();
        assertEq(vault.minHealthFactor(), 1.7e18);
    }

    /*//////////////////////////////////////////////////////////////
                        COST BASIS TESTS
    //////////////////////////////////////////////////////////////*/
    function test_CostBasis_firstDeposit() public {
        // Empty vault so pps should be 1
        _depositAs(alice, 1000e6);

        assertEq(vault.costBasisPerShare(alice), 1e18);
    }

    function test_CostBasis_firstMint() public {
        _mintAs(alice, 1000e6);

        assertEq(vault.costBasisPerShare(alice), 1e18);
    }

    function test_CostBasis_secondDepositAtHigherPrice() public {
        // First deposit at 1:1.
        uint256 sharesBefore = _depositAs(alice, 1_000e6);
        assertEq(vault.costBasisPerShare(alice), 1e18, "First deposit basis should be WAD");

        // Accrue real Aave yield by advancing time.
        vm.warp(block.timestamp + 365 days);

        // Snapshot the price the vault will use
        uint256 priceAfterYield = vault.convertToAssets(1e18);
        assertGt(priceAfterYield, 1e18, "price should rise after yield");

        // Second deposit blends the higher price into the weighted-average basis.
        uint256 sharesAdded = _depositAs(alice, 1_000e6);

        // Mirror _update's integer math exactly.
        uint256 expected = (1e18 * sharesBefore + priceAfterYield * sharesAdded) / (sharesBefore + sharesAdded);

        assertEq(vault.costBasisPerShare(alice), expected, "weighted-average basis after yield");
    }

    /*//////////////////////////////////////////////////////////////
                            REDEEM TESTS
    //////////////////////////////////////////////////////////////*/
    function test_requestRedeem_auth() public {
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
}

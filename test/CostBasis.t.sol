// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

// Internal
import {TestBase} from "./utils/TestBase.sol";

import {IERC20} from "openzeppelin/interfaces/IERC20.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";

contract CostBasisTest is TestBase {
    using SafeERC20 for IERC20;

    function setUp() public override {
        super.setUp();
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
}
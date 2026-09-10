// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {TestBase} from "./utils/TestBase.sol";

contract CostBasisTest is TestBase {
    function setUp() public override {
        super.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                         COST BASIS TESTS
    //////////////////////////////////////////////////////////////*/

    // Transferring the entire share balance zeroes the sender's cost basis and
    // sets the receiver's basis to the sender's (receiver starts from zero).
    function test_CostBasis_fullTransfer_resetsSender() public {
        uint256 aliceShares = _depositAs(alice, 1000e6);
        uint256 aliceBasis = vault.costBasisPerShare(alice);
        assertGt(aliceBasis, 0, "alice has non-zero basis after deposit");

        vm.prank(alice);
        vault.transfer(bob, aliceShares);

        assertEq(vault.costBasisPerShare(alice), 0, "full transfer resets sender basis");
        assertEq(vault.costBasisPerShare(bob), aliceBasis, "receiver inherits sender basis");
    }

    // When a receiver already holds shares, incoming shares blend into a weighted average.
    // Alice deposits at the initial price; 30 days of Aave yield raise the price per share;
    // Bob deposits at the higher price; Alice then transfers half her shares to Bob.
    function test_CostBasis_partialTransfer_weightedAverage() public {
        uint256 aliceShares = _depositAs(alice, 1000e6);
        uint256 aliceBasis = vault.costBasisPerShare(alice);

        vm.warp(block.timestamp + 30 days);

        uint256 bobShares = _depositAs(bob, 1000e6);
        uint256 bobBasis = vault.costBasisPerShare(bob);

        assertGt(bobBasis, aliceBasis, "bob deposited at a higher price per share after yield");

        uint256 transferAmount = aliceShares / 2;
        uint256 expectedBobBasis = (bobBasis * bobShares + aliceBasis * transferAmount) / (bobShares + transferAmount);

        vm.prank(alice);
        vault.transfer(bob, transferAmount);

        assertEq(
            vault.costBasisPerShare(bob), expectedBobBasis, "receiver basis is weighted average of old and incoming"
        );
    }

    // Burning a holder's entire share balance must reset their cost basis to 0.
    // requestRedeem transfers alice's shares to the vault (alice's basis → 0, vault inherits it).
    // fulfillRedeemRequest then burns the vault's escrowed shares, resetting the vault's basis to 0.
    function test_CostBasis_burn_resetsWhenFullyBurned() public {
        uint256 aliceShares = _depositAs(alice, 1000e6);

        vm.prank(alice);
        vault.requestRedeem(aliceShares, alice, alice);

        // After full transfer to vault: alice's basis is gone, vault holds it
        assertEq(vault.costBasisPerShare(alice), 0, "requestRedeem clears alice's basis");
        assertGt(vault.costBasisPerShare(address(vault)), 0, "vault holds alice's cost basis");

        // Vault has no debt — fulfillRedeemRequest pulls collateral from Aave to cover the redemption
        vm.prank(admin);
        vault.fulfillRedeemRequest(alice, aliceShares);

        // Burning all escrowed shares resets the vault's basis to 0
        assertEq(vault.costBasisPerShare(address(vault)), 0, "burning all escrow shares resets vault basis");
    }

    // A partial requestRedeem (less than full balance) must NOT change the sender's cost basis,
    // since the remaining shares still represent the same original purchase.
    function test_CostBasis_escrowedSharesDontDistortBasis() public {
        uint256 aliceShares = _depositAs(alice, 1000e6);
        uint256 aliceBasis = vault.costBasisPerShare(alice);

        // Escrow half alice's shares — partial transfer to vault
        vm.prank(alice);
        vault.requestRedeem(aliceShares / 2, alice, alice);

        assertEq(vault.costBasisPerShare(alice), aliceBasis, "partial escrow leaves remaining basis unchanged");
        assertEq(vault.balanceOf(alice), aliceShares / 2, "alice retains half her shares");
    }
}

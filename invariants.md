# SupplyBorrowVault — Invariants

---

## Accounting (shadow variables)

**A1.** `_accountedIdleAssets == ASSET.balanceOf(address(this)) - _reservedAssets`
The idle tracker mirrors the vault's actual USDT balance minus what's locked for claimants. Every code path that moves USDT in or out updates this variable in the same transaction.

**A2.** `_underlyingVaultShares == UNDERLYING_VAULT.balanceOf(address(this))`
Modified only in `_depositToUnderlyingVault` (+=) and `_withdrawFromUnderlyingVault` (-=). No other paths touch Morpho shares.

**A3.** `_accountedBorrowAssets == BORROW_ASSET.balanceOf(address(this))`
Incremented by `_borrowFromAave` and `_withdrawFromUnderlyingVault`; decremented by `_depositToUnderlyingVault` and `_repayToAave`. Aave caps `repaid` at actual debt, so the decrement on repay is always ≤ the current value.

**A4.** `_reservedAssets == Σ claimableAssets[controller]` (sum across all controllers)
Backed 1:1 by actual USDT sitting in the contract wallet (follows from A1 and the fact that `_transferOut` moves real tokens).

---
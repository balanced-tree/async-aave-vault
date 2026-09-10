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

## Net Asset Value

**N1.** `totalAssets() ≥ 0`
Clamped at zero when oracle-converted debt exceeds the borrow-asset position (line 476).

**N2.** The formula is exact:
```
totalAssets = _accountedIdleAssets
            + SPOKE.getUserSuppliedAssets(RESERVE_ID, this)
            + borrowToAsset(_accountedBorrowAssets + UNDERLYING_VAULT.previewRedeem(_underlyingVaultShares))
            - borrowToAsset(SPOKE.getUserTotalDebt(BORROW_RESERVE_ID, this))
```
Debt is oracle-converted with ceiling rounding; borrow-asset holdings with floor rounding.

**N3.** `totalAssets()` slightly overstates NAV when Aave interest has accrued but the debt view is stale. At actual repayment the debt is settled at the accrued amount, so any surplus USDC from Morpho outperforming covers it. This overshoot is non-exploitable but visible in view calls.

---
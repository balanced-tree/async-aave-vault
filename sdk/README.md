# @internal/sbv-sdk

TypeScript SDK for operators and admins of the SupplyBorrowVault contract. Built on viem. Bundles the full contract ABI. Exposes three independent, tree-shakeable clients with complete type inference and a simulate-first safety guarantee on every write.

> **Internal package — not published to npm.** Add as a workspace dependency.

---

## What this is

The SupplyBorrowVault is an ERC4626 + ERC7540 vault that supplies USDT to Aave v4 as collateral, borrows USDC against it, and deploys the USDC into a downstream Morpho vault. This SDK is aimed at manager tooling — scripts and dashboards that run the leverage lifecycle — not at end-user deposit/redeem flows.

Three clients cover the full surface of the contract:

| Client | Requires | Purpose |
|--------|----------|---------|
| `ReadClient` | `PublicClient` | Every view and pure function + off-chain HF simulation |
| `ManagerClient` | `PublicClient` + `WalletClient` | All write functions, simulate-first on every call |
| `EventClient` | `PublicClient` | Typed historical log fetchers and live watchers |

Each client is independently constructable. A read-only monitor only needs `ReadClient`. A fulfillment bot only needs `ManagerClient`. They share a `PublicClient` instance — no duplicate connections.

---

## Installation

The SDK is a private ESM package with viem as a peer dependency. The peer dep means the monorepo keeps a single copy of viem shared across packages rather than duplicating it in each bundle.

```json
// consuming package's package.json
{
  "dependencies": {
    "@internal/sbv-sdk": "workspace:*",
    "viem": "^2.21.0"
  }
}
```

---

## Quick start

```ts
import { createPublicClient, createWalletClient, http } from 'viem'
import { mainnet } from 'viem/chains'
import { ReadClient, ManagerClient, EventClient } from '@internal/sbv-sdk'

const VAULT = '0xYourVaultAddress'

const publicClient = createPublicClient({ chain: mainnet, transport: http() })
const walletClient = createWalletClient({ chain: mainnet, transport: http() })

const reader  = new ReadClient({ publicClient, address: VAULT })
const manager = new ManagerClient({ publicClient, walletClient, address: VAULT })
const events  = new EventClient({ publicClient, address: VAULT })
```

---

## File structure

```
sdk/
├── package.json          # @internal/sbv-sdk, viem peer dep, ESM
├── tsconfig.json         # strict, moduleResolution: bundler, rootDir: "."
└── src/
    ├── index.ts          # barrel: ReadClient, ManagerClient, EventClient, VaultContractError
    ├── abi.ts            # full contract ABI as const (55 fns, 16 events, 19 errors)
    ├── types.ts          # StrategyExecutionData (ABI-derived), log types, WatchUnsubscribe
    ├── errors.ts         # VaultContractError class + decodeVaultError()
    ├── reader.ts         # ReadClient — 15 view methods + simulateHealthFactor
    ├── manager.ts        # ManagerClient — 9 write methods, all simulate-first
    └── events.ts         # EventClient — 4 log fetchers + 3 live watchers
test/
    ├── reader.test.ts    # 20 tests
    ├── manager.test.ts   # 12 tests
    └── events.test.ts    # 11 tests
```

Run tests: `npm test`  
Type-check: `npm run typecheck`

---

## ReadClient

Wraps every view and pure function on the vault. All return values are `bigint` — no silent coercion to `number`.

### Construction

```ts
const reader = new ReadClient({ publicClient, address: VAULT })
```

### ERC4626 views

```ts
reader.totalAssets()                        // Promise<bigint>
reader.totalSupply()                        // Promise<bigint>
reader.balanceOf(account: Address)          // Promise<bigint>
reader.convertToAssets(shares: bigint)      // Promise<bigint>
reader.convertToShares(assets: bigint)      // Promise<bigint>
reader.maxDeposit(receiver: Address)        // Promise<bigint>
reader.maxMint(receiver: Address)           // Promise<bigint>
reader.maxWithdraw(owner: Address)          // Promise<bigint>  — always 0 (async flow)
reader.maxRedeem(owner: Address)            // Promise<bigint>  — always 0 (async flow)
```

**Note on `convertToAssets`:** floor-rounds per ERC4626. Returns `0n` for dust amounts when Aave rounding makes `totalAssets < totalSupply`. `totalAssets` itself is subject to up to 2 wei of drift on each read due to Aave's share-based accounting.

### ERC7540 redeem state

This vault uses an async redemption flow. Users call `requestRedeem` to queue shares; the manager calls `fulfillRedeemRequest` to move shares from pending to claimable; users then call `redeem` to claim assets. The SDK exposes reads for each state:

```ts
reader.pendingRedeemRequest(controller: Address)    // Promise<bigint>  — shares awaiting fulfilment
reader.claimableRedeemRequest(controller: Address)  // Promise<bigint>  — shares ready to claim
reader.getRedeemRequestData(controller: Address)    // Promise<RedeemRequestData>
```

`getRedeemRequestData` is a convenience wrapper that fetches both in a single `Promise.all` and returns `{ pendingShares, claimableShares }`.

The ERC7540 spec allows multiple request IDs per controller. This vault always uses `requestId = 0`; the SDK hardcodes it so callers don't need to track a constant that never changes.

### Vault-specific views

```ts
reader.costBasisPerShare(account: Address)  // Promise<bigint>
reader.manager()                            // Promise<Address>
reader.performanceFee()                     // Promise<bigint>  — basis points (500 = 5%)
reader.targetIdleBps()                      // Promise<bigint>
reader.minSupplyAmount()                    // Promise<bigint>  — USDT, 6 decimals
reader.minHealthFactor()                    // Promise<bigint>  — 1e18 scale
```

**Cost basis:** `costBasisPerShare` stores the price-per-share at which an address last acquired shares, used for P&L tracking and performance fee calculation. A full transfer resets the sender's basis to `0`; a partial transfer leaves it unchanged. The receiver's basis becomes a weighted average of their existing basis and the incoming shares' basis.

### simulateHealthFactor

```ts
reader.simulateHealthFactor(borrowAmount: bigint)  // Promise<bigint>
```

Off-chain estimate of the health factor after borrowing an additional `borrowAmount` of `BORROW_ASSET` (USDC, 6 decimals). Useful for pre-flight checks before calling `executeStrategy`.

Executes two batched `Promise.all` calls internally:
1. Reads `SPOKE_ADDRESS`, `SPOKE_ORACLE_ADDRESS`, `BORROW_ASSET`, `BORROW_DECIMALS` from the vault.
2. Reads `getUserAccountData(vault)` from the Aave Spoke and `getAssetPrice(BORROW_ASSET)` from the oracle in parallel.

Then computes:
```
borrowAmountInBase     = borrowAmount × oraclePrice / 10^borrowDecimals
newTotalDebt           = totalDebtBase + borrowAmountInBase
collateralAdjusted     = totalCollateralBase × liquidationThreshold / 10_000
simulatedHF            = collateralAdjusted × 1e18 / newTotalDebt
```

**Approximate.** Uses the same stale Aave debt view the contract reads during `executeStrategy`. The result matches what the vault's own HF check would see, but may diverge from a freshly-settled state by up to one block of accrued interest. Returns `0n` when `newTotalDebt` is zero (undefined HF).

---

## ManagerClient

### Construction

```ts
const manager = new ManagerClient({ publicClient, walletClient, address: VAULT })
```

### Simulate-first guarantee

Every write method runs `simulateContract` before `writeContract`. If the contract would revert, a `VaultContractError` is thrown synchronously — no gas is spent, no failed transaction appears on-chain. The pattern is implemented once in a private `write()` helper; it is architecturally impossible to add a method that skips simulation.

```ts
// What happens under the hood for every write:
const { request } = await publicClient
  .simulateContract({ address, abi, functionName, args, account })
  .catch((err) => { throw decodeVaultError(err) })

return walletClient.writeContract(request)
```

All methods return the transaction hash (`Promise<Hex>`).

### Strategy operations

```ts
manager.executeStrategy(strategy: StrategyExecutionData)  // Promise<Hex>
```

Borrows USDC from Aave and deploys it into the downstream Morpho vault. The `StrategyExecutionData` struct:

```ts
type StrategyExecutionData = {
  borrowAmount:      bigint  // USDC to borrow from Aave (6 decimals)
  depositAmount:     bigint  // USDC to deposit into downstream vault
  minSharesRequired: bigint  // slippage guard — reverts with INSUFFICIENT_SHARES if not met
}
```

Common simulation reverts: `HF_TOO_LOW` (borrow would breach `minHealthFactor`), `INSUFFICIENT_LIQUIDITY` (Aave Hub lacks liquidity), `UNAUTHORIZED` (caller is not the manager).

```ts
manager.deleverage(
  downstreamShares: bigint,      // shares to redeem from Morpho vault
  repayAmount: bigint,           // USDC debt to repay on Aave
  collateralToWithdraw: bigint,  // USDT collateral to withdraw from Aave
)  // Promise<Hex>
```

Unwinds a leveraged position. Redeems downstream shares, repays USDC debt, and withdraws USDT collateral in one transaction.

### Redeem fulfilment

```ts
manager.fulfillRedeemRequest(controller: Address, shares: bigint)    // Promise<Hex>
manager.fulfillRedeemRequests(controllers: Address[], shares: bigint[])  // Promise<Hex>
```

Moves shares from a controller's pending request into claimable state. The manager calls this after ensuring the vault has enough idle USDT to cover the redemption. Arrays must be the same length for the batch variant. After fulfilment, the controller can call `redeem()` directly on the contract to claim assets.

### Admin setters

All require `DEFAULT_ADMIN_ROLE`. The manager role cannot call these.

```ts
manager.setManager(newManager: Address)              // Promise<Hex>
manager.setPerformanceFee(newFee: bigint)            // basis points, e.g. 500 = 5%
manager.setTargetIdleBps(targetIdleBps: bigint)      // fraction of totalAssets to keep idle
manager.setMinSupplyAmount(minSupplyAmount: bigint)   // USDT, 6 decimals
manager.setMinHealthFactor(minHealthFactor: bigint)   // 1e18 scale, e.g. 1.2e18 = 1.2 HF
```

`setManager(address(0))` reverts with `ZERO_ADDRESS`. Simulation catches `AccessControlUnauthorizedAccount` before any tx is sent.

---

## EventClient

### Construction

```ts
const events = new EventClient({ publicClient, address: VAULT })
```

### Historical log fetchers

Indexed argument filters are sent to the RPC node as EVM topic filters — the node does the filtering, not the SDK.

```ts
events.getStrategyExecutedLogs(fromBlock: bigint, toBlock: bigint)
  // Promise<StrategyExecutedLog[]>
  // log.args: { sharesAcquired, amountBorrowed }

events.getManagerSetLogs(fromBlock: bigint, toBlock: bigint)
  // Promise<ManagerSetLog[]>
  // log.args: { newManager }

events.getCostBasisUpdatedLogs(fromBlock: bigint, toBlock: bigint, account?: Address)
  // Promise<CostBasisUpdatedLog[]>
  // filter by indexed shareHolder topic when account is provided
  // log.args: { shareHolder, costBasisPerShare }

events.getRedeemRequestLogs(fromBlock: bigint, toBlock: bigint, controller?: Address)
  // Promise<RedeemRequestLog[]>
  // filter by indexed controller topic when controller is provided
  // log.args: { controller, owner, requestId, sender, shares }
```

### Live watchers

All watchers return a `WatchUnsubscribe` function. Call it to stop the subscription. If the transport supports WebSocket, viem uses a subscription; otherwise it polls.

```ts
const unwatch = events.watchStrategyExecuted((log) => {
  console.log('strategy executed', {
    shares: log.args.sharesAcquired,
    borrowed: log.args.amountBorrowed,
  })
})

// stop listening
unwatch()
```

Available watchers:

```ts
events.watchStrategyExecuted(onLog: (log: StrategyExecutedLog) => void): WatchUnsubscribe
events.watchManagerSet(onLog: (log: ManagerSetLog) => void): WatchUnsubscribe
events.watchCostBasisUpdated(onLog: (log: CostBasisUpdatedLog) => void, account?: Address): WatchUnsubscribe
```

---

## Error handling

`VaultContractError` is thrown by `ManagerClient` when `simulateContract` detects a revert. It carries the decoded Solidity error name and any arguments so callers can branch on the exact failure reason without parsing hex selectors.

```ts
import { VaultContractError } from '@internal/sbv-sdk'

try {
  const hash = await manager.executeStrategy({
    borrowAmount: 10_000_000n,
    depositAmount: 10_000_000n,
    minSharesRequired: 1n,
  })
} catch (err) {
  if (err instanceof VaultContractError) {
    switch (err.errorName) {
      case 'HF_TOO_LOW':
        // borrow would breach minHealthFactor — reduce borrowAmount
        // or call reader.simulateHealthFactor() to find the safe limit
        break
      case 'INSUFFICIENT_LIQUIDITY':
        // Aave Hub does not have enough USDC — try later
        break
      case 'INSUFFICIENT_SHARES':
        // downstream vault minted fewer shares than minSharesRequired
        break
      case 'UNAUTHORIZED':
        // caller is not the manager address
        break
    }
  }
}
```

`err.args` is an array of decoded error arguments (empty for most vault-specific errors; populated for OpenZeppelin errors like `AccessControlUnauthorizedAccount`).

Errors that are not simulation reverts (network errors, user rejection from a hardware wallet, etc.) are re-thrown unchanged and do not become `VaultContractError`.

### Full error reference

| Error | When it fires |
|-------|---------------|
| `HF_TOO_LOW` | Borrow would push health factor below `minHealthFactor` |
| `INSUFFICIENT_LIQUIDITY` | Aave v4 Hub lacks enough USDC to fulfil the borrow |
| `INSUFFICIENT_SHARES` | Downstream vault minted fewer shares than `minSharesRequired` |
| `UNAUTHORIZED` | Caller does not hold the required role or is not the manager |
| `ZERO_ADDRESS` | A required address argument is the zero address |
| `ZERO_AMOUNT` | A required uint argument is zero where a positive value is needed |
| `ZERO_SHARES` | A share amount resolved to zero (dust or rounding) |
| `INVALID_AMOUNT` | Amount argument is invalid for the operation |
| `INVALID_ASSET` | Asset argument does not match the vault's expected asset |
| `INVALID_FEE_AMOUNT` | Performance fee exceeds the allowed maximum |
| `INVALID_MANAGER` | New manager address fails validation |
| `INVALID_OPERATOR` | Operator address fails validation |
| `MAX_DEPOSIT_EXCEEDED` | Deposit exceeds `maxDeposit` |
| `MAX_MINT_EXCEEDED` | Mint exceeds `maxMint` |
| `NOT_IMPLEMENTED` | Called a function this vault intentionally does not support (e.g. synchronous withdraw) |
| `AccessControlUnauthorizedAccount` | OZ AccessControl — caller lacks the required role |
| `ERC20InsufficientBalance` | Token balance too low for the operation |
| `ERC20InsufficientAllowance` | Token allowance too low |
| `ReentrancyGuardReentrantCall` | Reentrant call detected |

---

## Types reference

All types are exported from the package root.

```ts
import type {
  StrategyExecutionData,
  RedeemRequestData,
  StrategyExecutedLog,
  ManagerSetLog,
  CostBasisUpdatedLog,
  RedeemRequestLog,
  DepositLog,
  WithdrawLog,
  WatchUnsubscribe,
  Address,
  Hash,
} from '@internal/sbv-sdk'
```

`StrategyExecutionData` is derived from the `executeStrategy` ABI tuple entry via `AbiParametersToPrimitiveTypes` — it is not hand-written. If the contract's `StrategyExecutionData` struct gains a new field, the TypeScript type updates automatically on the next ABI re-extract. The log types follow the same pattern via `ExtractAbiEvent`.

---

## ABI

The ABI lives in `src/abi.ts` as a single `as const` array. The `as const` assertion is what makes viem's end-to-end type inference work: without it, TypeScript treats every ABI string as the broad `string` type and loses the ability to match function names to input/output types. With `as const`, every entry becomes a literal type, and viem can infer that `functionName: 'totalAssets'` returns `bigint` — without any explicit type annotation in the calling code.

The current ABI covers 55 functions, 16 events, and 19 custom errors.

**Do not hand-edit `abi.ts`.** Re-extract from the Foundry build artifact after any contract change:

```bash
# Extract .abi field from the Foundry artifact and update abi.ts
cat out/SupplyBorrowVault.sol/SupplyBorrowVault.json | jq '.abi'
```

The `out/` artifact is the single source of truth. Editing `abi.ts` directly creates a second source of truth that will eventually drift.

---

## tsconfig notes

Two settings in `tsconfig.json` are load-bearing for viem compatibility:

- **`moduleResolution: "bundler"`** — viem ships as ESM with path aliases. The older `node` resolver cannot follow them and produces `Cannot find module` errors.
- **`target: "ES2022"`** — required for native `bigint`. Older targets polyfill `bigint` as objects, which breaks viem's type arithmetic.

`rootDir` is set to `"."` (the package root) rather than `"src"` because `include` covers both `src/**/*` and `test/**/*`. Setting `rootDir: "src"` would cause TypeScript to reject any file outside `src/` as being outside the root.

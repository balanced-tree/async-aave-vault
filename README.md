## Async Aave Vault

The Async Aave Vault is an ERC-7540 vault with synchronous deposits and asynchronous redemptions. 

It interacts with an Aave-v4 Spoke as its underlying strategy.

Funds deposited into the vault are supplied to the Aave Spoke and vault managers can then manually borrow against the supplied funds, using the borrowed funds to deposit into another underlying vault.

### Caps
The vault includes a configurable Aave supply cap to limit how much deposited liquidity may be deployed into the Aave Spoke, allowing governance to manage strategy concentration.

Borrowing is separately constrained by a borrow cap and a minimum post-borrow health factor that ensures leverage cannot exceed predefined risk limits.

### Token Support
The vault only supports non-native ERC20 tokens.

### E2E Testing Flow
The tests are executed on a fork of Ethereum and the test vault interacts with the Aave Main Spoke at address `0x94e7A5dCbE816e498b89aB752661904E2F56c485` which is a constant in `TestBase.sol`.

The supply token (and asset of the vault) is USDT (reserveId 8 of the Spoke) USDC is then borrowed against the supplied USDT used as collateral. This USDC can be deposited by the manager into the Morpho 4626 vault at address `0xdd0f28e19C1780eb6396170735D45153D261490d`.

### Missed/unfinished Items
- Wrapped native token borrowing support through Gateway.
- Swap functionality that the manager could execute to exchange borrow tokens for asset tokens directly through a DEX.
- More rigurous unit testing, fuzz testing  and invariant definitions.
- Deployment script.

## Usage

### Install Dependancies
```shell
$ forge install
```

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```
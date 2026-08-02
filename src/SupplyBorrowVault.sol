// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// OpenZeppelin
import {Math} from "openzeppelin/utils/math/Math.sol";
import {ERC20} from "openzeppelin/token/ERC20/ERC20.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {IERC4626} from "openzeppelin/interfaces/IERC4626.sol";
import {AccessControl} from "openzeppelin/access/AccessControl.sol";
import {IERC165} from "openzeppelin/utils/introspection/IERC165.sol";
import {ReentrancyGuard} from "openzeppelin/utils/ReentrancyGuard.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "openzeppelin/interfaces/IERC20Metadata.sol";

// Aave
import {WadRayMath} from "aave-v4/libraries/math/WadRayMath.sol";
import {IPriceOracle} from "aave-v4/spoke/interfaces/IPriceOracle.sol";
import {ISpoke, ReserveFlags} from "aave-v4/spoke/interfaces/ISpoke.sol";

// Centrifuge
import {IERC7540Operator, IERC7540Redeem} from "centrifuge/misc/interfaces/IERC7540.sol";

// Interfaces
import {ISupplyBorrowVault} from "./interfaces/ISupplyBorrowVault.sol";

/// @title SupplyBorrowVault
/// @author balanced-tree
/// @notice Vault that deposits into Aave v4 Spoke as strategy, borrows against supplied assets and uses the borrowed assets to deposit into another vault.
/// @dev Has synchronous deposits and asynchronous redemptions.
contract SupplyBorrowVault is AccessControl, ReentrancyGuard, ERC20, ISupplyBorrowVault {
    using WadRayMath for uint256;
    using SafeERC20 for IERC20;
    using Math for uint256;

    /*//////////////////////////////////////////////////////////////
                              CONSTANTS
    //////////////////////////////////////////////////////////////*/
    uint256 private constant WAD = 1e18;

    uint256 private constant VIRTUAL_ASSETS = 1;
    uint256 private constant VIRTUAL_SHARES = 1;

    uint256 private constant BPS_PRECISION = 10_000;
    uint256 private constant MAX_TARGET_IDLE_BPS = 4000;
    uint256 private constant MAX_PERFORMANCE_FEE = 5000;
    uint256 private constant MIN_HEALTH_FACTOR = 1.333e18;

    bytes32 private constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    /*//////////////////////////////////////////////////////////////
                                STATE
    //////////////////////////////////////////////////////////////*/
    /// @notice The manager of the vault.
    address public manager;

    /// @notice The performance fee (in basis points)
    uint256 public performanceFee;

    /// @notice The target ratio of funds to be kept idle in the vault in basis points.
    uint256 public targetIdleBps;

    /// @notice The minimum amount of idle assets to supply to Aave to avoid dust size supply() calls.
    uint256 private _minSupplyAmount;

    /// @notice The amount of internally accounted available assets.
    uint256 private _accountedIdleAssets;

    /// @notice The amount of internally accounted borrowed assets.
    uint256 private _accountedBorrowAssets;

    /// @notice The amount of internally accounted underlying vault shares.
    uint256 private _underlyingVaultShares;

    /// @notice The amount of assets reserved for withdrawals of fulfilled (cliamable redeem requests).
    uint256 private _reservedAssets;

    /// @notice WAD-scaled weighted average cost basis per share for each account.
    mapping(address shareHolder => uint256 costBasis) public costBasisPerShare;

    /// @notice Redeem requests for each controller.
    mapping(address controller => RedeemRequestData redeemRequest) private _redeemRequests;

    /// @notice Operators for each controller.
    mapping(address controller => mapping(address operator => bool isOperator)) private _operators;

    /*/////////////////// IMMUTABLE STATE ////////////////////////*/
    /// @notice Underlying asset.
    IERC20 public immutable ASSET;

    /// @notice Decimals of the underlying asset (and the share token)
    uint8 public immutable DECIMALS;

    /// @notice Interface to the Aave Spoke contract.
    ISpoke public immutable SPOKE;
    /// @notice Address of the Aave Spoke contract.
    address public immutable SPOKE_ADDRESS;
    /// @notice Address of the Aave Spoke Oracle contract.
    address public immutable SPOKE_ORACLE_ADDRESS;

    /// @notice Identifier of the Aave Reserve to supply.
    uint256 public immutable RESERVE_ID;

    /// @notice Borrow asset.
    IERC20 public immutable BORROW_ASSET;

    /// @notice Decimals of the borrow asset.
    uint8 public immutable BORROW_DECIMALS;

    /// @notice Identifier of the Aave Reserve to borrow.
    uint256 public immutable BORROW_RESERVE_ID;

    /// @notice Instance of the underlying vault.
    IERC4626 public immutable UNDERLYING_VAULT;

    /// @notice Address to which fee funds will be transferred.
    address private immutable TREASURY;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    /// @notice Contract initialization.
    /// @param asset_ The underlying asset address.
    /// @param admin_ The address of the initial admin.
    /// @param treasury_ The address to which fee funds will be transferred.
    /// @param spokeAddress_ Address of the Aave Spoke contract.
    /// @param downstreamVault_ The address of the downstream vault.
    /// @param aaveReserveId_ The identifier of the Aave Reserve to supply.
    /// @param borrowReserveId_ The identifier of the Aave Reserve to borrow.
    /// @param targetIdleBps_ The target ratio of funds to be kept available in the vault for small withdrawals in basis points.
    /// @param performanceFee_ The initial performance fee (in basis points)
    /// @param name_ The name of the vault.
    /// @param symbol_ The symbol of the share token.
    constructor(
        address asset_,
        address admin_,
        address treasury_,
        address spokeAddress_,
        address downstreamVault_,
        uint256 aaveReserveId_,
        uint256 borrowReserveId_,
        uint256 targetIdleBps_,
        uint256 performanceFee_,
        string memory name_,
        string memory symbol_
    ) ERC20(name_, symbol_) {
        // Validate admin
        if (admin_ == address(0)) revert ZERO_ADDRESS();

        // Validate and set treasury
        if (treasury_ == address(0)) revert ZERO_ADDRESS();
        TREASURY = treasury_;

        // Validate asset
        if (asset_ == address(0)) revert INVALID_ASSET();
        if (asset_.code.length == 0) revert INVALID_ASSET();

        // Set asset and precision
        (bool success, uint8 assetDecimals) = _getAssetDecimals(asset_);
        DECIMALS = success ? assetDecimals : 18;
        ASSET = IERC20(asset_);

        // Set roles
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(MANAGER_ROLE, admin_);
        manager = admin_;

        // Validate and set Spoke details
        if (spokeAddress_ == address(0)) revert ZERO_ADDRESS();
        SPOKE_ADDRESS = spokeAddress_;
        SPOKE = ISpoke(spokeAddress_);
        SPOKE_ORACLE_ADDRESS = SPOKE.ORACLE();

        // Validate and set Reserve details
        if (aaveReserveId_ == borrowReserveId_) revert INVALID_ASSET();

        ISpoke.Reserve memory reserve = SPOKE.getReserve(aaveReserveId_);
        if (reserve.underlying != address(ASSET)) revert INVALID_ASSET();
        // Reserve asset decimals equal underlying asset decimals
        RESERVE_ID = aaveReserveId_;

        BORROW_RESERVE_ID = borrowReserveId_;
        ISpoke.Reserve memory borrowReserve = SPOKE.getReserve(borrowReserveId_);
        BORROW_DECIMALS = borrowReserve.decimals;

        // Set target idle BPS
        if (targetIdleBps_ > MAX_TARGET_IDLE_BPS || targetIdleBps_ == 0) revert INVALID_AMOUNT();
        targetIdleBps = targetIdleBps_;

        // Set performance fee
        if (performanceFee_ > MAX_PERFORMANCE_FEE) revert INVALID_FEE_AMOUNT();
        performanceFee = performanceFee_;

        // Set underlying vault
        if (downstreamVault_ == address(0)) revert ZERO_ADDRESS();
        if (IERC4626(downstreamVault_).asset() != borrowReserve.underlying) revert INVALID_ASSET();
        UNDERLYING_VAULT = IERC4626(downstreamVault_);
        BORROW_ASSET = IERC20(borrowReserve.underlying);
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @inheritdoc ISupplyBorrowVault
    function setManager(address newManager) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newManager == address(0)) revert ZERO_ADDRESS();
        if (hasRole(MANAGER_ROLE, newManager)) revert INVALID_MANAGER();

        _revokeRole(MANAGER_ROLE, manager);

        manager = newManager;
        _grantRole(MANAGER_ROLE, newManager);
        emit ManagerSet(newManager);
    }

    /// @inheritdoc ISupplyBorrowVault
    function setPerformanceFee(uint256 newFee) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newFee > MAX_PERFORMANCE_FEE) revert INVALID_FEE_AMOUNT();
        performanceFee = newFee;

        emit PerformanceFeeSet(newFee);
    }

    /// @inheritdoc ISupplyBorrowVault
    function setTargetIdleBps(uint256 targetIdleBps_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (targetIdleBps_ > MAX_TARGET_IDLE_BPS) revert INVALID_AMOUNT();
        targetIdleBps = targetIdleBps_;

        emit TargetIdleBpsSet(targetIdleBps_);
    }

    /// @inheritdoc ISupplyBorrowVault
    /// @dev The vault manager can set the minimum supply amount so that it can be updated dynamically.
    function setMinSupplyAmount(uint256 minSupplyAmount_) external onlyRole(MANAGER_ROLE) {
        if (minSupplyAmount_ == 0) revert ZERO_AMOUNT();
        _minSupplyAmount = minSupplyAmount_;

        emit MinSupplyAmountSet(minSupplyAmount_);
    }

    /// @inheritdoc ISupplyBorrowVault
    function setMinHealthFactor(uint256 minHealthFactor) external onlyRole(MANAGER_ROLE) {
        if (minHealthFactor < MIN_HEALTH_FACTOR) revert INVALID_AMOUNT();
        minHealthFactor = minHealthFactor;

        emit MinHealthFactorSet(minHealthFactor);
    }

    /// @inheritdoc ISupplyBorrowVault
    function executeStrategy(StrategyExecutionData memory strategy)
        external
        onlyRole(MANAGER_ROLE)
        returns (uint256 sharesAcquired)
    {
        if (strategy.depositAmount == 0 || strategy.minSharesRequired == 0) revert ZERO_AMOUNT();

        if (strategy.borrowAmount > 0) {
            _borrowFromAave(strategy.borrowAmount);
        }

        sharesAcquired = _depositToUnderlyingVault(strategy.depositAmount);
        if (sharesAcquired < strategy.minSharesRequired) revert INSUFFICIENT_SHARES();

        emit StrategyExecuted(sharesAcquired, strategy.borrowAmount);
    }

    /// @inheritdoc ISupplyBorrowVault
    function deleverage(uint256 downstreamShares, uint256 repayAmount, uint256 collateralToWithdraw)
        external
        onlyRole(MANAGER_ROLE)
    {
        if (downstreamShares > 0) _withdrawFromUnderlyingVault(downstreamShares);
        if (repayAmount > 0) _repayToAave(repayAmount);
        if (collateralToWithdraw > 0) {
            uint256 withdrawn = _withdrawFromAave(collateralToWithdraw);
            _accountedIdleAssets += withdrawn;
        }

        // Never leave the remaining position below the HF floor
        if (SPOKE.getUserTotalDebt(BORROW_RESERVE_ID, address(this)) != 0) {
            if (_computeHealthFactor(0) < MIN_HEALTH_FACTOR) revert HF_TOO_LOW();
        }
    }

    /*//////////////////////////////////////////////////////////////
                          EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @inheritdoc IERC4626
    function deposit(uint256 assets, address receiver) external override nonReentrant returns (uint256 shares) {
        if (receiver == address(0)) revert ZERO_ADDRESS();
        if (assets == 0) revert ZERO_AMOUNT();

        // Check deposits are enabled
        uint256 maxAssetAmount = maxDeposit(receiver);
        if (assets > maxAssetAmount) revert MAX_DEPOSIT_EXCEEDED();

        // Calculate shares
        shares = previewDeposit(assets);
        if (shares == 0) revert ZERO_SHARES();

        // Deposit assets into the vault
        _deposit(assets, receiver, shares);
    }

    /// @inheritdoc IERC4626
    function mint(uint256 shares, address receiver) external override nonReentrant returns (uint256 assets) {
        if (receiver == address(0)) revert ZERO_ADDRESS();
        if (shares == 0) revert ZERO_AMOUNT();

        // Check mints are enabled
        uint256 maxShareAmount = maxMint(receiver);
        if (shares > maxShareAmount) revert MAX_MINT_EXCEEDED();

        assets = _convertToAssets(shares, Math.Rounding.Ceil);

        // Deposit assets into the vault
        _deposit(assets, receiver, shares);
    }

    /// @inheritdoc IERC7540Redeem
    function requestRedeem(uint256 shares, address controller, address owner)
        external
        override
        nonReentrant
        returns (uint256 requestId)
    {
        if (shares == 0) revert ZERO_SHARES();
        if (controller == address(0) || owner == address(0)) revert ZERO_ADDRESS();

        if (msg.sender != owner && !_operators[owner][msg.sender]) revert UNAUTHORIZED();

        // Escrow the shares into the vault. The shares stay in totalSupply while pending, so pps keeps floating until fulfillment locks it.
        _transfer(owner, address(this), shares);

        _redeemRequests[controller].pendingShares += shares;

        emit RedeemRequest(controller, owner, 0, msg.sender, shares);

        return 0;
    }

    /// @inheritdoc IERC4626
    function withdraw(uint256 assets, address receiver, address controller)
        external
        override
        nonReentrant
        returns (uint256 shares)
    {
        if (assets == 0) revert ZERO_AMOUNT();
        if (receiver == address(0)) revert ZERO_ADDRESS();

        if (msg.sender != controller && !_operators[controller][msg.sender]) revert UNAUTHORIZED();

        RedeemRequestData storage request = _redeemRequests[controller];
        uint256 claimableAssets = request.claimableAssets;
        if (assets > claimableAssets) revert INVALID_AMOUNT();

        shares = Math.mulDiv(assets, request.claimableShares, claimableAssets, Math.Rounding.Ceil);

        request.claimableAssets = claimableAssets - assets;
        request.claimableShares -= shares;
        _reservedAssets -= assets;

        _transferOut(receiver, assets);

        emit Withdraw(msg.sender, receiver, controller, assets, shares);
    }

    /// @inheritdoc IERC4626
    function redeem(uint256 shares, address receiver, address controller)
        external
        override
        nonReentrant
        returns (uint256 assets)
    {
        if (shares == 0) revert ZERO_AMOUNT();
        if (receiver == address(0)) revert ZERO_ADDRESS();
    }

    /// @inheritdoc IERC7540Operator
    function setOperator(address operator, bool approved) external returns (bool) {
        if (operator == address(0)) revert ZERO_ADDRESS();
        if (msg.sender == operator) revert INVALID_OPERATOR();

        _operators[msg.sender][operator] = approved;
        emit OperatorSet(msg.sender, operator, approved);
        return true;
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @inheritdoc IERC20Metadata
    function decimals() public view override(IERC20Metadata, ERC20) returns (uint8) {
        return DECIMALS;
    }

    /// @inheritdoc IERC4626
    function asset() public view override returns (address) {
        return address(ASSET);
    }

    /// @inheritdoc IERC4626
    /// @dev totalAssets = idleAsets + assets supplied to Aave + valueOfBorrowedFundsHeld (in asset units) - debtVault (in asset units)
    function totalAssets() public view override returns (uint256 assets) {
        assets = _accountedIdleAssets + SPOKE.getUserSuppliedAssets(RESERVE_ID, address(this));

        uint256 borrowAssets = _accountedBorrowAssets;

        uint256 debt = SPOKE.getUserTotalDebt(BORROW_RESERVE_ID, address(this));

        // If there's no borrow, we don't need to read the oracle for the borrow asset value conversion.
        if (borrowAssets != 0 || debt != 0) {
            uint256 borrowPrice = IPriceOracle(SPOKE_ORACLE_ADDRESS).getReservePrice(BORROW_RESERVE_ID);
            uint256 assetPrice = IPriceOracle(SPOKE_ORACLE_ADDRESS).getReservePrice(RESERVE_ID);

            assets += _borrowToAsset(borrowAssets, borrowPrice, assetPrice, Math.Rounding.Floor);
            uint256 debtValue = _borrowToAsset(debt, borrowPrice, assetPrice, Math.Rounding.Ceil);

            assets = assets > debtValue ? assets - debtValue : 0;
        }
    }

    /// @inheritdoc IERC4626
    function convertToShares(uint256 assets) public view override returns (uint256) {
        return _convertToShares(assets, Math.Rounding.Floor);
    }

    /// @inheritdoc IERC4626
    function convertToAssets(uint256 shares) public view override returns (uint256) {
        return _convertToAssets(shares, Math.Rounding.Floor);
    }

    /// @inheritdoc IERC4626
    function maxDeposit(address) public view override returns (uint256) {
        return _supplyEnabled() ? type(uint256).max : 0;
    }

    /// @inheritdoc IERC4626
    function maxMint(address) public view override returns (uint256) {
        return _supplyEnabled() ? type(uint256).max : 0;
    }

    /// @inheritdoc IERC4626
    function maxWithdraw(address owner) public view override returns (uint256) {
        return _redeemRequests[owner].claimableAssets;
    }

    /// @inheritdoc IERC4626
    function maxRedeem(address owner) public view override returns (uint256) {
        return _redeemRequests[owner].claimableShares;
    }

    /// @inheritdoc IERC4626
    function previewDeposit(uint256 assets) public view override returns (uint256) {
        return _convertToShares(assets, Math.Rounding.Floor);
    }

    /// @inheritdoc IERC4626
    function previewMint(uint256 shares) public view override returns (uint256) {
        return _convertToAssets(shares, Math.Rounding.Ceil);
    }

    /// @inheritdoc IERC4626
    function previewWithdraw(
        uint256 /* assets*/
    )
        public
        pure
        returns (uint256)
    {
        revert NOT_IMPLEMENTED();
    }

    /// @inheritdoc IERC4626
    function previewRedeem(
        uint256 /*shares*/
    )
        public
        pure
        override
        returns (uint256)
    {
        revert NOT_IMPLEMENTED();
    }

    /// @inheritdoc IERC7540Operator
    function isOperator(address controller, address operator) public view returns (bool status) {
        return _operators[controller][operator];
    }

    /// @inheritdoc IERC7540Redeem
    function pendingRedeemRequest(
        uint256,
        /*requestId*/
        address controller
    )
        external
        view
        returns (uint256 pendingShares)
    {
        return _redeemRequests[controller].pendingShares;
    }

    /// @inheritdoc IERC7540Redeem
    function claimableRedeemRequest(
        uint256, /*requestId*/
        address controller
    )
        external
        view
        returns (uint256 claimableShares)
    {
        return maxRedeem(controller);
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public pure override returns (bool supported) {
        supported = (interfaceId == type(IERC4626).interfaceId) || (interfaceId == type(IERC165).interfaceId)
            || (interfaceId == type(IERC7540Redeem).interfaceId) || (interfaceId == type(IERC7540Operator).interfaceId);
    }

    /*//////////////////////////////////////////////////////////////
                        ERC20 INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Override of ERC20._update to snapshot weighted-average cost basis per share.
     * @dev Called on every mint, burn, and transfer. Reads balanceOf before calling super, so all balance reads reflect pre-update state.
     * @param from The sender (address(0) on mint).
     * @param to The receiver (address(0) on burn).
     * @param value The amount of shares being moved.
     */
    function _update(address from, address to, uint256 value) internal override {
        if (from == address(0)) {
            // Mint flow
            uint256 oldBalance = balanceOf(to);
            // Current price per share in WAD: assets per 1e18 shares
            uint256 currentPrice = _convertToAssets(WadRayMath.WAD, Math.Rounding.Floor);

            if (oldBalance == 0) {
                costBasisPerShare[to] = currentPrice;
            } else {
                uint256 oldBasis = costBasisPerShare[to];
                costBasisPerShare[to] = (oldBasis * oldBalance + currentPrice * value) / (oldBalance + value);
            }

            emit CostBasisUpdated(to, costBasisPerShare[to]);
        } else if (to == address(0)) {
            // Burn flow
            if (balanceOf(from) == value) {
                costBasisPerShare[from] = 0;
                emit CostBasisUpdated(from, 0);
            }
        } else {
            // Transfer flow
            uint256 senderBasis = costBasisPerShare[from];
            uint256 receiverBalance = balanceOf(to);

            // Update receiver's cost basis
            if (receiverBalance == 0) {
                costBasisPerShare[to] = senderBasis;
            } else {
                uint256 receiverBasis = costBasisPerShare[to];
                costBasisPerShare[to] =
                    (receiverBasis * receiverBalance + senderBasis * value) / (receiverBalance + value);
            }

            emit CostBasisUpdated(to, costBasisPerShare[to]);

            // Reset sender cost basis if their balance is reduced to 0
            if (balanceOf(from) == value) {
                costBasisPerShare[from] = 0;
                emit CostBasisUpdated(from, 0);
            }
        }

        super._update(from, to, value);
    }

    /**
     * @notice Performs a transfer in of underlying assets.
     * @param from Address from which to transfer the assets.
     * @param assets Amount of assets to transfer.
     */
    function _transferIn(address from, uint256 assets) internal {
        SafeERC20.safeTransferFrom(IERC20(asset()), from, address(this), assets);
    }

    /**
     * @notice Performs a transfer out of underlying assets.
     * @param to Address to which the assets will be transferred.
     * @param assets Amount of assets to transfer.
     */
    function _transferOut(address to, uint256 assets) internal {
        SafeERC20.safeTransfer(IERC20(asset()), to, assets);
    }

    /**
     * @notice Gets the decimals of an asset
     * @dev A return value of false indicates that the attempt failed in some way.
     * @param assetAddress The address of the token to query.
     * @return ok Boolean indicating if the operation was successful.
     * @return assetDecimals The token's decimals if successful, 0 otherwise.
     */
    function _getAssetDecimals(address assetAddress) internal view returns (bool ok, uint8 assetDecimals) {
        (bool success, bytes memory encodedDecimals) =
            address(assetAddress).staticcall(abi.encodeCall(IERC20Metadata.decimals, ()));
        if (success && encodedDecimals.length >= 32) {
            uint256 returnedDecimals = abi.decode(encodedDecimals, (uint256));
            if (returnedDecimals < type(uint8).max) {
                // casting to 'uint8' is safe because the returned decimals is a valid uint8
                // forge-lint: disable-next-line(unsafe-typecast)
                return (true, uint8(returnedDecimals));
            }
        }
        return (false, 0);
    }

    /*//////////////////////////////////////////////////////////////
                       ERC4626 INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Returns the amount of shares that the Vault would exchange for the amount of assets provided, in an ideal
     * scenario where all the conditions are met.
     * @param assets The amount of assets to be converted.
     * @param rounding The direction in which to round division.
     * @return shares The equivalent amount of shares.
     */
    function _convertToShares(uint256 assets, Math.Rounding rounding) internal view returns (uint256 shares) {
        shares = Math.mulDiv(assets, totalSupply() + VIRTUAL_SHARES, totalAssets() + VIRTUAL_ASSETS, rounding);
    }

    /**
     * @notice Returns the amount of assets that the Vault would exchange for the amount of shares provided, in an ideal
     * scenario where all the conditions are met.
     * @param shares The amount of shares to be converted.
     * @param rounding The directio in which to round division.
     * @return assets The equivalent amount of assets.
     */
    function _convertToAssets(uint256 shares, Math.Rounding rounding) internal view returns (uint256 assets) {
        assets = Math.mulDiv(shares, totalAssets() + VIRTUAL_ASSETS, totalSupply() + VIRTUAL_SHARES, rounding);
    }

    /**
     * @notice Deposits assets into the vault.
     * @param assets Amount of assets to deposit.
     * @param receiver Address to which the shares will be minted.
     * @param shares Amount of shares to mint.
     */
    function _deposit(uint256 assets, address receiver, uint256 shares) internal {
        // Pull assets and account only the actual received delta
        uint256 idleBefore = ASSET.balanceOf(address(this));
        _transferIn(msg.sender, assets);
        uint256 assetsReceived = ASSET.balanceOf(address(this)) - idleBefore;

        /// @dev _update() snapshots the depositor's cost basis. The cost basis must be the price-per-share before this deposit is reflected in the vault's accounting.
        _mint(receiver, shares);

        // Reflect the new assets in vault accounting.
        _accountedIdleAssets += assetsReceived;

        // Supply any idle above the target buffer to Aave.
        _rebalanceIdleAssetsToAave();

        // Emit event
        emit Deposit(msg.sender, receiver, assets, shares);
    }

    /**
     * @notice Performs a rebalance operation to ensure there are enough idle assets available for withdrawals.
     * @param assetsNeeded the amount of idle assets required for withdrawal.
     */
    function _ensureIdleAssets(uint256 assetsNeeded) internal {
        uint256 idle = _accountedIdleAssets;

        if (idle >= assetsNeeded) {
            return;
        }

        // While leveraged, never pull collateral from Aave to fund redemptions
        // collateral against open debt lowers HF. The manager must keep the idle buffer topped up via deleverage() (which repays debt before freeing collateral).
        if (SPOKE.getUserTotalDebt(BORROW_RESERVE_ID, address(this)) != 0) revert INSUFFICIENT_LIQUIDITY();

        uint256 shortfall = assetsNeeded - idle;

        uint256 withdrawn = _withdrawFromAave(shortfall);

        // Depending on Aave liquidity, withdrawn may be less than requested.
        if (withdrawn < shortfall) revert INSUFFICIENT_LIQUIDITY();

        _accountedIdleAssets += withdrawn;
    }

    /*//////////////////////////////////////////////////////////////
                       AAVE V4 INTERNAL HELPERS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Whether the Aave reserve currently accepts supplies (not paused or frozen).
     * @dev A deposit rebalances excess idle into Aave, so deposits revert while supply is disabled.
     * @return enabled True if the reserve accepts supplies.
     */
    function _supplyEnabled() internal view returns (bool enabled) {
        // ReserveFlagsMap bits: 0x01 = paused, 0x02 = frozen. Supply requires neither set.
        uint8 flags = ReserveFlags.unwrap(SPOKE.getReserve(RESERVE_ID).flags);
        return (flags & 0x03) == 0;
    }

    /**
     * @notice Performs a supply operation to the Aave Spoke.
     * @param amountToSupply The amount to supply.
     */
    function _supplyToAave(uint256 amountToSupply) internal {
        ASSET.safeIncreaseAllowance(SPOKE_ADDRESS, amountToSupply);
        SPOKE.supply(RESERVE_ID, amountToSupply, address(this));
    }

    /**
     * @notice Performs a rebalance operation to supply excess idle assets above the target amount into Aave.
     */
    function _rebalanceIdleAssetsToAave() internal {
        uint256 total = totalAssets();

        uint256 targetIdle = Math.mulDiv(total, targetIdleBps, BPS_PRECISION, Math.Rounding.Floor);

        uint256 idle = _accountedIdleAssets;

        if (idle <= targetIdle) {
            return;
        }

        uint256 excessIdle = idle - targetIdle;

        if (excessIdle < _minSupplyAmount) {
            return;
        }

        _accountedIdleAssets -= excessIdle;
        _supplyToAave(excessIdle);
    }

    /**
     * @notice Performs a withdrawal operation from the Aave Spoke.
     * @param amountToWithdraw The amount to withddraw.
     * @return amountReceived The amount of assets received from withdrawal.
     */
    function _withdrawFromAave(uint256 amountToWithdraw) internal returns (uint256 amountReceived) {
        (, amountReceived) =
            SPOKE.withdraw({reserveId: RESERVE_ID, amount: amountToWithdraw, onBehalfOf: address(this)});
    }

    /**
     * @notice Computes the health factor after a borrow operation.
     * @param borrowAmount The amount to borrow.
     * @return hf The health factor.
     */
    function _computeHealthFactor(uint256 borrowAmount) internal view returns (uint256 hf) {
        // Current account data
        ISpoke.UserAccountData memory currentData = SPOKE.getUserAccountData(address(this));

        // Value the new borrow in Aave units: amount * price * 10^(18 - decimals)
        /// @dev The borrow asset is priced via its own reserve.
        uint256 borrowPrice = IPriceOracle(SPOKE_ORACLE_ADDRESS).getReservePrice(BORROW_RESERVE_ID);
        uint256 borrowValue = borrowAmount * borrowPrice * (10 ** (WadRayMath.WAD_DECIMALS - BORROW_DECIMALS));

        uint256 newTotalDebtValue = currentData.totalDebtValueRay.fromRayUp() + borrowValue;
        if (newTotalDebtValue == 0) return type(uint256).max;

        // WAD-scaled HF: avgCollateralFactor is returned normalized to WAD
        hf = Math.mulDiv(
            currentData.totalCollateralValue, currentData.avgCollateralFactor, newTotalDebtValue, Math.Rounding.Floor
        );
    }

    /**
     * @notice Performs a borrow operation from the Aave Spoke.
     * @param amountToBorrow The amount to borrow.
     * @return borrowedAssets The amount of assets borrowed.
     */
    function _borrowFromAave(uint256 amountToBorrow) internal returns (uint256 borrowedAssets) {
        // Ensure the supplied reserve counts as collateral
        SPOKE.setUsingAsCollateral(RESERVE_ID, true, address(this));

        uint256 hf = _computeHealthFactor(amountToBorrow);

        if (hf < MIN_HEALTH_FACTOR) revert HF_TOO_LOW();

        (, borrowedAssets) = SPOKE.borrow(BORROW_RESERVE_ID, amountToBorrow, address(this));

        // Track the borrowed funds
        _accountedBorrowAssets += borrowedAssets;

        // TODO: Handle borrowing wrapped native assets
    }

    /**
     * @notice Repays Aave debt using held borrow asset funds.
     * @param amount The amount of debt to repay (capped at outstanding debt by Aave).
     * @return repaid The actual amount of borrow asset repaid.
     */
    function _repayToAave(uint256 amount) internal returns (uint256 repaid) {
        BORROW_ASSET.safeIncreaseAllowance(SPOKE_ADDRESS, amount);
        (, repaid) = SPOKE.repay(BORROW_RESERVE_ID, amount, address(this));
        _accountedBorrowAssets -= repaid;
    }

    /*//////////////////////////////////////////////////////////////
                        CONVERSION HELPERS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Converts a borrow asset amount to its equivalent value in asset token units.
     * @dev Derived from Aave (amount * price * 10^(18 - decimals))
     * @param borrowAmount Amount in borrow token units.
     * @param borrowPrice Oracle price of the borrow reserve.
     * @param assetPrice Oracle price of the asset (collateral) reserve.
     * @param rounding Rounding direction (Floor for assets held, Ceil for debt).
     */
    function _borrowToAsset(uint256 borrowAmount, uint256 borrowPrice, uint256 assetPrice, Math.Rounding rounding)
        internal
        view
        returns (uint256)
    {
        return Math.mulDiv(borrowAmount * borrowPrice, 10 ** DECIMALS, assetPrice * (10 ** BORROW_DECIMALS), rounding);
    }

    /*//////////////////////////////////////////////////////////////
                        UNDERLYING VAULT FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Deploys held borrow asset funds into the underlying vault.
     * @param amount The amount of borrow asset to deposit into the underlying vault.
     * @return sharesReceived The underlying vault shares minted to this vault.
     */
    function _depositToUnderlyingVault(uint256 amount) internal returns (uint256 sharesReceived) {
        _accountedBorrowAssets -= amount;

        BORROW_ASSET.safeIncreaseAllowance(address(UNDERLYING_VAULT), amount);
        sharesReceived = UNDERLYING_VAULT.deposit(amount, address(this));

        _underlyingVaultShares += sharesReceived;
    }

    /**
     * @notice Redeems underlying vault shares back into held BORROW funds.
     * @dev Reverse of _depositToUnderlyingVault() used by the deleverage path to source repay funds.
     * @param shares The underlying vault shares to redeem.
     * @return assetsReceived The BORROW asset received.
     */
    function _withdrawFromUnderlyingVault(uint256 shares) internal returns (uint256 assetsReceived) {
        _underlyingVaultShares -= shares;
        assetsReceived = UNDERLYING_VAULT.redeem(shares, address(this), address(this));
        _accountedBorrowAssets += assetsReceived;
    }
}

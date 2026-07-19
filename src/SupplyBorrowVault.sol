// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Interfaces
import {ISupplyBorrowVault} from "./interfaces/ISupplyBorrowVault.sol";

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

/// @title SupplyBorrowVault
/// @author balanced-tree
/// @notice Vault that deposits into Aave v4 Spoke as strategy, borrows against supplied assets and uses the borrowed assets to deposit into another vault.
/// @dev Has synchronous deposits and asynchronous redemptions.
contract SupplyBorrowVault is ERC20, AccessControl, ReentrancyGuard,  ISupplyBorrowVault {
    using SafeERC20 for IERC20;
    using Math for uint256;

    /*//////////////////////////////////////////////////////////////
                              CONSTANTS
    //////////////////////////////////////////////////////////////*/
    uint256 private constant VIRTUAL_ASSETS = 1;
    uint256 private constant VIRTUAL_SHARES = 1;
    uint256 private constant BPS_PRECISION = 10_000;
    bytes32 private constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    /*//////////////////////////////////////////////////////////////
                                STATE
    //////////////////////////////////////////////////////////////*/

    address public manager;

    // Immutable state
    IERC20 public immutable ASSET;
    uint8 public immutable UNDERLYING_DECIMALS;

    address private immutable TREASURY;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    /// @notice Contract initialization.
    /// @param asset_ The underlying asset address.
    /// @param admin_ The address of the initial admin.
    /// @param treasury_ The address to which fee funds will be transferred.
    /// @param name_ The name of the vault.
    /// @param symbol_ The symbol of the share token.
    constructor(address asset_, address admin_, address treasury_, string memory name_, string memory symbol_)
        ERC20(name_, symbol_)
    {
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
        UNDERLYING_DECIMALS = success ? assetDecimals : 18;
        ASSET = IERC20(asset_);

        // Set roles
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(MANAGER_ROLE, admin_);
        manager = admin_;
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
        emit managerSet(newManager);
    }

    /*//////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @inheritdoc IERC4626
    function deposit(uint256 assets, address receiver) external override nonReentrant returns (uint256 shares) {
        revert NOT_IMPLEMENTED();
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @inheritdoc IERC20Metadata
    function decimals() public view override(IERC20Metadata, ERC20) returns (uint8) {
        return UNDERLYING_DECIMALS;
    }

    /// @inheritdoc IERC4626
    function asset() public view override returns (address) {
        return address(ASSET);
    }
    
    /// @inheritdoc IERC4626
    function totalAssets() public view override returns (uint256) {
        revert();
    }

    /// @inheritdoc IERC4626
    function convertToShares(uint256 assets) public view override returns (uint256) {
        return _convertToShares(assets, Math.Rounding.Floor);
    }

    /// @inheritdoc IERC4626
    function convertToAssets(uint256 shares) public view override returns (uint256) {
        return _convertToAssets(shares, Math.Rounding.Floor);
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Returns the amount of shares that the Vault would exchange for the amount of assets provided, in an ideal
     * scenario where all the conditions are met.
     * @param assets The amount of assets to be converted.
     * @param rounding The direction in which to round division.
     * @return The equivalent amount of shares.
     */
    function _convertToShares(uint256 assets, Math.Rounding rounding) internal view returns (uint256) {
      revert();
    }

    /**
     * @notice Returns the amount of assets that the Vault would exchange for the amount of shares provided, in an ideal
     * scenario where all the conditions are met.
     * @param shares The amount of shares to be converted.
     * @param rounding The directio in which to round division.
     * @return The equivalent amount of assets.
     */
    function _convertToAssets(uint256 shares, Math.Rounding rounding) internal view returns (uint256) {
      revert();
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
     * @dev A return value of false indicates that the attempt failed in some way..
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
}

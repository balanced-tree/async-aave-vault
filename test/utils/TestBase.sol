// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

// Internal
import {TestConfigSetup} from "./TestConfigSetup.sol";
import {SupplyBorrowVault} from "../../src/SupplyBorrowVault.sol";

import {IERC20} from "openzeppelin/interfaces/IERC20.sol";
import {ISpoke} from "aave-v4/spoke/interfaces/ISpoke.sol";
import {IERC4626} from "openzeppelin/interfaces/IERC4626.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";

abstract contract TestBase is TestConfigSetup {
    using SafeERC20 for IERC20;
    
    IERC20 public asset;
    IERC20 public borrowAsset;

    ISpoke public spoke;
    IERC4626 public downstreamVault;

    SupplyBorrowVault public vault;
    string public name = "SupplyBorrowVault";
    string public symbol = "SBV";

    function setUp() public virtual override {
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
}

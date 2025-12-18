import assert from "node:assert";
import { test } from "node:test";
import hre from "hardhat";

test("NFTAuction UUPS upgrade flow", async () => {
    const { viem } = await hre.network.connect();
    const [deployer] = await viem.getWalletClients();

    // Deploy implementation v1
    const implV1 = await viem.deployContract("NFTAuction", undefined, { client: { wallet: deployer } });

    // Deploy ERC1967 proxy pointing to implV1 (no init calldata)
    const proxy = await viem.deployContract(
        "MyERC1967Proxy",
        [implV1.address, "0x"],
        { client: { wallet: deployer } }
    );

    console.log("Before upgrade - proxy:", proxy.address);
    console.log("Before upgrade - implementation:", implV1.address);

    // Interact with proxy using NFTAuction ABI
    const nftAuctionProxy = await viem.getContractAt("NFTAuction", proxy.address);

    // Call initialize via proxy to set owner
    // await nftAuctionProxy.write.initialize({ account: deployer.account });
    await nftAuctionProxy.write.initialize({ account: deployer.account });
    const owner = (await nftAuctionProxy.read.owner()) as `0x${string}`;
    assert.strictEqual(owner.toLowerCase(), deployer.account.address.toLowerCase());

    // Deploy implementation v2
    const implV2 = await viem.deployContract("NFTAuctionV2", undefined, { client: { wallet: deployer } });

    // Upgrade proxy to implV2 using UUPS upgrade function (use upgradeToAndCall)
    await nftAuctionProxy.write.upgradeToAndCall([implV2.address, "0x"], { account: deployer.account });

    console.log("After upgrade - proxy:", proxy.address);
    console.log("After upgrade - implementation:", implV2.address);

    // Verify new implementation function exists at proxy address
    const nftAuctionV2AtProxy = await viem.getContractAt("NFTAuctionV2", proxy.address);
    const hello = await nftAuctionV2AtProxy.read.HelloWorld();
    console.log("HelloWorld():", hello);
    assert.strictEqual(hello, "Hello World");

    // Verify storage (owner) preserved after upgrade
    const ownerAfter = (await nftAuctionV2AtProxy.read.owner()) as `0x${string}`;
    assert.strictEqual(ownerAfter.toLowerCase(), deployer.account.address.toLowerCase());
});

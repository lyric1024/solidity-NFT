import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("NFTAuctionModuleV1", (m) => {
    // 部署实现合约（implementation）
    const impl = m.contract("NFTAuction", [], { id: "NFTAuctionImpl" });

    // 部署 ERC1967 proxy，构造函数参数：implementation address + init calldata
    // 我们这里不传 init calldata（使用 "0x"），因此需要在部署后通过代理地址调用 `initialize`。
    const proxy = m.contract("MyERC1967Proxy", [impl, "0x"], { id: "NFTAuctionProxy" });

    // 在代理上调用 initialize()（NFTAuction.initialize() 无需参数）
    // 使用实现合约的 ABI 在代理地址上执行初始化调用
    const nftAuctionAtProxy = m.contractAt("NFTAuction", proxy, { id: "NFTAuctionAtProxy" });
    m.call(nftAuctionAtProxy, "initialize", []);

    // 导出代理地址作为 nftAuction 引用
    return { nftAuction: proxy };
});
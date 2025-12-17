import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("NFTAuctionModule", (m) => {
    // 首次运行：部署代理 + 实现
    // 后续运行：自动升级（因为名字相同）
    const nftAuction = m.contract("NFTAuction");
    // 如果是 V2，可选：调用 initializeV2
    // 注意：只有升级后才需要这行！首次部署会失败（因为 reinitializer(2) 不能在 version=1 时调）
    // 所以建议手动调用，或通过条件判断（Ignition 目前不支持条件调用）
    // m.call(nftAuction, "initializeV2", [deployer]);
    
    return { nftAuction };
});
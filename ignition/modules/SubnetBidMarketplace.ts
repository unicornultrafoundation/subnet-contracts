import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const UpgradeSubnetBidMarketplaceModule = buildModule("SubnetBidMarketplace", (m) => {
  const proxyAdminOwner = m.getAccount(0);
  const SubnetBidMarketplace = m.contract("SubnetBidMarketplace");
  const proxy = m.contract("TransparentUpgradeableProxy", [
    SubnetBidMarketplace,
    proxyAdminOwner,
    "0x",
  ]);

  const proxyAdminAddress = m.readEventArgument(
    proxy,
    "AdminChanged",
    "newAdmin"
  );

  const proxyAdmin = m.contractAt("ProxyAdmin", proxyAdminAddress);

  return { proxyAdmin, proxy };
});

export default UpgradeSubnetBidMarketplaceModule;

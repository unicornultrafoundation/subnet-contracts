import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const SubnetDirectProviderMarketplaceModule = buildModule("SubnetDirectProviderMarketplace", (m) => {
  const proxyAdminOwner = m.getAccount(0);
  const SubnetDirectProviderMarketplace = m.contract("SubnetDirectProviderMarketplace");
  const proxy = m.contract("TransparentUpgradeableProxy", [
    SubnetDirectProviderMarketplace,
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

export default SubnetDirectProviderMarketplaceModule;


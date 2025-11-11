import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const SubnetFixedPriceMarketplaceModule = buildModule("SubnetFixedPriceMarketplace", (m) => {
  const proxyAdminOwner = m.getAccount(0);
  const SubnetFixedPriceMarketplace = m.contract("SubnetFixedPriceMarketplace");
  const proxy = m.contract("TransparentUpgradeableProxy", [
    SubnetFixedPriceMarketplace,
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

export default SubnetFixedPriceMarketplaceModule;


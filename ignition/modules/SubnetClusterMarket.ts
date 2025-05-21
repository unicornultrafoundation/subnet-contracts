import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const UpgradeSubnetClusterMarketModule = buildModule("SubnetClusterMarket", (m) => {
  const proxyAdminOwner = m.getAccount(0);
  const SubnetClusterMarket = m.contract("SubnetClusterMarket");
  const proxy = m.contract("TransparentUpgradeableProxy", [
    SubnetClusterMarket,
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

export default UpgradeSubnetClusterMarketModule;

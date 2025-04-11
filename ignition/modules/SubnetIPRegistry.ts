import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const UpgradeSubnetIPRegistryModule = buildModule("SubnetIPRegistry", (m) => {
  const proxyAdminOwner = m.getAccount(0);
  const SubnetIPRegistry = m.contract("SubnetIPRegistry");
  const proxy = m.contract("TransparentUpgradeableProxy", [
    SubnetIPRegistry,
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

export default UpgradeSubnetIPRegistryModule;

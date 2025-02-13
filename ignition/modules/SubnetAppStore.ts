import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const UpgradeSubnetAppStoreModule = buildModule("SubnetAppStore", (m) => {
  const proxyAdminOwner = m.getAccount(0);
  const SubnetAppStore = m.contract("SubnetAppStore");
  const proxy = m.contract("TransparentUpgradeableProxy", [
    SubnetAppStore,
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

export default UpgradeSubnetAppStoreModule;

import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const UpgradeSubnetProviderModule = buildModule("SubnetProvider", (m) => {
  const proxyAdminOwner = m.getAccount(0);
  const SubnetProvider = m.contract("SubnetProvider");
  const proxy = m.contract("TransparentUpgradeableProxy", [
    SubnetProvider,
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

export default UpgradeSubnetProviderModule;

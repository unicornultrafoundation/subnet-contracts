import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const UpgradeSubnetProviderUptimeModule = buildModule(
  "SubnetProviderUptime",
  (m) => {
    const proxyAdminOwner = m.getAccount(0);
    const SubnetProviderUptime = m.contract("SubnetProviderUptime");
    const proxy = m.contract("TransparentUpgradeableProxy", [
      SubnetProviderUptime,
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
  }
);

export default UpgradeSubnetProviderUptimeModule;

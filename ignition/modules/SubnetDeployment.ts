import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const UpgradeSubnetDeploymentModule = buildModule("SubnetDeployment", (m) => {
  const proxyAdminOwner = m.getAccount(0);
  const SubnetDeployment = m.contract("SubnetDeployment");
  const proxy = m.contract("TransparentUpgradeableProxy", [
    SubnetDeployment,
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

export default UpgradeSubnetDeploymentModule;

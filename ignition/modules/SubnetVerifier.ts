import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const SubnetVerifierModule = buildModule("SubnetVerifier", (m) => {
  const proxyAdminOwner = m.getAccount(0);
  const SubnetProvider = m.contract("SubnetVerifier");
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

export default SubnetVerifierModule;

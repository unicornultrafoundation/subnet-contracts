import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import UpgradeSubnetAppStoreModule from "./SubnetAppStore";

const UpgradeSubnetAppStoreV2Module = buildModule("SubnetAppStoreV2", (m) => {
  const proxyAdminOwner = m.getAccount(0);
  const { proxyAdmin, proxy } = m.useModule(UpgradeSubnetAppStoreModule);


  const SubnetAppStoreV2 = m.contract("SubnetAppStoreV2");

  m.call(proxyAdmin, "upgradeAndCall", [proxy, SubnetAppStoreV2, "0x"], {
    from: proxyAdminOwner,
  });

  return { proxyAdmin, proxy };

});

export default UpgradeSubnetAppStoreV2Module;

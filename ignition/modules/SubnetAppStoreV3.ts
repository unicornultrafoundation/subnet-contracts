import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import UpgradeSubnetAppStoreModule from "./SubnetAppStoreV2";

const UpgradeSubnetAppStoreV3Module = buildModule("SubnetAppStoreV3", (m) => {
  const proxyAdminOwner = m.getAccount(0);
  const { proxyAdmin, proxy } = m.useModule(UpgradeSubnetAppStoreModule);


  const SubnetAppStoreV3 = m.contract("SubnetAppStoreV3");

  m.call(proxyAdmin, "upgradeAndCall", [proxy, SubnetAppStoreV3, "0x"], {
    from: proxyAdminOwner,
  });

  return { proxyAdmin, proxy };

});

export default UpgradeSubnetAppStoreV3Module;

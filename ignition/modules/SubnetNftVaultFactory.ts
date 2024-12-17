// This setup uses Hardhat Ignition to manage smart contract deployments.
// Learn more about it at https://hardhat.org/ignition

import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const SubnetNftVaultModule = buildModule("SubnetNftVaultFactory", (m) => {
  const deployer = '0xA80805588121246a5688De1BC13c654870a4Ae24'
  const subnetNftVaultFactory = m.contract("SubnetNftVaultFactory", [deployer], {});
  return { subnetNftVaultFactory };
});

export default SubnetNftVaultModule;

// This setup uses Hardhat Ignition to manage smart contract deployments.
// Learn more about it at https://hardhat.org/ignition

import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const SubnetStakingPoolFactoryModule = buildModule("SubnetStakingPoolFactory", (m) => {
  const deployer = '0x8cb3C64E938065b1Ab4b137dB2b0e9953f66c3Eb'
  const subnetStakingPoolFactory = m.contract("SubnetStakingPoolFactory", [deployer], {});
  return { subnetStakingPoolFactory };
});

export default SubnetStakingPoolFactoryModule;

// This setup uses Hardhat Ignition to manage smart contract deployments.
// Learn more about it at https://hardhat.org/ignition

import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const SubnetProviderModule = buildModule("SubnetProvider", (m) => {
  const subnetProvider = m.contract("SubnetProvider");

  return { subnetProvider };
});

export default SubnetProviderModule;

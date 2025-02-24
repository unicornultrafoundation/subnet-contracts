// This setup uses Hardhat Ignition to manage smart contract deployments.
// Learn more about it at https://hardhat.org/ignition

import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const SubnetTokenModule = buildModule("SubnetToken", (m) => {
  const owner = m.getAccount(0);
  const subnetToken = m.contract("SubnetToken", [owner]);

  return { subnetToken };
});

export default SubnetTokenModule;

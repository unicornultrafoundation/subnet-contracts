// This setup uses Hardhat Ignition to manage smart contract deployments.
// Learn more about it at https://hardhat.org/ignition

import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const RewardTokenModule = buildModule("RewardToken", (m) => {
  const rewardToken = m.contract("ERC20Mock", ["RewardToken", "RTK"]);

  return { rewardToken };
});

export default RewardTokenModule;

// This setup uses Hardhat Ignition to manage smart contract deployments.
// Learn more about it at https://hardhat.org/ignition

import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

// Define the deployment module for SubnetRegistry
const SubnetRegistryModule = buildModule("SubnetRegistry", (m) => {
  const nftContractAddress = "0xYourNFTContractAddress"; // Replace with your NFT contract address
  const ownerAddress = "0x"; // Replace with your owner address
  const rewardPerSecond = 1_000_000_000_000_000n; // Reward rate in wei (e.g., 0.001 ETH per second)

  // Deploy the SubnetRegistry contract
  const subnetRegistry = m.contract("SubnetRegistry", [ownerAddress, nftContractAddress, rewardPerSecond]);

  return { subnetRegistry };
});

export default SubnetRegistryModule;

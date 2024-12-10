// This setup uses Hardhat Ignition to manage smart contract deployments.
// Learn more about it at https://hardhat.org/ignition

import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";



const SubnetRegistryModule = buildModule("SubnetRegistry", (m) => {
  // Constants
  const NFT_CONTRACT_ADDRESS = "0x9CEb5fBb9734aC71F365d7cc0EedA48bB9763891"; // Replace with your NFT contract address
  const REWARD_PER_SECOND = 1000000000000000n; // Example: 0.001 ether per second

  const subnetRegistry = m.contract(
    "SubnetRegistry", 
    ["0x8cb3C64E938065b1Ab4b137dB2b0e9953f66c3Eb", NFT_CONTRACT_ADDRESS, REWARD_PER_SECOND], // Constructor arguments
  );

  return { subnetRegistry };
});

export default SubnetRegistryModule;

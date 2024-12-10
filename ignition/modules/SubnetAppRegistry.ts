// This setup uses Hardhat Ignition to manage smart contract deployments.
// Learn more about it at https://hardhat.org/ignition

import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const SubnetAppRegistryModule = buildModule("SubnetAppRegistryDeployment", (m) => {
  // Declare dependencies
  const subnetRegistryAddress = "0x857C4FB4d4195A24ce78E840b01261C5F9d8c9BF"; // Replace with actual SubnetRegistry address
  const treasuryAddress = "0x8cb3C64E938065b1Ab4b137dB2b0e9953f66c3Eb"; // Replace with the treasury address
  const feeRate = 50; // Example: 5% fee rate (50 per thousand)

  // Deploy the SubnetAppRegistry contract
  const subnetAppRegistry = m.contract(
    "SubnetAppRegistry",
    [subnetRegistryAddress,  "0x8cb3C64E938065b1Ab4b137dB2b0e9953f66c3Eb", treasuryAddress, feeRate], // Constructor arguments
    {}
  );

  return { subnetAppRegistry };
});

export default SubnetAppRegistryModule;

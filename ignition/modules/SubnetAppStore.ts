// This setup uses Hardhat Ignition to manage smart contract deployments.
// Learn more about it at https://hardhat.org/ignition

import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import SubnetProviderModule from "./SubnetProvider";

const SubnetAppStoreModule = buildModule("SubnetAppStore", (m) => {
  const { subnetProvider } = m.useModule(SubnetProviderModule)
  const ownerAddress = '0x8cb3C64E938065b1Ab4b137dB2b0e9953f66c3Eb';
  const treasuryAddress = '0x8cb3C64E938065b1Ab4b137dB2b0e9953f66c3Eb';
  const feeRate = 50; // Fee rate: 5%

  const subnetAppStore = m.contract("SubnetAppStore", [
    subnetProvider,
    ownerAddress,
    treasuryAddress,
    feeRate
  ]);

  return { subnetAppStore };
});

export default SubnetAppStoreModule;

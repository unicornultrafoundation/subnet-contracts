// This setup uses Hardhat Ignition to manage smart contract deployments.
// Learn more about it at https://hardhat.org/ignition

import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const NftLicenseModule = buildModule("NftLicense", (m) => {
  const nft = m.contract("TestNFT", [], {});
  return { nft };
});

export default NftLicenseModule;

// This setup uses Hardhat Ignition to manage smart contract deployments.
// Learn more about it at https://hardhat.org/ignition

import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import { ethers } from "hardhat";
import SubnetProviderModule from "./SubnetProvider";

const SubnetProviderUptimeModule = buildModule("SubnetProviderUptime", (m) => {
    const { subnetProvider } = m.useModule(SubnetProviderModule)
    const ownerAddress = '0x8cb3C64E938065b1Ab4b137dB2b0e9953f66c3Eb';
    const rewardTokenAddress = '0x96BcC1F417e087C9505C52362c63f8b5d97087b5';
    const rewardPerSecond = ethers.parseEther("0.01");

    const subnetProviderUptime = m.contract("SubnetProviderUptime", [
        ownerAddress,
        subnetProvider,
        rewardTokenAddress,
        rewardPerSecond,
        "12D3KooWGNQYBFWmKgiAgEsQ4u2WznEgR2NmrBbYcfq33yQo4D8a",
        ownerAddress
    ]);

    return { subnetProviderUptime };
});

export default SubnetProviderUptimeModule;

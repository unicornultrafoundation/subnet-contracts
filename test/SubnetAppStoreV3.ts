import { ethers, ignition } from 'hardhat';
import { expect } from 'chai';
import { SubnetAppStoreV3, SubnetProvider, ERC20Mock, SubnetVerifier } from '../typechain-types';
import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers';
import UpgradeSubnetAppStoreV3Module from '../ignition/modules/SubnetAppStoreV3';
import UpgradeSubnetProviderModule from '../ignition/modules/SubnetProvider';

describe("SubnetAppStoreV3", function () {
    let subnetAppStore: SubnetAppStoreV3;
    let subnetProvider: SubnetProvider;
    let subnetVerifier: SubnetVerifier;
    let token: ERC20Mock;
    let owner: HardhatEthersSigner, addr1: HardhatEthersSigner, addr2: HardhatEthersSigner, addr3: HardhatEthersSigner;

    beforeEach(async function () {
        [owner, addr1, addr2, addr3] = await ethers.getSigners();

        const { proxy: subnetProviderProxy } = await ignition.deploy(UpgradeSubnetProviderModule);
        subnetProvider = await ethers.getContractAt("SubnetProvider", await subnetProviderProxy.getAddress());
        await subnetProvider.initialize(owner.address);
        await subnetProvider.registerProvider("name", "metadata", owner.address, "https://provider.com");
        await subnetProvider.registerPeerNode(1, "peer1", "metadata");
        const ERC20MockFactory = await ethers.getContractFactory("ERC20Mock");
        token = await ERC20MockFactory.deploy("Test Token", "TTK");
        await token.mint(owner.address, ethers.parseEther("10000"));

        const { proxy: subnetAppStoreProxy } = await ignition.deploy(UpgradeSubnetAppStoreV3Module);
        subnetAppStore = await ethers.getContractAt("SubnetAppStoreV3", await subnetAppStoreProxy.getAddress());
        await subnetAppStore.initialize(
            subnetProvider.getAddress(),
            owner.address,
            owner.address,
            50, // feeRate
            3600 // rewardLockDuration
        );

        const SubnetVerifierFactory = await ethers.getContractFactory("SubnetVerifier");
        subnetVerifier = await SubnetVerifierFactory.deploy();
        await subnetVerifier.initialize(owner.address, token.getAddress(), ethers.parseEther("100"), 86400);

        await subnetAppStore.setSubnetVerifier(subnetVerifier.getAddress());
    });

    it("should remove inactive verifier", async function () {
        const peerIds = ["peer1"];
        const budget = ethers.parseEther("1000");
        const appId = 1;

        await token.approve(subnetAppStore.getAddress(), budget);
        const tx = await subnetAppStore.createApp(
            "TestApp",
            "TST",
            peerIds,
            budget,
            10,
            20,
            30,
            40,
            50,
            "metadata",
            addr1.address,
            addr2.address,
            token.getAddress()
        );


        const verifiers = [addr1.address, addr2.address, addr3.address];
        await subnetAppStore.updateVerifiers(appId, verifiers);

        await token.approve(subnetVerifier.getAddress(), ethers.parseEther("100"));
        await subnetVerifier.register(addr1.address, "peer1", "Verifier1", "https://verifier1.com", "metadata1");

        await token.approve(subnetVerifier.getAddress(), ethers.parseEther("100"));
        await subnetVerifier.register(addr2.address, "peer2", "Verifier2", "https://verifier2.com", "metadata2");

        await token.approve(subnetVerifier.getAddress(), ethers.parseEther("100"));
        await subnetVerifier.register(addr3.address, "peer3", "Verifier3", "https://verifier3.com", "metadata3");

        await subnetVerifier.slash(addr2.address, 50);

        await subnetAppStore.removeInactiveVerifier(appId, 1);

        const verifier0 = await subnetAppStore.appVerifiers(appId, 0);
        expect(verifier0).to.equal(addr1.address);
        const verifier1 = await subnetAppStore.appVerifiers(appId, 1);
        expect(verifier1).to.equal(addr3.address);
    });

    it("should report usage", async function () {
        const peerIds = ["peer1"];
        const budget = ethers.parseEther("1000");
        const appId = 1;

        await token.approve(subnetAppStore.getAddress(), budget);
        const tx = await subnetAppStore.createApp(
            "TestApp",
            "TST",
            peerIds,
            budget,
            10,
            20,
            30,
            40,
            50,
            "metadata",
            addr1.address,
            addr2.address,
            token.getAddress()
        );

        const verifiers = [addr1.address, addr2.address, owner.address];
        await subnetAppStore.updateVerifiers(appId, verifiers);
        const usage = {
            appId: appId,
            providerId: 1,
            peerId: "peer1",
            usedCpu: 10,
            usedGpu: 20,
            usedMemory: 30,
            usedStorage: 40,
            usedUploadBytes: 50,
            usedDownloadBytes: 60,
            duration: 70,
            timestamp: Math.floor(Date.now() / 1000)
        };

        const signatures = await signUsage(usage, [addr1, addr2, owner]);

        await subnetAppStore.reportUsage(
            usage.appId,
            usage.providerId,
            usage.peerId,
            usage.usedCpu,
            usage.usedGpu,
            usage.usedMemory,
            usage.usedStorage,
            usage.usedUploadBytes,
            usage.usedDownloadBytes,
            usage.duration,
            usage.timestamp,
            signatures
        );


        const pendingReward = await subnetAppStore.getPendingReward(appId, 1);
        expect(pendingReward).to.equal(95);
    });

    async function signUsage(usage: any, signers: HardhatEthersSigner[]) {
        const domain = {
            name: "SubnetAppStore",
            version: "1",
            chainId: (await ethers.provider.getNetwork()).chainId,
            verifyingContract: await subnetAppStore.getAddress(),
        };

        const types = {
            Usage: [
                { name: "appId", type: "uint256" },
                { name: "providerId", type: "uint256" },
                { name: "peerId", type: "string" },
                { name: "usedCpu", type: "uint256" },
                { name: "usedGpu", type: "uint256" },
                { name: "usedMemory", type: "uint256" },
                { name: "usedStorage", type: "uint256" },
                { name: "usedUploadBytes", type: "uint256" },
                { name: "usedDownloadBytes", type: "uint256" },
                { name: "duration", type: "uint256" },
                { name: "timestamp", type: "uint256" },
            ],
        };

        let signatures = "0x"; // hex prefix

        for (const signer of signers) {
            const signature = await signer.signTypedData(domain, types, usage);
            signatures += signature.slice(2); // remove hex prefix
        }
    
        return signatures;
    }
});

import { ethers } from 'hardhat';
import { expect } from 'chai';
import { ERC20Mock, SubnetAppStore, SubnetProvider } from '../typechain-types';
import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers';

describe("SubnetAppStore", function () {
    let subnetAppStore: SubnetAppStore;
    let subnetProvider: SubnetProvider;
    let owner: HardhatEthersSigner, treasury: HardhatEthersSigner, addr1: HardhatEthersSigner, addr2: HardhatEthersSigner;
    let rewardToken: ERC20Mock;

    beforeEach(async function () {
        [owner, treasury, addr1, addr2] = await ethers.getSigners();

        const MockErc20 = await ethers.getContractFactory("ERC20Mock");
        rewardToken = await MockErc20.deploy("Reward Token", "RT");

        // Deploy SubnetProvider contract
        const SubnetProviderFactory = await ethers.getContractFactory("SubnetProvider");
        subnetProvider = await SubnetProviderFactory.deploy();

        await subnetProvider.registerProvider("name", "metadata");

        // Deploy SubnetAppStore contract
        const SubnetAppStoreFactory = await ethers.getContractFactory("SubnetAppStore");
        subnetAppStore = await SubnetAppStoreFactory.deploy(
            await subnetProvider.getAddress(),
            owner.address,
            treasury.address,
            50 // Fee rate: 5%
        );

        await rewardToken.mint(owner.address, ethers.parseEther("10000"));
        await rewardToken.approve(subnetAppStore.getAddress(), ethers.parseEther("10000"));
    });

    async function createApp() {
        const appBudget = ethers.parseEther("10"); // 10 ETH
        const operator = owner.address;

        await subnetAppStore.createApp(
            "TestApp",
            "TAPP",
            "peer123",
            appBudget,
            10, // maxNodes
            2, // minCpu
            1, // minGpu
            4, // minMemory
            10, // minUploadBandwidth
            20, // minDownloadBandwidth
            1, // pricePerCpu
            1, // pricePerGpu
            1, // pricePerMemoryGB
            1, // pricePerStorageGB
            1, // pricePerBandwidthGB
            "metadata",
            operator,
            await rewardToken.getAddress() // paymentToken
        );
    }

    it("should allow creating a new application", async function () {
        await createApp();

        const app = await subnetAppStore.apps(1);
        expect(app.name).to.equal("TestApp");
        expect(app.symbol).to.equal("TAPP");
        expect(app.peerId).to.equal("peer123");
        expect(app.budget).to.equal(ethers.parseEther("10"));
        expect(app.maxNodes).to.equal(10);
        expect(app.owner).to.equal(owner.address);
        expect(app.operator).to.equal(owner.address);
    });

    describe("Update App Fields", function () {
        beforeEach(async function () {
            await createApp();
        });

        it("should allow updating the metadata of an application", async function () {
            const newMetadata = "new metadata";
            await subnetAppStore.connect(owner).updateMetadata(1, newMetadata);

            const app = await subnetAppStore.apps(1);
            expect(app.metadata).to.equal(newMetadata);
        });

        it("should allow updating the name of an application", async function () {
            const newName = "NewAppName";
            await subnetAppStore.connect(owner).updateName(1, newName);

            const app = await subnetAppStore.apps(1);
            expect(app.name).to.equal(newName);
        });

        it("should allow updating the operator of an application", async function () {
            const newOperator = addr1.address;
            await subnetAppStore.connect(owner).updateOperator(1, newOperator);

            const app = await subnetAppStore.apps(1);
            expect(app.operator).to.equal(newOperator);
        });
    });

    describe("Report Usage", function () {
        beforeEach(async function () {
            await createApp();
            await subnetProvider.registerProvider("provider1", "metadata1");
        });

        it("should report usage and calculate rewards", async function () {
            const providerId = 1;
            const appId = 1;
            const usageData = {
                providerId: providerId,
                appId: appId,
                usedCpu: 10,
                usedGpu: 5,
                usedMemory: 10 * 1e9,
                usedStorage: 20 * 1e9,
                usedUploadBytes: 1e9, // 1 GB
                usedDownloadBytes: 2e9, // 2 GB
                duration: 3600 // 1 hour
            };

            const domain = {
                name: "SubnetAppRegistry",
                version: "1",
                chainId: (await ethers.provider.getNetwork()).chainId,
                verifyingContract: await subnetAppStore.getAddress()
            };

            const types = {
                Usage: [
                    { name: "providerId", type: "uint256" },
                    { name: "appId", type: "uint256" },
                    { name: "usedCpu", type: "uint256" },
                    { name: "usedGpu", type: "uint256" },
                    { name: "usedMemory", type: "uint256" },
                    { name: "usedStorage", type: "uint256" },
                    { name: "usedUploadBytes", type: "uint256" },
                    { name: "usedDownloadBytes", type: "uint256" },
                    { name: "duration", type: "uint256" }
                ]
            };

            const signature = await owner.signTypedData(domain, types, usageData);

            await subnetAppStore.reportUsage(
                usageData.providerId,
                usageData.appId,
                usageData.usedCpu,
                usageData.usedGpu,
                usageData.usedMemory,
                usageData.usedStorage,
                usageData.usedUploadBytes,
                usageData.usedDownloadBytes,
                usageData.duration,
                signature
            );

            const deployment = await subnetAppStore.getDeployment(appId, providerId);
            expect(deployment.usedCpu).to.equal(usageData.usedCpu);
            expect(deployment.usedGpu).to.equal(usageData.usedGpu);
            expect(deployment.usedMemory).to.equal(usageData.usedMemory);
            expect(deployment.usedStorage).to.equal(usageData.usedStorage);
            expect(deployment.usedUploadBytes).to.equal(usageData.usedUploadBytes);
            expect(deployment.usedDownloadBytes).to.equal(usageData.usedDownloadBytes);
            expect(deployment.duration).to.equal(usageData.duration);
        });

        it("should revert if the signature is invalid", async function () {
            const providerId = 1;
            const appId = 1;
            const usageData = {
                providerId: providerId,
                appId: appId,
                usedCpu: 10,
                usedGpu: 5,
                usedMemory: 10 * 1e9,
                usedStorage: 20 * 1e9,
                usedUploadBytes: 1e9, // 1 GB
                usedDownloadBytes: 2e9, // 2 GB
                duration: 3600 // 1 hour
            };

            const invalidSignature = "0x2e101a65cd0b9df75ea01c2ae41a32c6069ad5577aa1d5ddefd57521bc533ee1162f63b2ebad37b9a11899f1dcb0fd734793ecccd901b791f303a60db4a65a3a1b";

            await expect(
                subnetAppStore.reportUsage(
                    usageData.providerId,
                    usageData.appId,
                    usageData.usedCpu,
                    usageData.usedGpu,
                    usageData.usedMemory,
                    usageData.usedStorage,
                    usageData.usedUploadBytes,
                    usageData.usedDownloadBytes,
                    usageData.duration,
                    invalidSignature
                )
            ).to.be.revertedWith("Invalid app owner or operator signature");
        });

        it("should revert if the app budget is exhausted", async function () {
            const providerId = 1;
            const appId = 1;
            const usageData = {
                providerId: providerId,
                appId: appId,
                usedCpu: ethers.parseEther("100"),
                usedGpu: 500,
                usedMemory: 1000 * 1e9,
                usedStorage: 2000 * 1e9,
                usedUploadBytes: 1000e9, // 1000 GB
                usedDownloadBytes: 2000e9, // 2000 GB
                duration: 3600 // 1 hour
            };

            const domain = {
                name: "SubnetAppRegistry",
                version: "1",
                chainId: (await ethers.provider.getNetwork()).chainId,
                verifyingContract: await subnetAppStore.getAddress()
            };

            const types = {
                Usage: [
                    { name: "providerId", type: "uint256" },
                    { name: "appId", type: "uint256" },
                    { name: "usedCpu", type: "uint256" },
                    { name: "usedGpu", type: "uint256" },
                    { name: "usedMemory", type: "uint256" },
                    { name: "usedStorage", type: "uint256" },
                    { name: "usedUploadBytes", type: "uint256" },
                    { name: "usedDownloadBytes", type: "uint256" },
                    { name: "duration", type: "uint256" }
                ]
            };

            const signature = await owner.signTypedData(domain, types, usageData);

            await expect(
                subnetAppStore.reportUsage(
                    usageData.providerId,
                    usageData.appId,
                    usageData.usedCpu,
                    usageData.usedGpu,
                    usageData.usedMemory,
                    usageData.usedStorage,
                    usageData.usedUploadBytes,
                    usageData.usedDownloadBytes,
                    usageData.duration,
                    signature
                )
            ).to.be.revertedWith("Insufficient budget");
        });
    });

    describe("Claim Reward", function () {
        beforeEach(async function () {
            await createApp();
            await subnetProvider.registerProvider("provider1", "metadata1");
        });

        it("should allow a node to claim a reward successfully", async function () {
            const providerId = 1;
            const appId = 1;

            const usageData = {
                providerId: providerId,
                appId: appId,
                usedCpu: 10,
                usedGpu: 5,
                usedMemory: 10 * 1e9,
                usedStorage: 20 * 1e9,
                usedUploadBytes: 1e9, // 1 GB
                usedDownloadBytes: 2e9, // 2 GB
                duration: 3600 // 1 hour
            };

            const domain = {
                name: "SubnetAppRegistry",
                version: "1",
                chainId: (await ethers.provider.getNetwork()).chainId,
                verifyingContract: await subnetAppStore.getAddress()
            };

            const types = {
                Usage: [
                    { name: "providerId", type: "uint256" },
                    { name: "appId", type: "uint256" },
                    { name: "usedCpu", type: "uint256" },
                    { name: "usedGpu", type: "uint256" },
                    { name: "usedMemory", type: "uint256" },
                    { name: "usedStorage", type: "uint256" },
                    { name: "usedUploadBytes", type: "uint256" },
                    { name: "usedDownloadBytes", type: "uint256" },
                    { name: "duration", type: "uint256" }
                ]
            };

            const signature = await owner.signTypedData(domain, types, usageData);

            await subnetAppStore.reportUsage(
                usageData.providerId,
                usageData.appId,
                usageData.usedCpu,
                usageData.usedGpu,
                usageData.usedMemory,
                usageData.usedStorage,
                usageData.usedUploadBytes,
                usageData.usedDownloadBytes,
                usageData.duration,
                signature
            );

            // Simulate 30 days passing
            await ethers.provider.send("evm_increaseTime", [30 * 24 * 60 * 60]);
            await ethers.provider.send("evm_mine", []);

            const initialTreasuryBalance = await rewardToken.balanceOf(treasury.address);
            const initialNodeBalance = await rewardToken.balanceOf(owner.address);

            await expect(
                subnetAppStore.claimReward(providerId, appId)
            )
                .to.emit(subnetAppStore, "RewardClaimed")
                .withArgs(appId, providerId, 108018n);

            const finalTreasuryBalance = await rewardToken.balanceOf(treasury.address);
            const finalNodeBalance = await rewardToken.balanceOf(owner.address);

            const expectedReward = 108018n;
            const fee = expectedReward * 50n/1000n;
            const netReward = expectedReward - fee;

            expect(finalTreasuryBalance- initialTreasuryBalance).to.equal(fee);
            expect(finalNodeBalance - initialNodeBalance).to.equal(netReward);
        });

        it("should revert if the claim is not yet unlocked", async function () {
            const providerId = 1;
            const appId = 1;

            const usageData = {
                providerId: providerId,
                appId: appId,
                usedCpu: 10,
                usedGpu: 5,
                usedMemory: 10 * 1e9,
                usedStorage: 20 * 1e9,
                usedUploadBytes: 1e9, // 1 GB
                usedDownloadBytes: 2e9, // 2 GB
                duration: 3600 // 1 hour
            };

            const domain = {
                name: "SubnetAppRegistry",
                version: "1",
                chainId: (await ethers.provider.getNetwork()).chainId,
                verifyingContract: await subnetAppStore.getAddress()
            };

            const types = {
                Usage: [
                    { name: "providerId", type: "uint256" },
                    { name: "appId", type: "uint256" },
                    { name: "usedCpu", type: "uint256" },
                    { name: "usedGpu", type: "uint256" },
                    { name: "usedMemory", type: "uint256" },
                    { name: "usedStorage", type: "uint256" },
                    { name: "usedUploadBytes", type: "uint256" },
                    { name: "usedDownloadBytes", type: "uint256" },
                    { name: "duration", type: "uint256" }
                ]
            };

            const signature = await owner.signTypedData(domain, types, usageData);

            await subnetAppStore.reportUsage(
                usageData.providerId,
                usageData.appId,
                usageData.usedCpu,
                usageData.usedGpu,
                usageData.usedMemory,
                usageData.usedStorage,
                usageData.usedUploadBytes,
                usageData.usedDownloadBytes,
                usageData.duration,
                signature
            );

            await expect(
                subnetAppStore.claimReward(providerId, appId)
            ).to.be.revertedWith("Claim not yet unlocked");
        });
    });
});

import { ethers, ignition } from 'hardhat';
import { expect } from 'chai';
import { ERC20Mock, SubnetAppStore, SubnetProvider } from '../typechain-types';
import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers';
import SubnetProviderModule from '../ignition/modules/SubnetProvider';
import SubnetAppStoreModule from '../ignition/modules/SubnetAppStore';

describe("SubnetAppStore", function () {
    let subnetAppStore: SubnetAppStore;
    let subnetProvider: SubnetProvider;
    let owner: HardhatEthersSigner, operator: HardhatEthersSigner, treasury: HardhatEthersSigner, addr1: HardhatEthersSigner, addr2: HardhatEthersSigner, verifier: HardhatEthersSigner;
    let rewardToken: ERC20Mock;

    beforeEach(async function () {
        [owner, operator, treasury, addr1, addr2, verifier] = await ethers.getSigners();

        const MockErc20 = await ethers.getContractFactory("ERC20Mock");
        rewardToken = await MockErc20.deploy("Reward Token", "RT");

        const { proxy: subnetProviderProxy } = await ignition.deploy(SubnetProviderModule);
        subnetProvider = await ethers.getContractAt("SubnetProvider", await subnetProviderProxy.getAddress());
        await subnetProvider.initialize(verifier.address);
        await subnetProvider.registerProvider("name", "metadata", owner.address, "https://provider.com");

        // Deploy subnetAppStoreProxy contract
        const { proxy: subnetAppStoreProxy } = await ignition.deploy(SubnetAppStoreModule);
        subnetAppStore = await ethers.getContractAt("SubnetAppStore", await subnetAppStoreProxy.getAddress());
        await subnetAppStore.initialize(await subnetProvider.getAddress(), owner.address, treasury.address, 50, 30 * 24 * 60 * 60); // Fee rate: 5%, Reward lock duration: 30 days
        await rewardToken.mint(owner.address, ethers.parseEther("10000"));
        await rewardToken.approve(subnetAppStore.getAddress(), ethers.parseEther("10000"));
    });

    async function createApp() {
        const appBudget = ethers.parseEther("10"); // 10 ETH

        await subnetAppStore.createApp(
            "TestApp",
            "TAPP",
            ["peer123"],
            appBudget,
            ethers.parseEther("0.00001"), // pricePerCpu
            ethers.parseEther("0.00001"), // pricePerGpu
            ethers.parseEther("0.00001"), // pricePerMemoryGB
            ethers.parseEther("0.00001"), // pricePerStorageGB
            ethers.parseEther("0.00001"), // pricePerBandwidthGB
            "metadata",
            operator.address,
            operator.address, // verifier
            await rewardToken.getAddress() // paymentToken
        );
    }

    it("should allow creating a new application", async function () {
        await createApp();

        const app = await subnetAppStore.getApp(1);
        expect(app.name).to.equal("TestApp");
        expect(app.symbol).to.equal("TAPP");
        expect(app.peerIds[0]).to.equal("peer123");
        expect(app.budget).to.equal(ethers.parseEther("10"));
        expect(app.owner).to.equal(owner.address);
        expect(app.operator).to.equal(operator.address);
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

    describe("Update PeerId", function () {
        beforeEach(async function () {
            await createApp();
        });

        it("should allow the owner to update the peerId", async function () {
            await subnetAppStore.connect(owner).updatePeerId(1, ["newPeerId"]);
            const app = await subnetAppStore.getApp(1);
            expect(app.peerIds[0]).to.equal("newPeerId");
        });

        it("should allow the operator to update the peerId", async function () {
            await subnetAppStore.connect(owner).updateOperator(1, addr1.address);
            await subnetAppStore.connect(addr1).updatePeerId(1, ["newPeerId"]);
            const app = await subnetAppStore.getApp(1);
            expect(app.peerIds[0]).to.equal("newPeerId");
        });

        it("should not allow others to update the peerId", async function () {
            await expect(
                subnetAppStore.connect(addr2).updatePeerId(1, ["newPeerId"])
            ).to.be.revertedWith("Only the owner or operator can update the peerId");
        });
    });

    describe("Report Usage", function () {
        beforeEach(async function () {
            await createApp();
            await subnetProvider.registerProvider("provider1", "metadata1", owner.address, "https://provider1.com");
            await subnetProvider.registerPeerNode(1, "peer123", "metadata");
        });

        it("should report usage and calculate rewards", async function () {
            const providerId = 1;
            const appId = 1;
            const usageData = {
                providerId: providerId,
                appId: appId,
                peerId: "peer123",
                usedCpu: 10,
                usedGpu: 5,
                usedMemory: 10 * 1e9,
                usedStorage: 20 * 1e9,
                usedUploadBytes: 1e9, // 1 GB
                usedDownloadBytes: 2e9, // 2 GB
                duration: 3600, // 1 hour
                timestamp: Math.floor(Date.now() / 1000)
            };

            const domain = {
                name: "SubnetAppStore",
                version: "1",
                chainId: (await ethers.provider.getNetwork()).chainId,
                verifyingContract: await subnetAppStore.getAddress()
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
                    { name: "timestamp", type: "uint256" }
                ]
            };

            const signature = await owner.signTypedData(domain, types, usageData);

            await subnetAppStore.reportUsage(
                usageData.appId,
                usageData.providerId,
                usageData.peerId,
                usageData.usedCpu,
                usageData.usedGpu,
                usageData.usedMemory,
                usageData.usedStorage,
                usageData.usedUploadBytes,
                usageData.usedDownloadBytes,
                usageData.duration,
                usageData.timestamp,
                signature
            );

            const  pendingReward = await subnetAppStore.getPendingReward(appId, providerId);
            expect(pendingReward).to.equal(1080130000000000000n);
        });

        it("should revert if the signature is invalid", async function () {
            const providerId = 1;
            const appId = 1;
            const usageData = {
                providerId: providerId,
                appId: appId,
                peerId: "peer123",
                usedCpu: 10,
                usedGpu: 5,
                usedMemory: 10 * 1e9,
                usedStorage: 20 * 1e9,
                usedUploadBytes: 1e9, // 1 GB
                usedDownloadBytes: 2e9, // 2 GB
                duration: 3600, // 1 hour
                timestamp: Math.floor(Date.now() / 1000)
            };

            const invalidSignature = "0x2e101a65cd0b9df75ea01c2ae41a32c6069ad5577aa1d5ddefd57521bc533ee1162f63b2ebad37b9a11899f1dcb0fd734793ecccd901b791f303a60db4a65a3a1b";

            await expect(
                subnetAppStore.reportUsage(
                    usageData.appId,
                    usageData.providerId,
                    usageData.peerId,
                    usageData.usedCpu,
                    usageData.usedGpu,
                    usageData.usedMemory,
                    usageData.usedStorage,
                    usageData.usedUploadBytes,
                    usageData.usedDownloadBytes,
                    usageData.duration,
                    usageData.timestamp,
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
                peerId: "peer123",
                usedCpu: ethers.parseEther("100"),
                usedGpu: 500,
                usedMemory: 1000 * 1e9,
                usedStorage: 2000 * 1e9,
                usedUploadBytes: 1000e9, // 1000 GB
                usedDownloadBytes: 2000e9, // 2000 GB
                duration: 3600, // 1 hour
                timestamp: Math.floor(Date.now() / 1000)
            };

            const domain = {
                name: "SubnetAppStore",
                version: "1",
                chainId: (await ethers.provider.getNetwork()).chainId,
                verifyingContract: await subnetAppStore.getAddress()
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
                    { name: "timestamp", type: "uint256" }
                ]
            };

            const signature = await owner.signTypedData(domain, types, usageData);

            await expect(
                subnetAppStore.reportUsage(
                    usageData.appId,
                    usageData.providerId,
                    usageData.peerId,
                    usageData.usedCpu,
                    usageData.usedGpu,
                    usageData.usedMemory,
                    usageData.usedStorage,
                    usageData.usedUploadBytes,
                    usageData.usedDownloadBytes,
                    usageData.duration,
                    usageData.timestamp,
                    signature
                )
            ).to.be.revertedWith("Insufficient budget");
        });
    });

    describe("Claim Reward", function () {
        beforeEach(async function () {
            await createApp();
            await subnetProvider.registerProvider("provider1", "metadata1", owner.address, "https://provider1.com");
            await subnetProvider.registerPeerNode(1, "peer123", "metadata");
            await rewardToken.mint(subnetAppStore.getAddress(), ethers.parseEther("100"));
        });

        it("should allow a node to claim a reward successfully", async function () {
            const providerId = 1;
            const appId = 1;

            const usageData = {
                providerId: providerId,
                appId: appId,
                peerId: "peer123",
                usedCpu: 10,
                usedGpu: 5,
                usedMemory: 10 * 1e9,
                usedStorage: 20 * 1e9,
                usedUploadBytes: 1e9, // 1 GB
                usedDownloadBytes: 2e9, // 2 GB
                duration: 3600, // 1 hour
                timestamp: Math.floor(Date.now() / 1000)
            };

            const domain = {
                name: "SubnetAppStore",
                version: "1",
                chainId: (await ethers.provider.getNetwork()).chainId,
                verifyingContract: await subnetAppStore.getAddress()
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
                    { name: "timestamp", type: "uint256" }
                ]
            };

            const signature = await owner.signTypedData(domain, types, usageData);

            await subnetAppStore.reportUsage(
                usageData.appId,
                usageData.providerId,
                usageData.peerId,
                usageData.usedCpu,
                usageData.usedGpu,
                usageData.usedMemory,
                usageData.usedStorage,
                usageData.usedUploadBytes,
                usageData.usedDownloadBytes,
                usageData.duration,
                usageData.timestamp,
                signature
            );

            // Simulate 30 days passing
            await ethers.provider.send("evm_increaseTime", [30 * 24 * 60 * 60]);
            await ethers.provider.send("evm_mine", []);

            const initialTreasuryBalance = await rewardToken.balanceOf(treasury.address);
            const initialNodeBalance = await rewardToken.balanceOf(owner.address);

            const block = await ethers.provider.getBlock("latest");

            await expect(
                subnetAppStore.claimReward(providerId, appId)
            )
                .to.emit(subnetAppStore, "RewardClaimed")
                .withArgs(appId, providerId, 1080130000000000000n, block!.timestamp + 1 + 30 * 24 * 60 * 60);

            // Simulate another 30 days passing to unlock the reward
            await ethers.provider.send("evm_increaseTime", [30 * 24 * 60 * 60]);
            await ethers.provider.send("evm_mine", []);

            await expect(
                subnetAppStore.claimReward(providerId, appId)
            )
                .to.emit(subnetAppStore, "LockedRewardPaid")
                .withArgs(appId, 1080130000000000000n, 54006500000000000n, 0, owner.address, operator.address);

            const finalTreasuryBalance = await rewardToken.balanceOf(treasury.address);
            const finalNodeBalance = await rewardToken.balanceOf(owner.address);

            const expectedReward = 1080130000000000000n;
            const fee = expectedReward * 50n / 1000n;
            const verifierFee = 0n;
            const netReward = expectedReward - fee - verifierFee;

            expect(finalTreasuryBalance - initialTreasuryBalance).to.equal(fee);
            expect(finalNodeBalance - initialNodeBalance).to.equal(netReward);
        });

        it("should revert if the claim is not yet unlocked", async function () {
            const providerId = 1;
            const appId = 1;

            const usageData = {
                providerId: providerId,
                appId: appId,
                peerId: "peer123",
                usedCpu: 10,
                usedGpu: 5,
                usedMemory: 10 * 1e9,
                usedStorage: 20 * 1e9,
                usedUploadBytes: 1e9, // 1 GB
                usedDownloadBytes: 2e9, // 2 GB,
                duration: 3600, // 1 hour
                timestamp: Math.floor(Date.now() / 1000)
            };

            const domain = {
                name: "SubnetAppStore",
                version: "1",
                chainId: (await ethers.provider.getNetwork()).chainId,
                verifyingContract: await subnetAppStore.getAddress()
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
                    { name: "timestamp", type: "uint256" }
                ]
            };

            const signature = await owner.signTypedData(domain, types, usageData);

            await subnetAppStore.reportUsage(
                usageData.appId,
                usageData.providerId,
                usageData.peerId,
                usageData.usedCpu,
                usageData.usedGpu,
                usageData.usedMemory,
                usageData.usedStorage,
                usageData.usedUploadBytes,
                usageData.usedDownloadBytes,
                usageData.duration,
                usageData.timestamp,
                signature
            );

            await subnetAppStore.claimReward(providerId, appId)

            await expect(
                subnetAppStore.claimReward(providerId, appId)
            ).to.be.revertedWith("Reward is locked");
        });

        it("should revert if the provider is jailed", async function () {
            const providerId = 1;
            const appId = 1;

            const usageData = {
                providerId: providerId,
                appId: appId,
                peerId: "peer123",
                usedCpu: 10,
                usedGpu: 5,
                usedMemory: 10 * 1e9,
                usedStorage: 20 * 1e9,
                usedUploadBytes: 1e9, // 1 GB
                usedDownloadBytes: 2e9, // 2 GB
                duration: 3600, // 1 hour
                timestamp: Math.floor(Date.now() / 1000)
            };

            const domain = {
                name: "SubnetAppStore",
                version: "1",
                chainId: (await ethers.provider.getNetwork()).chainId,
                verifyingContract: await subnetAppStore.getAddress()
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
                    { name: "timestamp", type: "uint256" }
                ]
            };

            const signature = await owner.signTypedData(domain, types, usageData);

            await subnetAppStore.reportUsage(
                usageData.appId,
                usageData.providerId,
                usageData.peerId,
                usageData.usedCpu,
                usageData.usedGpu,
                usageData.usedMemory,
                usageData.usedStorage,
                usageData.usedUploadBytes,
                usageData.usedDownloadBytes,
                usageData.duration,
                usageData.timestamp,
                signature
            );

            // Jail the provider
            await subnetProvider.connect(verifier).jailProvider(providerId);

            await expect(
                subnetAppStore.claimReward(providerId, appId)
            ).to.be.revertedWith("Provider is jailed");
        });
    });

    describe("Verifier Reward", function () {
        beforeEach(async function () {
            await createApp();
            await subnetProvider.registerProvider("provider1", "metadata1", owner.address, "https://provider1.com");
            await subnetProvider.registerPeerNode(1, "peer123", "metadata");
        });

        it("should reward verifier correctly", async function () {
            const providerId = 1;
            const appId = 1;
            const usageData = {
                providerId: providerId,
                appId: appId,
                peerId: "peer123",
                usedCpu: 10,
                usedGpu: 5,
                usedMemory: 10 * 1e9,
                usedStorage: 20 * 1e9,
                usedUploadBytes: 1e9, // 1 GB
                usedDownloadBytes: 2e9, // 2 GB
                duration: 3600, // 1 hour
                timestamp: Math.floor(Date.now() / 1000)
            };

            const domain = {
                name: "SubnetAppStore",
                version: "1",
                chainId: (await ethers.provider.getNetwork()).chainId,
                verifyingContract: await subnetAppStore.getAddress()
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
                    { name: "timestamp", type: "uint256" }
                ]
            };

            const signature = await operator.signTypedData(domain, types, usageData);
            await subnetAppStore.setVerifierRewardRate(100); // 10%

            await subnetAppStore.reportUsage(
                usageData.appId,
                usageData.providerId,
                usageData.peerId,
                usageData.usedCpu,
                usageData.usedGpu,
                usageData.usedMemory,
                usageData.usedStorage,
                usageData.usedUploadBytes,
                usageData.usedDownloadBytes,
                usageData.duration,
                usageData.timestamp,
                signature
            );


            await subnetAppStore.claimReward(providerId, appId);

            await ethers.provider.send("evm_increaseTime", [30 * 24 * 60 * 60]);
            await ethers.provider.send("evm_mine", []);

            await subnetAppStore.claimReward(providerId, appId);


            const verifierRewardRate = await subnetAppStore.verifierRewardRate();
            const totalReward = 1080130000000000000n;
            const feeRate = await subnetAppStore.feeRate();
            const protocolFee = BigInt(totalReward) * feeRate / 1000n;

            const verifierReward = (BigInt(totalReward) - protocolFee) * verifierRewardRate / 1000n;

            expect(await rewardToken.balanceOf(operator.address)).to.equal(verifierReward);
        });
    });

    describe("Refund Provider", function () {
        beforeEach(async function () {
            await createApp();
            await subnetProvider.registerProvider("provider1", "metadata1", owner.address, "https://provider1.com");
            await subnetProvider.registerPeerNode(1, "peer123", "metadata");
        });

        it("should allow refunding the provider", async function () {
            const providerId = 1;
            const appId = 1;

            const usageData = {
                providerId: providerId,
                appId: appId,
                peerId: "peer123",
                usedCpu: 10,
                usedGpu: 5,
                usedMemory: 10 * 1e9,
                usedStorage: 20 * 1e9,
                usedUploadBytes: 1e9, // 1 GB
                usedDownloadBytes: 2e9, // 2 GB
                duration: 3600, // 1 hour
                timestamp: Math.floor(Date.now() / 1000)
            };

            const domain = {
                name: "SubnetAppStore",
                version: "1",
                chainId: (await ethers.provider.getNetwork()).chainId,
                verifyingContract: await subnetAppStore.getAddress()
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
                    { name: "timestamp", type: "uint256" }
                ]
            };

            const signature = await owner.signTypedData(domain, types, usageData);

            await subnetAppStore.reportUsage(
                usageData.appId,
                usageData.providerId,
                usageData.peerId,
                usageData.usedCpu,
                usageData.usedGpu,
                usageData.usedMemory,
                usageData.usedStorage,
                usageData.usedUploadBytes,
                usageData.usedDownloadBytes,
                usageData.duration,
                usageData.timestamp,
                signature
            );

            let app = await subnetAppStore.getApp(usageData.appId);
            const initialProviderBalance = app.spentBudget;

            await subnetProvider.connect(verifier).jailProvider(providerId);

            await expect(
                subnetAppStore.refundProvider(appId, providerId)
            )
                .to.emit(subnetAppStore, "ProviderRefunded")
                .withArgs(appId, providerId, 1080130000000000000n);

            app = await subnetAppStore.getApp(usageData.appId);    
            const finalProviderBalance = app.spentBudget;

            const expectedRefund = 1080130000000000000n;

            expect(finalProviderBalance + initialProviderBalance).to.equal(expectedRefund);
        });


        it("should revert if there are no rewards to refund", async function () {
            const providerId = 1;
            const appId = 1;

            await subnetProvider.connect(verifier).jailProvider(providerId);

            await expect(
                subnetAppStore.refundProvider(appId, providerId)
            ).to.be.revertedWith("No rewards");
        });

        it("should revert if called by non-owner", async function () {
            const providerId = 1;
            const appId = 1;

            const usageData = {
                providerId: providerId,
                appId: appId,
                peerId: "peer123",
                usedCpu: 10,
                usedGpu: 5,
                usedMemory: 10 * 1e9,
                usedStorage: 20 * 1e9,
                usedUploadBytes: 1e9, // 1 GB
                usedDownloadBytes: 2e9, // 2 GB
                duration: 3600, // 1 hour
                timestamp: Math.floor(Date.now() / 1000)
            };

            const domain = {
                name: "SubnetAppStore",
                version: "1",
                chainId: (await ethers.provider.getNetwork()).chainId,
                verifyingContract: await subnetAppStore.getAddress()
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
                    { name: "timestamp", type: "uint256" }
                ]
            };

            const signature = await owner.signTypedData(domain, types, usageData);

            await subnetAppStore.reportUsage(
                usageData.appId,
                usageData.providerId,
                usageData.peerId,
                usageData.usedCpu,
                usageData.usedGpu,
                usageData.usedMemory,
                usageData.usedStorage,
                usageData.usedUploadBytes,
                usageData.usedDownloadBytes,
                usageData.duration,
                usageData.timestamp,
                signature
            );

            await subnetProvider.connect(verifier).jailProvider(providerId);

            await expect(
                subnetAppStore.connect(addr1).refundProvider(appId, providerId)
            ).to.be.revertedWith("Only the owner can request a refund");
        });
    });
});

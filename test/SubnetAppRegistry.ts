import { ethers, upgrades } from 'hardhat'
import { SubnetAppRegistry, SubnetRegistry } from '../typechain-types';
import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers';
import { expect } from 'chai';

describe("SubnetAppRegistry", function () {
    let subnetAppRegistry: SubnetAppRegistry,
        subnetRegistry: SubnetRegistry,
        owner: HardhatEthersSigner, treasury: HardhatEthersSigner,
        addr1: HardhatEthersSigner;

    beforeEach(async function () {
        [owner, treasury, addr1] = await ethers.getSigners();

        // Deploy TestNFT contract
        const TestNFTFactory = await ethers.getContractFactory("TestNFT");
        const testNFT = await TestNFTFactory.deploy();

        await testNFT.mint(owner, 1)

        // Mock SubnetRegistry Contract (Minimal interface)
        const _SubnetRegistry = await ethers.getContractFactory("SubnetRegistry");
        subnetRegistry = await _SubnetRegistry.deploy(
            owner.address,
            await testNFT.getAddress(),
            ethers.parseEther("0.01") // Reward per second
        );

        await testNFT.approve(await subnetRegistry.getAddress(), 1)
        await subnetRegistry.registerSubnet(1, "0x", "")


        // Deploy SubnetAppRegistry Contract
        const _SubnetAppRegistry = await ethers.getContractFactory("SubnetAppRegistry");
        const _subnetAppRegistry = await _SubnetAppRegistry.deploy(
            await subnetRegistry.getAddress(),
            owner.address,
            treasury.address,
            50 // Fee rate: 5%
        )

        subnetAppRegistry = await ethers.getContractAt('SubnetAppRegistry', await _subnetAppRegistry.getAddress())
    });

    it("should allow creating a new application", async function () {
        const appName = "TestApp";
        const appSymbol = "TAPP";
        const appPeerId = "peer123";
        const appBudget = ethers.parseEther("10"); // 10 ETH
        const maxNodes = 10;

        // Create an application
        await subnetAppRegistry.createApp(
            appName,
            appSymbol,
            appPeerId,
            appBudget,
            maxNodes,
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
            0, // PaymentMethod.DURATION
            { value: appBudget }
        );

        // Check the created application
        const app = await subnetAppRegistry.apps(1);
        expect(app.name).to.equal(appName);
        expect(app.symbol).to.equal(appSymbol);
        expect(app.peerId).to.equal(appPeerId);
        expect(app.budget).to.equal(appBudget);
        expect(app.maxNodes).to.equal(maxNodes);
        expect(app.owner).to.equal(owner.address);
    });

    it("should not allow creating an application with duplicate symbols", async function () {
        const appSymbol = "DUPL";

        // Create the first application
        await subnetAppRegistry.createApp(
            "App1",
            appSymbol,
            "peer1",
            ethers.parseEther("5"),
            5,
            2, 1, 4, 10, 20, 1, 1, 1, 1, 1, 0,
            { value: ethers.parseEther("5") }
        );

        // Attempt to create another application with the same symbol
        await expect(
            subnetAppRegistry.createApp(
                "App2",
                appSymbol,
                "peer2",
                ethers.parseEther("5"),
                5,
                2, 1, 4, 10, 20, 1, 1, 1, 1, 1, 0,
                { value: ethers.parseEther("5") }
            )
        ).to.be.revertedWith("Symbol already exists");
    });

    it("should emit an AppCreated event upon creating an application", async function () {
        const appName = "EmitApp";
        const appSymbol = "EAPP";
        const appBudget = ethers.parseEther("5");

        // Expect the event
        await expect(
            subnetAppRegistry.createApp(
                appName,
                appSymbol,
                "peerEmit",
                appBudget,
                5,
                2, 1, 4, 10, 20, 1, 1, 1, 1, 1, 0,
                { value: appBudget }
            )
        )
            .to.emit(subnetAppRegistry, "AppCreated")
            .withArgs(1, appName, appSymbol, owner.address, appBudget);
    });

    it("should allow updating the treasury address", async function () {
        const newTreasury = addr1.address;

        // Update the treasury
        await subnetAppRegistry.connect(owner).setTreasury(newTreasury);

        // Check if updated
        expect(await subnetAppRegistry.treasury()).to.equal(newTreasury);
    });

    it("should not allow non-owners to update the treasury", async function () {
        const newTreasury = addr1.address;

        // Attempt to update the treasury from a non-owner
        await expect(
            subnetAppRegistry.connect(addr1).setTreasury(newTreasury)
        ).to.be.revertedWithCustomError(subnetAppRegistry, "OwnableUnauthorizedAccount");
    });

    it("should allow updating the fee rate", async function () {
        const newFeeRate = 100; // 10%

        // Update the fee rate
        await subnetAppRegistry.connect(owner).setFeeRate(newFeeRate);

        // Check if updated
        expect(await subnetAppRegistry.feeRate()).to.equal(newFeeRate);
    });

    it("should not allow fee rate greater than 1000", async function () {
        const invalidFeeRate = 1100; // Invalid fee rate (110%)

        // Attempt to set an invalid fee rate
        await expect(
            subnetAppRegistry.connect(owner).setFeeRate(invalidFeeRate)
        ).to.be.revertedWith("Fee rate must be <= 1000 (100%)");
    });

    it("should register a node to an application successfully", async function () {
        // Mock application creation
        const appBudget = ethers.parseEther("10");
        await subnetAppRegistry.createApp(
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
            0, // PaymentMethod.DURATION
            { value: appBudget }
        );

        // Mock subnet registration in SubnetRegistry
        const subnetId = 1;

        // Register the node to the app
        await subnetAppRegistry.registerNode(subnetId, 1);

        // Verify the node is registered
        const registeredApp = await subnetAppRegistry.getAppNode(1, subnetId);
        expect(registeredApp.isRegistered).to.equal(true);

        // Verify the app's node count
        const app = await subnetAppRegistry.apps(1);
        expect(app.nodeCount).to.equal(1);
    });

    it("should revert if the app ID is invalid", async function () {
        await expect(subnetAppRegistry.registerNode(1, 999)).to.be.revertedWith("Invalid App ID");
    });

    it("should revert if the app has reached the maximum node limit", async function () {
        const appBudget = ethers.parseEther("10");
        await subnetAppRegistry.createApp(
            "TestApp",
            "TAPP",
            "peer123",
            appBudget,
            1, // maxNodes
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
            0, // PaymentMethod.DURATION
            { value: appBudget }
        );

        const subnetId1 = 1;
        const subnetId2 = 2;

        // Register first node successfully
        await subnetAppRegistry.registerNode(subnetId1, 1);

        // Attempt to register a second node, which exceeds the limit
        await expect(subnetAppRegistry.registerNode(subnetId2, 1)).to.be.revertedWith(
            "App has reached maximum node limit"
        );
    });

    it("should revert if the subnet is inactive", async function () {
        const appBudget = ethers.parseEther("10");
        await subnetAppRegistry.createApp(
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
            0, // PaymentMethod.DURATION
            { value: appBudget }
        );

        const subnetId = 1;

        await subnetRegistry.deregisterSubnet(subnetId);

        // Subnet is not active
        await expect(subnetAppRegistry.registerNode(subnetId, 1)).to.be.revertedWith(
            "Subnet is inactive"
        );
    });

    describe("ClaimReward", () => {
        let owner: HardhatEthersSigner, treasury: HardhatEthersSigner;
        let feeRate = 50n
        beforeEach(async () => {
            const appBudget = ethers.parseEther("100"); // 100 ether budget
            [owner, treasury] = await ethers.getSigners();
            // Mock application creation
            await subnetAppRegistry.createApp(
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
                0, // PaymentMethod.DURATION
                { value: appBudget }
            );

            await subnetAppRegistry.registerNode(1, 1)
        })

        it("should allow a node to claim a reward successfully", async function () {
            const subnetId = 1;
            const appId = 1;

            // Simulate usage data
            const usageData = {
                subnetId: subnetId,
                appId: appId,
                usedCpu: 10,
                usedGpu: 5,
                usedMemory: 10,
                usedStorage: 20,
                usedUploadBytes: 1e9, // 1 GB
                usedDownloadBytes: 2e9, // 2 GB
                duration: 3600 // 1 hour
            };

            const bandwidth = (usageData.usedDownloadBytes + usageData.usedUploadBytes)/1e9
            const reward = BigInt((usageData.usedCpu + usageData.usedGpu +
                usageData.usedMemory + usageData.usedStorage +
                bandwidth) * usageData.duration);

            // Generate EIP-712 signature
            const domain = {
                name: "SubnetAppRegistry",
                version: "1",
                chainId: (await ethers.provider.getNetwork()).chainId,
                verifyingContract: await subnetAppRegistry.getAddress()
            };

            const types = {
                Usage: [
                    { name: "subnetId", type: "uint256" },
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

            // Node claims the reward
            const initialTreasuryBalance = await ethers.provider.getBalance(treasury.address);
            const initialNodeBalance = await ethers.provider.getBalance(owner.address);

            await expect(
                subnetAppRegistry.claimReward(
                    usageData.subnetId,
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
            )
                .to.emit(subnetAppRegistry, "RewardClaimed")
                .withArgs(appId, subnetId, owner.address, reward);

            // Verify balances
            const finalTreasuryBalance = await ethers.provider.getBalance(treasury.address);
            const finalNodeBalance = await ethers.provider.getBalance(owner.address);

            const expectedReward = reward; // Reward calculated based on usage
            const fee = expectedReward * feeRate / 1000n;
            const netReward = expectedReward - fee;

            expect(finalTreasuryBalance - initialTreasuryBalance).to.equal(fee);
            expect(finalNodeBalance - initialNodeBalance).to.be.closeTo(netReward, ethers.parseEther("0.001")); // Allow slight gas variation
        })
    })
});

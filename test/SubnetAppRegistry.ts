import { ethers, upgrades } from 'hardhat'
import { SubnetAppRegistry } from '../typechain-types';
import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers';
import { expect } from 'chai';

describe("SubnetAppRegistry", function () {
    let subnetAppRegistry: SubnetAppRegistry,
        owner: HardhatEthersSigner, treasury: HardhatEthersSigner,
        addr1: HardhatEthersSigner;

    beforeEach(async function () {
        [owner, treasury, addr1] = await ethers.getSigners();

        // Deploy TestNFT contract
        const TestNFTFactory = await ethers.getContractFactory("TestNFT");
        const testNFT = await TestNFTFactory.deploy();

        // Mock SubnetRegistry Contract (Minimal interface)
        const _SubnetRegistry = await ethers.getContractFactory("SubnetRegistry");
        const _subnetRegistry = await _SubnetRegistry.deploy(
            owner.address,
            await testNFT.getAddress(),
            ethers.parseEther("0.01") // Reward per second
        );


        // Deploy SubnetAppRegistry Contract
        const _SubnetAppRegistry = await ethers.getContractFactory("SubnetAppRegistry");
        const _subnetAppRegistry = await _SubnetAppRegistry.deploy(
            await _subnetRegistry.getAddress(),
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
        ).to.be.revertedWithCustomError(subnetAppRegistry,"OwnableUnauthorizedAccount");
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
});

import { ethers, ignition } from 'hardhat';
import { expect } from 'chai';
import { ERC20Mock, SubnetProvider } from '../../typechain-types';
import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers';
import SubnetProviderModule from '../../ignition/modules/SubnetProvider';

describe("SubnetProvider", function () {
    let subnetProvider: SubnetProvider;
    let owner: HardhatEthersSigner, operator: HardhatEthersSigner, addr1: HardhatEthersSigner, addr2: HardhatEthersSigner;
    let stakingToken: ERC20Mock;

    beforeEach(async function () {
        [owner, operator, addr1, addr2] = await ethers.getSigners();

        // Deploy mock ERC20 for staking
        const MockErc20 = await ethers.getContractFactory("ERC20Mock");
        stakingToken = await MockErc20.deploy("Staking Token", "ST");
        await stakingToken.mint(owner.address, ethers.parseEther("100000"));
        await stakingToken.mint(addr1.address, ethers.parseEther("100000"));

        // Deploy SubnetProvider contract
        const { proxy: subnetProviderProxy } = await ignition.deploy(SubnetProviderModule);
        subnetProvider = await ethers.getContractAt("SubnetProvider", await subnetProviderProxy.getAddress());
        await (subnetProvider.initialize as any)(owner.address, await stakingToken.getAddress());
        // Approve token spending
        await stakingToken.approve(await subnetProviderProxy.getAddress(), ethers.parseEther("100000"));
        await stakingToken.connect(addr1).approve(await subnetProviderProxy.getAddress(), ethers.parseEther("100000"));
    });

    describe("Initialization and Configuration", function() {
        it("should initialize with correct parameters", async function() {
            expect(await subnetProvider.owner()).to.equal(owner.address);
            expect(await subnetProvider.stakingToken()).to.equal(await stakingToken.getAddress());
        });

        it("should allow owner to update stake parameters", async function() {
            await subnetProvider.setStakeParameters(
                ethers.parseEther("600"), // base stake
                ethers.parseEther("120"), // cpu rate
                ethers.parseEther("1200"), // gpu rate
                ethers.parseEther("25"), // memory rate
                ethers.parseEther("3") // disk rate
            );

            expect(await subnetProvider.baseStakeAmount()).to.equal(ethers.parseEther("600"));
            expect(await subnetProvider.cpuStakeRate()).to.equal(ethers.parseEther("120"));
            expect(await subnetProvider.gpuStakeRate()).to.equal(ethers.parseEther("1200"));
            expect(await subnetProvider.memoryStakeRate()).to.equal(ethers.parseEther("25"));
            expect(await subnetProvider.diskStakeRate()).to.equal(ethers.parseEther("3"));
        });

        it("should allow owner to update lock period", async function() {
            const newLockPeriod = 4 * 7 * 24 * 60 * 60; // 4 weeks
            await subnetProvider.setLockPeriod(newLockPeriod);
            expect(await subnetProvider.lockPeriod()).to.equal(newLockPeriod);
        });

        it("should not allow non-owner to update parameters", async function() {
            await expect(
                subnetProvider.connect(addr1).setStakeParameters(
                    ethers.parseEther("600"),
                    ethers.parseEther("120"),
                    ethers.parseEther("1200"),
                    ethers.parseEther("25"),
                    ethers.parseEther("3")
                )
            ).to.be.revertedWithCustomError(subnetProvider, "OwnableUnauthorizedAccount");

            await expect(
                subnetProvider.connect(addr1).setLockPeriod(4 * 7 * 24 * 60 * 60)
            ).to.be.revertedWithCustomError(subnetProvider, "OwnableUnauthorizedAccount");
        });
    });

    describe("Provider Management", function() {
        it("should register a new provider and store specs with stake", async function() {
            const cpu = 4n, gpu = 1n, gpuMem = 8000n, memMB = 16n * 1024n, diskGB = 500n;
            const priceCpu = 1n, priceGpu = 2n, priceMem = 3n, priceDisk = 4n;

            await subnetProvider.registerProvider(
                operator.address,
                "provider-metadata",
                1, // machineType
                2, // region
                cpu,
                gpu,
                gpuMem,
                memMB,
                diskGB,
                priceCpu,
                priceGpu,
                priceMem,
                priceDisk
            );

            const provider = await subnetProvider.getProvider(owner.address);
            expect(provider.operator).to.equal(operator.address);
            expect(provider.registered).to.be.true;
            expect(provider.isActive).to.be.true;
            expect(provider.isSlashed).to.be.false;
            expect(provider.metadata).to.equal("provider-metadata");
            expect(provider.cpuCores).to.equal(cpu);
            expect(provider.gpuCores).to.equal(gpu);
            expect(provider.memoryMB).to.equal(memMB);
            expect(provider.diskGB).to.equal(diskGB);
        });

        it("should allow updating provider metadata", async function() {
            await registerDefaultProvider();
            await subnetProvider.updateProviderInfo(owner.address, "new-metadata");
            const provider = await subnetProvider.getProvider(owner.address);
            expect(provider.metadata).to.equal("new-metadata");
        });

        it("should only allow provider owner to update metadata", async function() {
            await registerDefaultProvider();
            await expect(
                subnetProvider.connect(addr1).updateProviderInfo(owner.address, "hacked-metadata")
            ).to.be.revertedWith("Only owner can update provider info");
        });

        it("should allow updating provider operator", async function() {
            await registerDefaultProvider();
            await subnetProvider.setProviderOperator(owner.address, addr1.address);
            const provider = await subnetProvider.getProvider(owner.address);
            expect(provider.operator).to.equal(addr1.address);
        });
    });

    describe("Specs Update, Staking and Withdrawal", function() {
        beforeEach(async function() {
            await registerDefaultProvider();
        });

        it("should update specs with increased stake and disallow downgrade", async function() {
            const before = await subnetProvider.getProvider(owner.address);

            // Increase resources and prices
            await subnetProvider.updateProviderSpecs(
                owner.address,
                1, // machineType
                3, // region
                8, // cpuCores
                2, // gpuCores
                16000, // gpuMemory
                32 * 1024, // memoryMB
                1000, // diskGB
                "updated-metadata",
                10, // cpuPrice
                20, // gpuPrice
                30, // memPrice
                40  // diskPrice
            );

            const after = await subnetProvider.getProvider(owner.address);
            expect(after.cpuCores).to.equal(8);
            expect(after.gpuCores).to.equal(2);
            expect(after.memoryMB).to.equal(32 * 1024);
            expect(after.diskGB).to.equal(1000);
            expect(after.totalStaked).to.be.greaterThan(before.totalStaked);

            // Downgrade should revert
            await expect(
                subnetProvider.updateProviderSpecs(
                    owner.address, 1, 3, 4, 1, 8000, 16 * 1024, 500, "meta", 1, 2, 3, 4
                )
            ).to.be.revertedWith("Cannot downgrade machine resources");
        });

        it("should deactivate and allow withdrawal after lock period", async function() {
            const before = await stakingToken.balanceOf(owner.address);
            await subnetProvider.deactivateProvider(owner.address);

            // cannot withdraw before lock
            await expect(subnetProvider.claimWithdrawal(owner.address)).to.be.revertedWith("Still locked");

            const lockPeriod = await subnetProvider.lockPeriod();
            await ethers.provider.send("evm_increaseTime", [Number(lockPeriod)]);
            await ethers.provider.send("evm_mine", []);

            await subnetProvider.claimWithdrawal(owner.address);
            const after = await stakingToken.balanceOf(owner.address);
            expect(after).to.be.gt(before);
        });
    });

    describe("Stake Calculation and Slashing", function() {
        it("should calculate required stake including monthly revenue", async function() {
            const base = await subnetProvider.baseStakeAmount();
            const cpuRate = await subnetProvider.cpuStakeRate();
            const gpuRate = await subnetProvider.gpuStakeRate();
            const memRate = await subnetProvider.memoryStakeRate();
            const diskRate = await subnetProvider.diskStakeRate();

            const cpu = 4n, gpu = 1n, memMB = 16n * 1024n, diskGB = 500n;
            const priceCpu = 1n, priceGpu = 2n, priceMem = 3n, priceDisk = 4n;

            const stake = await subnetProvider.calculateRequiredStake(
                cpu, gpu, memMB, diskGB, priceCpu, priceGpu, priceMem, priceDisk
            );

            const resourceStake = cpu * cpuRate + gpu * gpuRate + (memMB * memRate) / 1024n + diskGB * diskRate;
            const memoryGB = memMB / 1024n;
            const revenuePerSecond = cpu * priceCpu + gpu * priceGpu + memoryGB * priceMem + diskGB * priceDisk;
            const monthlyRevenue = revenuePerSecond * 30n * 24n * 60n * 60n; // 30 days
            const expected = base + resourceStake + monthlyRevenue;
            expect(stake).to.equal(expected);
        });

        it("should slash stake correctly and deactivate", async function() {
            await registerDefaultProvider();
            const before = await subnetProvider.getProvider(owner.address);
            const slashAmount = before.stakeAmount / 2n;

            await subnetProvider.slashStake(owner.address, slashAmount, "bad behavior");

            const after = await subnetProvider.getProvider(owner.address);
            expect(after.stakeAmount).to.equal(before.stakeAmount - slashAmount);
            expect(after.totalStaked).to.equal(before.totalStaked - slashAmount);
            expect(after.slashedAmount).to.equal(before.slashedAmount + slashAmount);
            expect(after.isSlashed).to.be.true;
            expect(after.isActive).to.be.false;
        });
    });

    describe("Helper Functions and Status Checks", function() {
        beforeEach(async function() {
            await registerDefaultProvider();
        });

        it("should check if provider is active", async function() {
            expect(await subnetProvider.isProviderActive(owner.address)).to.be.true;
            await subnetProvider.deactivateProvider(owner.address);
            expect(await subnetProvider.isProviderActive(owner.address)).to.be.false;
        });

        it("should validate provider requirements correctly", async function() {
            // Should pass with equal requirements
            expect(await subnetProvider.validateProviderRequirements(
                1,
                owner.address,
                4, // minCpuCores
                16 * 1024, // minMemoryMB
                500, // minDiskGB
                1 // minGpuCores
            )).to.be.true;

            // Should pass with lower requirements
            expect(await subnetProvider.validateProviderRequirements(
                1,
                owner.address,
                2, // minCpuCores
                8 * 1024, // minMemoryMB
                250, // minDiskGB
                0 // minGpuCores
            )).to.be.true;

            // Should fail with higher requirements
            expect(await subnetProvider.validateProviderRequirements(
                1,
                owner.address,
                8, // minCpuCores (too high)
                16 * 1024, // minMemoryMB
                500, // minDiskGB
                1 // minGpuCores
            )).to.be.false;
        });
    });

    // Helper to register a default provider owned by `owner`
    async function registerDefaultProvider() {
        await subnetProvider.registerProvider(
            operator.address,
            "provider-metadata",
            1,
            2,
            4,
            1,
            8000,
            16 * 1024,
            500,
            1,
            2,
            3,
            4
        );
    }
});

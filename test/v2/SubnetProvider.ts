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

        it("should allow owner to update stake configuration", async function() {
            const newRatioBps = 15_000;
            const newRevenueDays = 45;
            await (subnetProvider as any).setStakeConfiguration(newRatioBps, newRevenueDays);

            expect(await (subnetProvider as any).stakeRevenueRatioBps()).to.equal(newRatioBps);
            expect(await (subnetProvider as any).stakeRevenueDays()).to.equal(newRevenueDays);
        });

        it("should allow owner to update lock period", async function() {
            const newLockPeriod = 4 * 7 * 24 * 60 * 60; // 4 weeks
            await subnetProvider.setLockPeriod(newLockPeriod);
            expect(await subnetProvider.lockPeriod()).to.equal(newLockPeriod);
        });

        it("should not allow non-owner to update parameters", async function() {
            await expect(
                (subnetProvider.connect(addr1) as any).setStakeConfiguration(12_000, 40)
            ).to.be.revertedWithCustomError(subnetProvider, "OwnableUnauthorizedAccount");

            await expect(
                subnetProvider.connect(addr1).setLockPeriod(4 * 7 * 24 * 60 * 60)
            ).to.be.revertedWithCustomError(subnetProvider, "OwnableUnauthorizedAccount");
        });
    });

    describe("Provider Management", function() {
        it("should register a new provider and store specs with stake", async function() {
            const cpu = 4n, gpu = 1n, memMB = 16n * 1024n, diskGB = 500n;
            const priceCpu = 1n, priceGpu = 2n, priceMem = 3n, priceDisk = 4n;

            await (subnetProvider as any).registerProvider(
                operator.address,
                "provider-metadata",
                1, // machineType
                2, // region
                cpu,
                gpu,
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
            await (subnetProvider as any).updateProviderSpecs(
                owner.address,
                1, // machineType (immutable)
                2, // region (immutable)
                8, // cpuCores
                2, // gpuCores
                32 * 1024, // memoryMB
                1000 // diskGB
            );

            const after = await subnetProvider.getProvider(owner.address);
            expect(after.cpuCores).to.equal(8);
            expect(after.gpuCores).to.equal(2);
            expect(after.memoryMB).to.equal(32 * 1024);
            expect(after.diskGB).to.equal(1000);
            expect(after.totalStaked).to.be.greaterThan(before.totalStaked);
            expect(after.metadata).to.equal(before.metadata);
            expect(after.machineType).to.equal(before.machineType);
            expect(after.region).to.equal(before.region);

            // Downgrade should revert
            await expect(
                (subnetProvider as any).updateProviderSpecs(
                    owner.address, 1, 2, 4, 1, 16 * 1024, 500
                )
            ).to.be.revertedWith("Cannot decrease mCPU");
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
            const ratioBps = await (subnetProvider as any).stakeRevenueRatioBps();
            const revenueDays = await (subnetProvider as any).stakeRevenueDays();

            const cpu = 4n, gpu = 1n, memMB = 16n * 1024n, diskGB = 500n;
            const priceCpu = 1n, priceGpu = 2n, priceMem = 3n, priceDisk = 4n;

            const stake = await subnetProvider.calculateRequiredStake(
                cpu, gpu, memMB, diskGB, priceCpu, priceGpu, priceMem, priceDisk
            );

            // Calculate revenue per second using new precision-aware logic
            // CPU: (mCPU * price per CPU) / 1000
            // Memory: (MB * price per GB) / 1024
            const cpuRevenue = (cpu * priceCpu) / 1000n;
            const memoryRevenue = (memMB * priceMem) / 1024n;
            const revenuePerSecond = cpuRevenue + (gpu * priceGpu) + memoryRevenue + (diskGB * priceDisk);
            const revenueSeconds = BigInt(revenueDays) * 24n * 60n * 60n;
            const revenueStake = revenuePerSecond * revenueSeconds;
            const expected = (revenueStake * ratioBps) / 10_000n;
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

    describe("Resource Price Management", function() {
        beforeEach(async function() {
            await registerDefaultProvider();
        });

        it("should update resource prices without additional stake if required stake doesn't increase", async function() {
            const providerBefore = await subnetProvider.getProvider(owner.address);
            const stakeBefore = providerBefore.stakeAmount;
            const balanceBefore = await stakingToken.balanceOf(owner.address);

            // Set lower prices (should not require additional stake)
            await (subnetProvider as any).setResourcePrice(
                owner.address,
                1, // cpuPricePerSecond (same)
                2, // gpuPricePerSecond (same)
                2, // memoryPricePerSecond (lower: 3 -> 2)
                3, // diskPricePerSecond (lower: 4 -> 3)
            );

            const providerAfter = await subnetProvider.getProvider(owner.address);
            const balanceAfter = await stakingToken.balanceOf(owner.address);

            // Prices should be updated
            expect(providerAfter.cpuPricePerSecond).to.equal(1);
            expect(providerAfter.gpuPricePerSecond).to.equal(2);
            expect(providerAfter.memoryPricePerSecond).to.equal(2);
            expect(providerAfter.diskPricePerSecond).to.equal(3);

            // Stake should remain the same (or could be less, but we don't refund)
            expect(providerAfter.stakeAmount).to.equal(stakeBefore);
            // Balance should not change (no additional stake required)
            expect(balanceAfter).to.equal(balanceBefore);
        });

        it("should require additional stake when prices increase", async function() {
            const providerBefore = await subnetProvider.getProvider(owner.address);
            const stakeBefore = providerBefore.stakeAmount;
            const balanceBefore = await stakingToken.balanceOf(owner.address);

            // Calculate expected new stake with higher prices
            const newCpuPrice = 2n; // doubled
            const newGpuPrice = 4n; // doubled
            const newMemPrice = 6n; // doubled
            const newDiskPrice = 8n; // doubled

            const expectedNewStake = await subnetProvider.calculateRequiredStake(
                providerBefore.cpuCores,
                providerBefore.gpuCores,
                providerBefore.memoryMB,
                providerBefore.diskGB,
                newCpuPrice,
                newGpuPrice,
                newMemPrice,
                newDiskPrice
            );

            // Set higher prices (should require additional stake)
            await (subnetProvider as any).setResourcePrice(
                owner.address,
                newCpuPrice,
                newGpuPrice,
                newMemPrice,
                newDiskPrice
            );

            const providerAfter = await subnetProvider.getProvider(owner.address);
            const balanceAfter = await stakingToken.balanceOf(owner.address);
            const additionalStake = expectedNewStake - stakeBefore;

            // Prices should be updated
            expect(providerAfter.cpuPricePerSecond).to.equal(newCpuPrice);
            expect(providerAfter.gpuPricePerSecond).to.equal(newGpuPrice);
            expect(providerAfter.memoryPricePerSecond).to.equal(newMemPrice);
            expect(providerAfter.diskPricePerSecond).to.equal(newDiskPrice);

            // Stake should be increased
            expect(providerAfter.stakeAmount).to.equal(expectedNewStake);
            expect(providerAfter.totalStaked).to.equal(providerBefore.totalStaked + additionalStake);

            // Balance should decrease by additional stake amount
            expect(balanceBefore - balanceAfter).to.equal(additionalStake);
        });

        it("should reject price update if provider is not active", async function() {
            await subnetProvider.deactivateProvider(owner.address);

            await expect(
                (subnetProvider as any).setResourcePrice(
                    owner.address,
                    2, 4, 6, 8
                )
            ).to.be.revertedWith("Provider not active");
        });

        it("should reject price update if provider is not registered", async function() {
            await expect(
                (subnetProvider as any).setResourcePrice(
                    addr2.address,
                    2, 4, 6, 8
                )
            ).to.be.revertedWith("Provider not registered");
        });

        it("should only allow provider owner to update prices", async function() {
            // Non-owner should not be able to update
            await expect(
                (subnetProvider.connect(addr1) as any).setResourcePrice(
                    owner.address,
                    2, 4, 6, 8
                )
            ).to.be.revertedWith("Only owner can update prices");

            // Operator should not be able to update
            await expect(
                (subnetProvider.connect(operator) as any).setResourcePrice(
                    owner.address,
                    2, 4, 6, 8
                )
            ).to.be.revertedWith("Only owner can update prices");

            // Owner should be able to update
            await (subnetProvider as any).setResourcePrice(
                owner.address,
                2, 4, 6, 8
            );

            const provider = await subnetProvider.getProvider(owner.address);
            expect(provider.cpuPricePerSecond).to.equal(2);
        });

        it("should handle partial price increases correctly", async function() {
            const providerBefore = await subnetProvider.getProvider(owner.address);
            const stakeBefore = providerBefore.stakeAmount;

            // Calculate expected stake with partial price increase
            const newCpuPrice = 10n; // Increase significantly to ensure stake increases
            const expectedNewStake = await subnetProvider.calculateRequiredStake(
                providerBefore.cpuCores,
                providerBefore.gpuCores,
                providerBefore.memoryMB,
                providerBefore.diskGB,
                newCpuPrice, // cpuPricePerSecond (increased)
                providerBefore.gpuPricePerSecond, // same
                providerBefore.memoryPricePerSecond, // same
                providerBefore.diskPricePerSecond // same
            );

            // Only increase CPU price
            await (subnetProvider as any).setResourcePrice(
                owner.address,
                newCpuPrice, // cpuPricePerSecond (increased)
                providerBefore.gpuPricePerSecond, // same
                providerBefore.memoryPricePerSecond, // same
                providerBefore.diskPricePerSecond // same
            );

            const providerAfter = await subnetProvider.getProvider(owner.address);

            // Prices should be updated
            expect(providerAfter.cpuPricePerSecond).to.equal(newCpuPrice);
            expect(providerAfter.gpuPricePerSecond).to.equal(providerBefore.gpuPricePerSecond);
            expect(providerAfter.memoryPricePerSecond).to.equal(providerBefore.memoryPricePerSecond);
            expect(providerAfter.diskPricePerSecond).to.equal(providerBefore.diskPricePerSecond);

            // Stake should increase if expected stake is greater
            if (expectedNewStake > stakeBefore) {
                expect(providerAfter.stakeAmount).to.be.gt(stakeBefore);
                expect(providerAfter.stakeAmount).to.equal(expectedNewStake);
            } else {
                // If stake doesn't increase (due to precision), it should at least remain the same
                expect(providerAfter.stakeAmount).to.be.gte(stakeBefore);
            }
        });

        it("should update prices multiple times and accumulate stake correctly", async function() {
            const provider1 = await subnetProvider.getProvider(owner.address);
            const stake1 = provider1.stakeAmount;

            // First price increase
            await (subnetProvider as any).setResourcePrice(
                owner.address,
                2, 4, 6, 8
            );

            const provider2 = await subnetProvider.getProvider(owner.address);
            const stake2 = provider2.stakeAmount;
            expect(stake2).to.be.gt(stake1);

            // Second price increase
            await (subnetProvider as any).setResourcePrice(
                owner.address,
                3, 6, 9, 12
            );

            const provider3 = await subnetProvider.getProvider(owner.address);
            const stake3 = provider3.stakeAmount;
            expect(stake3).to.be.gt(stake2);

            // Verify final prices
            expect(provider3.cpuPricePerSecond).to.equal(3);
            expect(provider3.gpuPricePerSecond).to.equal(6);
            expect(provider3.memoryPricePerSecond).to.equal(9);
            expect(provider3.diskPricePerSecond).to.equal(12);
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
        await (subnetProvider as any).registerProvider(
            operator.address,
            "provider-metadata",
            1,
            2,
            4,
            1,
            16 * 1024,
            500,
            1,
            2,
            3,
            4
        );
    }
});

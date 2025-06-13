import { ethers, ignition } from 'hardhat';
import { expect } from 'chai';
import { ERC20Mock, SubnetProvider } from '../typechain-types';
import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers';
import SubnetProviderModule from '../ignition/modules/SubnetProvider';

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
        await subnetProvider.initialize(owner.address, await stakingToken.getAddress(), "Provider NFT", "PNFT");
        // Approve token spending
        await stakingToken.approve(await subnetProviderProxy.getAddress(), ethers.parseEther("100000"));
        await stakingToken.connect(addr1).approve(await subnetProviderProxy.getAddress(), ethers.parseEther("100000"));
    });

    describe("Initialization and Configuration", function() {
        it("should initialize with correct parameters", async function() {
            expect(await subnetProvider.owner()).to.equal(owner.address);
            expect(await subnetProvider.stakingToken()).to.equal(await stakingToken.getAddress());
            expect(await subnetProvider.name()).to.equal("Provider NFT");
            expect(await subnetProvider.symbol()).to.equal("PNFT");
        });

        it("should allow owner to update stake parameters", async function() {
            await subnetProvider.setStakeParameters(
                ethers.parseEther("600"), // base stake
                ethers.parseEther("120"), // cpu rate
                ethers.parseEther("1200"), // gpu rate
                ethers.parseEther("25"), // memory rate
                ethers.parseEther("3"), // disk rate
                ethers.parseEther("12"), // upload rate
                ethers.parseEther("6")  // download rate
            );

            expect(await subnetProvider.baseStakeAmount()).to.equal(ethers.parseEther("600"));
            expect(await subnetProvider.cpuStakeRate()).to.equal(ethers.parseEther("120"));
            expect(await subnetProvider.gpuStakeRate()).to.equal(ethers.parseEther("1200"));
            expect(await subnetProvider.memoryStakeRate()).to.equal(ethers.parseEther("25"));
            expect(await subnetProvider.diskStakeRate()).to.equal(ethers.parseEther("3"));
            expect(await subnetProvider.uploadSpeedStakeRate()).to.equal(ethers.parseEther("12"));
            expect(await subnetProvider.downloadSpeedStakeRate()).to.equal(ethers.parseEther("6"));
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
                    ethers.parseEther("3"),
                    ethers.parseEther("12"),
                    ethers.parseEther("6")
                )
            ).to.be.revertedWithCustomError(subnetProvider, "OwnableUnauthorizedAccount");

            await expect(
                subnetProvider.connect(addr1).setLockPeriod(4 * 7 * 24 * 60 * 60)
            ).to.be.revertedWithCustomError(subnetProvider, "OwnableUnauthorizedAccount");
        });
    });

    describe("Provider Management", function() {
        it("should register a new provider and mint NFT", async function() {
            const tx = await subnetProvider.registerProvider(operator.address, "provider-metadata");
            const receipt = await tx.wait();
            
            // Find the provider ID from the transaction events
            const providerId = await getProviderIdFromReceipt(receipt!);
            expect(providerId).to.not.be.undefined;
            expect(await subnetProvider.ownerOf(providerId)).to.equal(owner.address);
            
            const provider = await subnetProvider.getProvider(providerId);
            expect(provider.operator).to.equal(operator.address);
            expect(provider.registered).to.be.true;
            expect(provider.isActive).to.be.true;
            expect(provider.isSlashed).to.be.false;
            expect(provider.metadata).to.equal("provider-metadata");
        });

        it("should allow updating provider metadata", async function() {
            const tx = await subnetProvider.registerProvider(operator.address, "old-metadata");
            const receipt = await tx.wait();
            const providerId = await getProviderIdFromReceipt(receipt!);
            
            await subnetProvider.updateProviderInfo(providerId, "new-metadata");
            
            const provider = await subnetProvider.getProvider(providerId);
            expect(provider.metadata).to.equal("new-metadata");
        });

        it("should only allow provider owner to update metadata", async function() {
            const tx = await subnetProvider.registerProvider(operator.address, "metadata");
            const receipt = await tx.wait();
            const providerId = await getProviderIdFromReceipt(receipt!);
            
            await expect(
                subnetProvider.connect(addr1).updateProviderInfo(providerId, "hacked-metadata")
            ).to.be.revertedWith("Only token owner can update provider info");
        });

        it("should allow updating provider operator", async function() {
            const tx = await subnetProvider.registerProvider(operator.address, "metadata");
            const receipt = await tx.wait();
            const providerId = await getProviderIdFromReceipt(receipt!);
            
            await subnetProvider.setProviderOperator(providerId, addr1.address);
            
            const provider = await subnetProvider.getProvider(providerId);
            expect(provider.operator).to.equal(addr1.address);
        });
    });

    describe("Machine Management", function() {
        let providerId: bigint;
        
        beforeEach(async function() {
            // Register a provider
            const tx = await subnetProvider.registerProvider(operator.address, "provider-metadata");
            const receipt = await tx.wait();
            providerId = await getProviderIdFromReceipt(receipt!);
        });

        it("should add a new machine", async function() {
            const tx = await subnetProvider.addMachine(
                providerId,
                1, // machineType
                2, // region
                4, // cpuCores
                3000, // cpuSpeed
                1, // gpuCores
                8000, // gpuMemory
                16 * 1024, // memoryMB (16GB)
                500, // diskGB
                123456789, // publicIp
                987654321, // overlayIp
                100, // uploadSpeed
                1000, // downloadSpeed
                "machine-metadata"
            );
            
            const receipt = await tx.wait();
            
            // Check machine was added correctly
            const provider = await subnetProvider.getProvider(providerId);
            expect(provider.machineCount).to.equal(1);
            
            // First machine has ID 0
            const machines = await subnetProvider.getMachines(providerId);
            expect(machines[0].active).to.be.true;
            expect(machines[0].machineType).to.equal(1);
            expect(machines[0].region).to.equal(2);
            expect(machines[0].cpuCores).to.equal(4);
            expect(machines[0].gpuCores).to.equal(1);
            expect(machines[0].memoryMB).to.equal(16 * 1024);
            expect(machines[0].diskGB).to.equal(500);
            expect(machines[0].uploadSpeed).to.equal(100);
            expect(machines[0].downloadSpeed).to.equal(1000);
            expect(machines[0].metadata).to.equal("machine-metadata");
            
            // Check stake was transferred
            const expectedStake = await subnetProvider.calculateRequiredStake(4, 1, 16 * 1024, 500, 100, 1000);
            expect(machines[0].stakeAmount).to.equal(expectedStake);
            
            // Check provider's total staked amount was updated
            expect(provider.totalStaked).to.equal(expectedStake);
        });

        it("should only allow provider owner to add machines", async function() {
            await expect(
                subnetProvider.connect(addr1).addMachine(
                    providerId,
                    1, // machineType
                    2, // region
                    4, // cpuCores
                    3000, // cpuSpeed
                    1, // gpuCores
                    8000, // gpuMemory
                    16 * 1024, // memoryMB
                    500, // diskGB
                    123456789, // publicIp
                    987654321, // overlayIp
                    100, // uploadSpeed
                    1000, // downloadSpeed
                    "machine-metadata"
                )
            ).to.be.revertedWith("Only token owner can add machine");
        });

        it("should update a machine with increased resources", async function() {
            // Add a machine first
            await subnetProvider.addMachine(
                providerId,
                1, // machineType
                2, // region
                4, // cpuCores
                3000, // cpuSpeed
                1, // gpuCores
                8000, // gpuMemory
                16 * 1024, // memoryMB
                500, // diskGB
                123456789, // publicIp
                987654321, // overlayIp
                100, // uploadSpeed
                1000, // downloadSpeed
                "machine-metadata"
            );
            
            // Get initial stake
            const initialMachine = (await subnetProvider.getMachines(providerId))[0];
            const initialStake = initialMachine.stakeAmount;
            
            // Update machine with more resources
            await subnetProvider.updateMachine(
                providerId,
                0, // machineId
                8, // cpuCores (increased)
                3500, // cpuSpeed
                2, // gpuCores (increased)
                16000, // gpuMemory
                32 * 1024, // memoryMB (increased)
                1000, // diskGB (increased)
                123456789, // publicIp
                987654321, // overlayIp
                200, // uploadSpeed (increased)
                2000, // downloadSpeed (increased)
                "updated-metadata"
            );
            
            // Check machine was updated correctly
            const updatedMachines = await subnetProvider.getMachines(providerId);
            const updatedMachine = updatedMachines[0];
            expect(updatedMachine.cpuCores).to.equal(8);
            expect(updatedMachine.gpuCores).to.equal(2);
            expect(updatedMachine.memoryMB).to.equal(32 * 1024);
            expect(updatedMachine.diskGB).to.equal(1000);
            expect(updatedMachine.uploadSpeed).to.equal(200);
            expect(updatedMachine.downloadSpeed).to.equal(2000);
            expect(updatedMachine.metadata).to.equal("updated-metadata");
            
            // Check additional stake was calculated and transferred
            expect(updatedMachine.stakeAmount).to.be.gt(initialStake);
        });
    });

    describe("Staking, Withdrawal, and Slashing", function() {
        let providerId: bigint;
        let machineId = 0n;
        let stakeAmount: bigint;
        
        beforeEach(async function() {
            // Register a provider
            const txProvider = await subnetProvider.registerProvider(operator.address, "provider-metadata");
            const receiptProvider = await txProvider.wait();
            providerId = await getProviderIdFromReceipt(receiptProvider!);
            
            // Add a machine
            await subnetProvider.addMachine(
                providerId,
                1, // machineType
                2, // region
                4, // cpuCores
                3000, // cpuSpeed
                1, // gpuCores
                8000, // gpuMemory
                16 * 1024, // memoryMB
                500, // diskGB
                123456789, // publicIp
                987654321, // overlayIp
                100, // uploadSpeed
                1000, // downloadSpeed
                "machine-metadata"
            );
            
            // Get stake amount
            const machine = (await subnetProvider.getMachines(providerId))[0];
            stakeAmount = machine.stakeAmount;
        });
        
        it("should calculate correct stake based on resources", async function() {
            // Calculate with default rates
            const stake = await subnetProvider.calculateRequiredStake(
                4, // cpuCores
                1, // gpuCores
                16 * 1024, // memoryMB
                500, // diskGB
                100, // uploadSpeed
                1000 // downloadSpeed
            );
            
            // Manually calculate expected stake
            const baseStake = await subnetProvider.baseStakeAmount();
            const cpuStake = 4n * await subnetProvider.cpuStakeRate();
            const gpuStake = 1n * await subnetProvider.gpuStakeRate();
            const memoryStake = BigInt(16 * 1024) * await subnetProvider.memoryStakeRate() / 1024n;
            const diskStake = 500n * await subnetProvider.diskStakeRate();
            const uploadStake = 100n * await subnetProvider.uploadSpeedStakeRate();
            const downloadStake = 1000n * await subnetProvider.downloadSpeedStakeRate();
            
            const expectedStake = baseStake + cpuStake + gpuStake + memoryStake + diskStake + uploadStake + downloadStake;
            
            expect(stake).to.equal(expectedStake);
        });

        it("should slash stake correctly", async function() {
            const slashAmount = stakeAmount / 2n; // Slash half the stake
            
            await subnetProvider.slashStake(providerId, machineId, slashAmount, "bad behavior");
            
            // Check machine stake was reduced
            const machine = (await subnetProvider.getMachines(providerId))[0];
            expect(machine.stakeAmount).to.equal(stakeAmount - slashAmount);
            
            // Check provider totals were updated
            const provider = await subnetProvider.getProvider(providerId);
            expect(provider.totalStaked).to.equal(stakeAmount - slashAmount);
            expect(provider.slashedAmount).to.equal(slashAmount);
            expect(provider.isSlashed).to.be.true;
            expect(provider.isActive).to.be.false; // Provider deactivated
            
            // Check contract's slashed total
            expect(await subnetProvider.totalSlashed()).to.equal(slashAmount);
        });

        it("should allow withdrawal after lock period", async function() {
            // Remove machine to start lock period
            await subnetProvider.removeMachine(providerId, machineId);
            
            // Try to withdraw before lock period ends
            await expect(
                subnetProvider.claimWithdrawal(providerId, machineId)
            ).to.be.revertedWith("Still locked");
            
            // Advance time by lock period
            const lockPeriod = await subnetProvider.lockPeriod();
            await ethers.provider.send("evm_increaseTime", [Number(lockPeriod)]);
            await ethers.provider.send("evm_mine", []); // Mine a new block
            
            // Now withdrawal should succeed
            await subnetProvider.claimWithdrawal(providerId, machineId);
            
            // Check stake was transferred back
            const finalProviderBalance = await stakingToken.balanceOf(owner.address);
            expect(finalProviderBalance).to.be.gt(0);
            
            // Check machine is marked as processed
            const machine = (await subnetProvider.getMachines(providerId))[0];
            expect(machine.withdrawalProcessed).to.be.true;
        });
    });

    describe("Helper Functions and Status Checks", function() {
        let providerId: bigint;
        let machineId = 0n;
        
        beforeEach(async function() {
            // Register a provider
            const txProvider = await subnetProvider.registerProvider(operator.address, "provider-metadata");
            const receiptProvider = await txProvider.wait();
            providerId = await getProviderIdFromReceipt(receiptProvider!);
            
            // Add a machine
            await subnetProvider.addMachine(
                providerId,
                1, // machineType
                2, // region
                4, // cpuCores
                3000, // cpuSpeed
                1, // gpuCores
                8000, // gpuMemory
                16 * 1024, // memoryMB
                500, // diskGB
                123456789, // publicIp
                987654321, // overlayIp
                100, // uploadSpeed
                1000, // downloadSpeed
                "machine-metadata"
            );
        });
        
        it("should check if a machine is active", async function() {
            // Machine should be active initially
            expect(await subnetProvider.isMachineActive(providerId, machineId)).to.be.true;
            
            // Remove the machine
            await subnetProvider.removeMachine(providerId, machineId);
            
            // Machine should be inactive after removal
            expect(await subnetProvider.isMachineActive(providerId, machineId)).to.be.false;
        });
        
        it("should validate machine requirements correctly", async function() {
            // Should pass with equal requirements
            expect(await subnetProvider.validateMachineRequirements(
                providerId,
                machineId,
                4, // minCpuCores
                16 * 1024, // minMemoryMB
                500, // minDiskGB
                1, // minGpuCores
                100, // minUploadSpeed
                1000 // minDownloadSpeed
            )).to.be.true;
            
            // Should pass with lower requirements
            expect(await subnetProvider.validateMachineRequirements(
                providerId,
                machineId,
                2, // minCpuCores
                8 * 1024, // minMemoryMB
                250, // minDiskGB
                0, // minGpuCores
                50, // minUploadSpeed
                500 // minDownloadSpeed
            )).to.be.true;
            
            // Should fail with higher requirements
            expect(await subnetProvider.validateMachineRequirements(
                providerId,
                machineId,
                8, // minCpuCores (too high)
                16 * 1024, // minMemoryMB
                500, // minDiskGB
                1, // minGpuCores
                100, // minUploadSpeed
                1000 // minDownloadSpeed
            )).to.be.false;
        });
    });

    // Helper function to extract provider ID from event logs
    async function getProviderIdFromReceipt(receipt: any): Promise<bigint> {
        for (const log of receipt.logs) {
            try {
                const parsedLog = subnetProvider.interface.parseLog({
                    topics: log.topics,
                    data: log.data
                });
                if (parsedLog && parsedLog.name === "Transfer") {
                    return parsedLog.args.tokenId;
                }
            } catch (e) {
                // Not an event we're interested in
            }
        }
        throw new Error("Provider ID not found in transaction logs");
    }
});

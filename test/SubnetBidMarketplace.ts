import { ethers, ignition } from 'hardhat';
import { expect } from 'chai';
import { ERC20Mock, SubnetProvider, SubnetBidMarketplace } from '../typechain-types';
import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers';
import SubnetBidMarketplaceModule from '../ignition/modules/SubnetBidMarketplace';
import SubnetProviderModule from '../ignition/modules/SubnetProvider';

describe("SubnetBidMarketplace", function () {
    let marketplace: SubnetBidMarketplace;
    let provider: SubnetProvider;
    let paymentToken: ERC20Mock;
    let owner: HardhatEthersSigner, 
        platformWallet: HardhatEthersSigner, 
        provider1: HardhatEthersSigner, 
        provider2: HardhatEthersSigner, 
        client1: HardhatEthersSigner, 
        client2: HardhatEthersSigner;
    
    let providerId1: bigint;
    let machineId1: bigint;

    beforeEach(async function () {
        [owner, platformWallet, provider1, provider2, client1, client2] = await ethers.getSigners();

        // Deploy mock ERC20 for payments
        const MockErc20 = await ethers.getContractFactory("ERC20Mock");
        paymentToken = await MockErc20.deploy("Payment Token", "PAY");
        await paymentToken.mint(client1.address, ethers.parseEther("10000000"));
        await paymentToken.mint(client2.address, ethers.parseEther("10000000"));

        // Deploy SubnetProvider contract
        const { proxy: subnetProviderProxy } = await ignition.deploy(SubnetProviderModule);
        provider = await ethers.getContractAt("SubnetProvider", await subnetProviderProxy.getAddress());
        await provider.initialize(owner.address, await paymentToken.getAddress(), "Provider NFT", "PNFT");
        
        // Deploy SubnetBidMarketplace contract
        const { proxy: subnetBidMarketplaceProxy } = await ignition.deploy(SubnetBidMarketplaceModule);
        marketplace = await ethers.getContractAt("SubnetBidMarketplace", await subnetBidMarketplaceProxy.getAddress());
        await marketplace.initialize(owner.address, await paymentToken.getAddress(), await provider.getAddress());

        // Register provider and add machine
        const providerTx = await provider.connect(provider1).registerProvider(provider1.address, "provider-metadata");
        const providerReceipt = await providerTx.wait();
        providerId1 = await getProviderIdFromReceipt(providerReceipt!, provider);
        
        // Approve tokens for staking
        await paymentToken.connect(provider1).mint(provider1.address, ethers.parseEther("10000000"));
        await paymentToken.connect(provider1).approve(await provider.getAddress(), ethers.parseEther("10000000"));
        
        // Add machine for testing
        const machineTx = await provider.connect(provider1).addMachine(
            providerId1,
            1, // machineType
            2, // region
            4, // cpuCores
            3000, // cpuSpeed
            2, // gpuCores
            16000, // gpuMemory
            32 * 1024, // memoryMB (32GB)
            1000, // diskGB
            123456789, // publicIp
            987654321, // overlayIp
            100, // uploadSpeed
            1000, // downloadSpeed
            "machine-metadata"
        );
        
        const machineReceipt = await machineTx.wait();
        machineId1 = 0n; // First machine has ID 0

        // Approve payment tokens for clients
        await paymentToken.connect(client1).approve(await marketplace.getAddress(), ethers.parseEther("10000000"));
        await paymentToken.connect(client2).approve(await marketplace.getAddress(), ethers.parseEther("10000000"));
    });

    describe("Initialization and Configuration", function() {
        it("should initialize with correct parameters", async function() {
            expect(await marketplace.owner()).to.equal(owner.address);
            expect(await marketplace.paymentToken()).to.equal(await paymentToken.getAddress());
            expect(await marketplace.subnetProviderContract()).to.equal(await provider.getAddress());
            expect(await marketplace.bidTimeLimit()).to.equal(5 * 60); // 5 minutes
        });

        it("should allow owner to update bid time limit", async function() {
            await marketplace.setBidTimeLimit(10 * 60); // 10 minutes
            expect(await marketplace.bidTimeLimit()).to.equal(10 * 60);
        });
        
        it("should allow owner to update payment token", async function() {
            const newToken = await (await ethers.getContractFactory("ERC20Mock")).deploy("New Token", "NEW");
            await marketplace.setPaymentConfig(await newToken.getAddress());
            expect(await marketplace.paymentToken()).to.equal(await newToken.getAddress());
        });

        it("should allow owner to update provider contract", async function() {
            // Deploy SubnetProvider contract
            const { proxy: subnetProviderProxy } = await ignition.deploy(SubnetProviderModule);
            provider = await ethers.getContractAt("SubnetProvider", await subnetProviderProxy.getAddress());
            await provider.initialize(owner.address, await paymentToken.getAddress(), "Provider NFT", "PNFT");

            await marketplace.setSubnetProviderContract(await provider.getAddress());
            expect(await marketplace.subnetProviderContract()).to.equal(await provider.getAddress());
        });
    });

    describe("Order Management", function() {
        it("should create a new order", async function() {
            const tx = await marketplace.connect(client1).createOrder(
                1,
                7 * 24 * 60 * 60, // 1 week duration
                ethers.parseEther("0.1"), // minBidPrice
                ethers.parseEther("1.0"), // maxBidPrice
                2, // region
                4, // cpuCores
                1, // gpuCores
                8000, // gpuMemory
                16 * 1024, // memoryMB
                500, // diskGB
                50, // uploadMbps
                500, // downloadMbps
                "Order specs"
            );
            
            const receipt = await tx.wait();
            expect(receipt?.status).to.equal(1);
            
            const orderId = 1n; // First order has ID 1
            const order = await marketplace.orders(orderId);
            
            expect(order.owner).to.equal(client1.address);
            expect(order.status).to.equal(0); // Open status
            expect(order.duration).to.equal(7 * 24 * 60 * 60);
            expect(order.minBidPrice).to.equal(ethers.parseEther("0.1"));
            expect(order.maxBidPrice).to.equal(ethers.parseEther("1.0"));
            expect(order.cpuCores).to.equal(4);
            expect(order.gpuCores).to.equal(1);
            expect(order.region).to.equal(2);
        });

        it("should check if bidding is open", async function() {
            await marketplace.connect(client1).createOrder(
                1,
                7 * 24 * 60 * 60, // 1 week duration
                ethers.parseEther("0.1"), // minBidPrice
                ethers.parseEther("1.0"), // maxBidPrice
                2, // region
                4, // cpuCores
                1, // gpuCores
                8000, // gpuMemory
                16 * 1024, // memoryMB
                500, // diskGB
                50, // uploadMbps
                500, // downloadMbps
                "Order specs"
            );
            
            const orderId = 1n;
            expect(await marketplace.isBiddingOpen(orderId)).to.equal(true);
            
            // Time travel past bidding window
            await ethers.provider.send("evm_increaseTime", [6 * 60]); // 6 minutes
            await ethers.provider.send("evm_mine", []);
            
            expect(await marketplace.isBiddingOpen(orderId)).to.equal(false);
        });

        it("should return remaining bid time", async function() {
            await marketplace.connect(client1).createOrder(
                1,
                7 * 24 * 60 * 60, // 1 week duration
                ethers.parseEther("0.1"), // minBidPrice
                ethers.parseEther("1.0"), // maxBidPrice
                2, // region
                4, // cpuCores
                1, // gpuCores
                8000, // gpuMemory
                16 * 1024, // memoryMB
                500, // diskGB
                50, // uploadMbps
                500, // downloadMbps
                "Order specs"
            );
            
            const orderId = 1n;
            const remainingTime = await marketplace.getRemainingBidTime(orderId);
            expect(remainingTime).to.be.closeTo(5n * 60n, 5n); // Around 5 minutes, allowing small deviation
            
            // Time travel
            await ethers.provider.send("evm_increaseTime", [3 * 60]); // 3 minutes
            await ethers.provider.send("evm_mine", []);
            
            const newRemainingTime = await marketplace.getRemainingBidTime(orderId);
            expect(newRemainingTime).to.be.closeTo(2n * 60n, 5n); // Around 2 minutes
        });

        it("should allow order cancellation by owner", async function() {
            await marketplace.connect(client1).createOrder(
                1,
                7 * 24 * 60 * 60, // 1 week duration
                ethers.parseEther("0.1"), // minBidPrice
                ethers.parseEther("1.0"), // maxBidPrice
                2, // region
                4, // cpuCores
                1, // gpuCores
                8000, // gpuMemory
                16 * 1024, // memoryMB
                500, // diskGB
                50, // uploadMbps
                500, // downloadMbps
                "Order specs"
            );
            
            const orderId = 1n;
            await marketplace.connect(client1).cancelOrder(orderId);
            
            const order = await marketplace.orders(orderId);
            expect(order.status).to.equal(2); // Closed status
        });

        it("should not allow non-owner to cancel order", async function() {
            await marketplace.connect(client1).createOrder(
                1,
                7 * 24 * 60 * 60, // 1 week duration
                ethers.parseEther("0.1"), // minBidPrice
                ethers.parseEther("1.0"), // maxBidPrice
                2, // region
                4, // cpuCores
                1, // gpuCores
                8000, // gpuMemory
                16 * 1024, // memoryMB
                500, // diskGB
                50, // uploadMbps
                500, // downloadMbps
                "Order specs"
            );
            
            const orderId = 1n;
            await expect(
                marketplace.connect(client2).cancelOrder(orderId)
            ).to.be.revertedWith("Only order owner can cancel");
        });
    });

    describe("Bidding Process", function() {
        beforeEach(async function() {
            // Create an order for bidding tests
            await marketplace.connect(client1).createOrder(
                1,
                7 * 24 * 60 * 60, // 1 week duration
                ethers.parseEther("0.1"), // minBidPrice
                ethers.parseEther("1.0"), // maxBidPrice
                2, // region
                4, // cpuCores
                1, // gpuCores
                8000, // gpuMemory
                16 * 1024, // memoryMB
                500, // diskGB
                50, // uploadMbps
                500, // downloadMbps
                "Order specs"
            );
        });

        it("should allow provider to submit a bid", async function() {
            const orderId = 1n;
            const bidPrice = ethers.parseEther("0.5");
            
            await marketplace.connect(provider1).submitBid(
                orderId,
                bidPrice,
                providerId1,
                machineId1
            );
            
            const bids = await marketplace.getBids(orderId);
            expect(bids.length).to.equal(1);
            expect(bids[0].provider).to.equal(provider1.address);
            expect(bids[0].pricePerSecond).to.equal(bidPrice);
            expect(bids[0].providerId).to.equal(providerId1);
            expect(bids[0].machineId).to.equal(machineId1);
            expect(bids[0].status).to.equal(0); // Pending status
        });

        it("should validate machine meets order requirements", async function() {
            // Create an order with requirements higher than machine capabilities
            await marketplace.connect(client1).createOrder(
                1,
                7 * 24 * 60 * 60, // 1 week duration
                ethers.parseEther("0.1"), // minBidPrice
                ethers.parseEther("1.0"), // maxBidPrice
                2, // region
                8, // cpuCores (higher than machine's 4 cores)
                4, // gpuCores (higher than machine's 2 cores)
                32000, // gpuMemory
                64 * 1024, // memoryMB
                2000, // diskGB
                200, // uploadMbps
                2000, // downloadMbps
                "High requirement specs"
            );
            
            const orderId = 2n;
            const bidPrice = ethers.parseEther("0.5");
            
            await expect(
                marketplace.connect(provider1).submitBid(
                    orderId,
                    bidPrice,
                    providerId1,
                    machineId1
                )
            ).to.be.revertedWith("Machine does not meet requirements");
        });

        it("should reject bids outside the price range", async function() {
            const orderId = 1n;
            
            // Too low
            await expect(
                marketplace.connect(provider1).submitBid(
                    orderId,
                    ethers.parseEther("0.05"), // below min
                    providerId1,
                    machineId1
                )
            ).to.be.revertedWith("Bid price below minimum");
            
            // Too high
            await expect(
                marketplace.connect(provider1).submitBid(
                    orderId,
                    ethers.parseEther("1.5"), // above max
                    providerId1,
                    machineId1
                )
            ).to.be.revertedWith("Bid price above maximum");
        });

        it("should not allow unauthorized addresses to bid", async function() {
            const orderId = 1n;
            const bidPrice = ethers.parseEther("0.5");
            
            // Provider2 is not the owner or operator of providerId1
            await expect(
                marketplace.connect(provider2).submitBid(
                    orderId,
                    bidPrice,
                    providerId1,
                    machineId1
                )
            ).to.be.revertedWith("Not authorized to bid for this provider");
        });

        it("should allow bid cancellation", async function() {
            const orderId = 1n;
            const bidPrice = ethers.parseEther("0.5");
            
            await marketplace.connect(provider1).submitBid(
                orderId,
                bidPrice,
                providerId1,
                machineId1
            );
            
            const bidIndex = 0;
            await marketplace.connect(provider1).cancelBid(orderId, bidIndex);
            
            const bids = await marketplace.getBids(orderId);
            expect(bids[0].status).to.equal(2); // Cancelled status
        });

        it("should not allow non-provider to cancel bid", async function() {
            const orderId = 1n;
            const bidPrice = ethers.parseEther("0.5");
            
            await marketplace.connect(provider1).submitBid(
                orderId,
                bidPrice,
                providerId1,
                machineId1
            );
            
            const bidIndex = 0;
            await expect(
                marketplace.connect(provider2).cancelBid(orderId, bidIndex)
            ).to.be.revertedWith("Only bid provider can cancel");
        });

        it("should reject bids after time limit", async function() {
            const orderId = 1n;
            const bidPrice = ethers.parseEther("0.5");
            
            // Time travel past bidding window
            await ethers.provider.send("evm_increaseTime", [6 * 60]); // 6 minutes
            await ethers.provider.send("evm_mine", []);
            
            await expect(
                marketplace.connect(provider1).submitBid(
                    orderId,
                    bidPrice,
                    providerId1,
                    machineId1
                )
            ).to.be.revertedWith("Bidding time expired");
        });
    });

    describe("Accepting Bids and Payment", function() {
        let orderId: bigint;
        
        beforeEach(async function() {
            // Create an order
            await marketplace.connect(client1).createOrder(
                1,
                7 * 24 * 60 * 60, // 1 week duration
                ethers.parseEther("0.1"), // minBidPrice
                ethers.parseEther("1.0"), // maxBidPrice
                2, // region
                4, // cpuCores
                1, // gpuCores
                8000, // gpuMemory
                16 * 1024, // memoryMB
                500, // diskGB
                50, // uploadMbps
                500, // downloadMbps
                "Order specs"
            );
            
            orderId = 1n;
            
            // Submit a bid
            await marketplace.connect(provider1).submitBid(
                orderId,
                ethers.parseEther("0.5"),
                providerId1,
                machineId1
            );
        });

        it("should allow client to accept a bid", async function() {
            const bidIndex = 0;
            const initialBalance = await paymentToken.balanceOf(client1.address);
            
            await marketplace.connect(client1).acceptBid(orderId, bidIndex);
            
            const order = await marketplace.orders(orderId);
            expect(order.status).to.equal(1); // Matched status
            expect(order.acceptedProviderId).to.equal(providerId1);
            expect(order.acceptedMachineId).to.equal(machineId1);
            
            // Check payment transfer
            const finalBalance = await paymentToken.balanceOf(client1.address);
            const expectedCost = ethers.parseEther("0.5") * 7n * 24n * 60n * 60n; // price * duration
            expect(initialBalance - finalBalance).to.equal(expectedCost);
            
            // Contract balance should have increased
            const marketplaceBalance = await paymentToken.balanceOf(marketplace.getAddress());
            expect(marketplaceBalance).to.equal(expectedCost);
        });

        it("should not allow non-owner to accept bid", async function() {
            const bidIndex = 0;
            await expect(
                marketplace.connect(client2).acceptBid(orderId, bidIndex)
            ).to.be.revertedWith("Only order owner can accept");
        });

        it("should allow provider to claim payment", async function() {
            const bidIndex = 0;
            await marketplace.connect(client1).acceptBid(orderId, bidIndex);
            
            // Time travel to simulate some usage
            await ethers.provider.send("evm_increaseTime", [3600]); // 1 hour
            await ethers.provider.send("evm_mine", []);
            
            const initialProviderBalance = await paymentToken.balanceOf(provider1.address);
            
            await marketplace.connect(provider1).claimPayment(orderId);
            
            const finalProviderBalance = await paymentToken.balanceOf(provider1.address);
            
            // Provider should have received payment for 1 hour
            const expectedPayment = ethers.parseEther("0.5") * 3600n; // price * 1 hour
            expect(finalProviderBalance - initialProviderBalance).to.be.closeTo(expectedPayment, ethers.parseEther("50"));
        });
    });

    describe("Order Extension and Closing", function() {
        let orderId: bigint;
        
        beforeEach(async function() {
            // Create and match an order
            await marketplace.connect(client1).createOrder(
                1,
                7 * 24 * 60 * 60, // 1 week duration
                ethers.parseEther("0.1"), // minBidPrice
                ethers.parseEther("1.0"), // maxBidPrice
                2, // region
                4, // cpuCores
                1, // gpuCores
                8000, // gpuMemory
                16 * 1024, // memoryMB
                500, // diskGB
                50, // uploadMbps
                500, // downloadMbps
                "Order specs"
            );
            
            orderId = 1n;
            
            await marketplace.connect(provider1).submitBid(
                orderId,
                ethers.parseEther("0.5"),
                providerId1,
                machineId1
            );
            
            await marketplace.connect(client1).acceptBid(orderId, 0);
        });

        it("should allow order owner to extend duration", async function() {
            const initialBalance = await paymentToken.balanceOf(client1.address);
            const initialExpiry = (await marketplace.orders(orderId)).expiredAt;
            
            await marketplace.connect(client1).extend(orderId);
            
            const finalOrder = await marketplace.orders(orderId);
            
            // Expiry should be increased by original duration
            expect(finalOrder.expiredAt).to.be.gt(initialExpiry);
            
            // Payment should have been made
            const finalBalance = await paymentToken.balanceOf(client1.address);
            const expectedCost = ethers.parseEther("0.5") * 7n * 24n * 60n * 60n; // price * original duration
            expect(initialBalance - finalBalance).to.equal(expectedCost);
        });

        it("should allow order owner to close order early with refund", async function() {
            const initialClientBalance = await paymentToken.balanceOf(client1.address);
            
            await marketplace.connect(client1).closeOrder(orderId, "early termination");
            
            const finalOrder = await marketplace.orders(orderId);
            expect(finalOrder.status).to.equal(2); // Closed status
            
            // Client should get refund for unused time
            const finalClientBalance = await paymentToken.balanceOf(client1.address);
            expect(finalClientBalance).to.be.gt(initialClientBalance);
        });

        it("should not allow non-owner to close order", async function() {
            await expect(
                marketplace.connect(client2).closeOrder(orderId, "unauthorized")
            ).to.be.revertedWith("Not authorized");
        });
    });

    // Helper function to extract provider ID from transaction logs
    async function getProviderIdFromReceipt(receipt: any, providerContract: SubnetProvider): Promise<bigint> {
        for (const log of receipt.logs) {
            try {
                const parsedLog = providerContract.interface.parseLog({
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

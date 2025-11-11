import { ethers, ignition } from 'hardhat';
import { expect } from 'chai';
import { ERC20Mock, SubnetProvider, SubnetDirectProviderMarketplace } from '../../typechain-types';
import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers';
import SubnetDirectProviderMarketplaceModule from '../../ignition/modules/SubnetDirectProviderMarketplace';
import SubnetProviderModule from '../../ignition/modules/SubnetProvider';

describe("SubnetDirectProviderMarketplace", function () {
    let marketplace: SubnetDirectProviderMarketplace;
    let provider: SubnetProvider;
    let paymentToken: ERC20Mock;
    let owner: HardhatEthersSigner;
    let provider1: HardhatEthersSigner;
    let client1: HardhatEthersSigner;

    beforeEach(async function () {
        [owner, provider1, client1] = await ethers.getSigners();

        // Deploy mock ERC20 for payments
        const MockErc20 = await ethers.getContractFactory("ERC20Mock");
        paymentToken = await MockErc20.deploy("Payment Token", "PAY");
        await paymentToken.mint(client1.address, ethers.parseEther("10000000"));

        // Deploy SubnetProvider contract
        const { proxy: subnetProviderProxy } = await ignition.deploy(SubnetProviderModule);
        provider = await ethers.getContractAt("SubnetProvider", await subnetProviderProxy.getAddress());
        await provider.initialize(owner.address, await paymentToken.getAddress());
        
        // Deploy SubnetDirectProviderMarketplace contract
        const { proxy: marketplaceProxy } = await ignition.deploy(SubnetDirectProviderMarketplaceModule);
        marketplace = await ethers.getContractAt("SubnetDirectProviderMarketplace", await marketplaceProxy.getAddress());
        await marketplace.initialize(owner.address, await paymentToken.getAddress(), await provider.getAddress());

        // Authorize marketplace to lock/unlock resources
        await provider.setAuthorizedLocker(await marketplace.getAddress(), true);

        // Register provider
        await paymentToken.connect(provider1).mint(provider1.address, ethers.parseEther("10000000"));
        await paymentToken.connect(provider1).approve(await provider.getAddress(), ethers.parseEther("10000000"));
        await provider.connect(provider1).registerProvider(
            provider1.address,
            "provider-metadata",
            1, // machineType
            2, // region
            4, // cpuCores
            1, // gpuCores
            8000, // gpuMemory
            16 * 1024, // memoryMB
            500, // diskGB
            1, // cpuPricePerSecond
            2, // gpuPricePerSecond
            3, // memoryPricePerSecond
            4  // diskPricePerSecond
        );

        // Approve payment tokens
        await paymentToken.connect(client1).approve(await marketplace.getAddress(), ethers.parseEther("10000000"));
    });

    describe("Initialization", function() {
        it("should initialize with correct parameters", async function() {
            expect(await marketplace.owner()).to.equal(owner.address);
            expect(await marketplace.paymentToken()).to.equal(await paymentToken.getAddress());
            expect(await marketplace.subnetProviderContract()).to.equal(await provider.getAddress());
        });
    });

    describe("Order Creation", function() {
        it("should create order with provider and auto-accept if price matches", async function() {
            // Calculate expected price: 4*1 + 1*2 + (16*1024/1024)*3 + 500*4 = 4 + 2 + 48 + 2000 = 2054
            const maxPrice = ethers.parseEther("3000"); // Higher than actual price
            
            const tx = await marketplace.connect(client1).createOrder(
                1, // machineType
                3600, // duration (1 hour)
                maxPrice,
                2, // region
                4, // cpuCores
                1, // gpuCores
                8000, // gpuMemory
                16 * 1024, // memoryMB
                500, // diskGB
                "test-specs",
                provider1.address
            );
            
            const receipt = await tx.wait();
            expect(receipt).to.not.be.null;
            
            const order = await marketplace.orders(1);
            expect(order.status).to.equal(1); // Matched
            expect(order.acceptedProvider).to.equal(provider1.address);
            expect(order.targetProvider).to.equal(provider1.address);
        });

        it("should reject if provider price exceeds maxPrice", async function() {
            // Actual price: 4*1 + 1*2 + (16*1024/1024)*3 + 500*4 = 4 + 2 + 48 + 2000 = 2054 wei
            const maxPrice = 1000; // Lower than actual price (2054 wei)
            
            await expect(
                marketplace.connect(client1).createOrder(
                    1, 3600, maxPrice, 2, 4, 1, 8000, 16 * 1024, 500, "specs", provider1.address
                )
            ).to.be.revertedWith("Provider price exceeds maximum");
        });

        it("should reject if provider does not meet requirements", async function() {
            const maxPrice = ethers.parseEther("10000");
            
            await expect(
                marketplace.connect(client1).createOrder(
                    1, 3600, maxPrice, 2, 100, 100, 8000, 16 * 1024, 500, "specs", provider1.address
                )
            ).to.be.revertedWith("Provider does not meet requirements");
        });
    });

    describe("Payment and Closing", function() {
        beforeEach(async function() {
            const maxPrice = ethers.parseEther("10000");
            await marketplace.connect(client1).createOrder(
                1, 3600, maxPrice, 2, 4, 1, 8000, 16 * 1024, 500, "specs", provider1.address
            );
        });

        it("should allow provider to claim payment", async function() {
            await ethers.provider.send("evm_increaseTime", [1800]); // 30 minutes
            await ethers.provider.send("evm_mine", []);

            const before = await paymentToken.balanceOf(provider1.address);
            await marketplace.connect(provider1).claimPayment(1);
            const after = await paymentToken.balanceOf(provider1.address);
            
            expect(after).to.be.gt(before);
        });

        it("should allow closing order and refund remaining", async function() {
            await ethers.provider.send("evm_increaseTime", [1800]);
            await ethers.provider.send("evm_mine", []);

            const before = await paymentToken.balanceOf(client1.address);
            await marketplace.connect(client1).closeOrder(1, "test reason");
            const after = await paymentToken.balanceOf(client1.address);
            
            expect(after).to.be.gt(before); // Should get refund
        });
    });

    describe("Order Extension", function() {
        beforeEach(async function() {
            const maxPrice = ethers.parseEther("10000");
            await marketplace.connect(client1).createOrder(
                1, 3600, maxPrice, 2, 4, 1, 8000, 16 * 1024, 500, "specs", provider1.address
            );
        });

        it("should allow extending order duration", async function() {
            const orderBefore = await marketplace.orders(1);
            const extendAmount = ethers.parseEther("5000");
            
            await paymentToken.connect(client1).approve(await marketplace.getAddress(), extendAmount);
            await marketplace.connect(client1).extend(1, extendAmount);
            
            const orderAfter = await marketplace.orders(1);
            expect(orderAfter.expiredAt).to.be.gt(orderBefore.expiredAt);
        });
    });
});


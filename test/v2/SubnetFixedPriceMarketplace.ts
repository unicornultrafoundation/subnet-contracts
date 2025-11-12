import { ethers, ignition } from 'hardhat';
import { expect } from 'chai';
import { ERC20Mock, SubnetProvider, SubnetFixedPriceMarketplace } from '../../typechain-types';
import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers';
import SubnetFixedPriceMarketplaceModule from '../../ignition/modules/SubnetFixedPriceMarketplace';
import SubnetProviderModule from '../../ignition/modules/SubnetProvider';

describe("SubnetFixedPriceMarketplace", function () {
    let marketplace: SubnetFixedPriceMarketplace;
    let provider: SubnetProvider;
    let paymentToken: ERC20Mock;
    let owner: HardhatEthersSigner;
    let provider1: HardhatEthersSigner;
    let provider2: HardhatEthersSigner;
    let client1: HardhatEthersSigner;

    beforeEach(async function () {
        [owner, provider1, provider2, client1] = await ethers.getSigners();

        // Deploy mock ERC20 for payments
        const MockErc20 = await ethers.getContractFactory("ERC20Mock");
        paymentToken = await MockErc20.deploy("Payment Token", "PAY");
        await paymentToken.mint(client1.address, ethers.parseEther("10000000"));

        // Deploy SubnetProvider contract
        const { proxy: subnetProviderProxy } = await ignition.deploy(SubnetProviderModule);
        provider = await ethers.getContractAt("SubnetProvider", await subnetProviderProxy.getAddress());
        await provider.initialize(owner.address, await paymentToken.getAddress());
        
        // Deploy SubnetFixedPriceMarketplace contract
        const { proxy: marketplaceProxy } = await ignition.deploy(SubnetFixedPriceMarketplaceModule);
        marketplace = await ethers.getContractAt("SubnetFixedPriceMarketplace", await marketplaceProxy.getAddress());
        await marketplace.initialize(owner.address, await paymentToken.getAddress(), await provider.getAddress());

        // Authorize marketplace to lock/unlock resources
        await provider.setAuthorizedLocker(await marketplace.getAddress(), true);

        // Register providers
        await registerProvider(provider1, 4, 1, 16 * 1024, 500);
        await registerProvider(provider2, 8, 2, 32 * 1024, 1000);

        // Approve payment tokens for client
        await paymentToken.connect(client1).approve(await marketplace.getAddress(), ethers.parseEther("10000000"));
    });

    async function registerProvider(
        signer: HardhatEthersSigner,
        cpu: number,
        gpu: number,
        memMB: number,
        diskGB: number
    ) {
        await paymentToken.connect(signer).mint(signer.address, ethers.parseEther("10000000"));
        await paymentToken.connect(signer).approve(await provider.getAddress(), ethers.parseEther("10000000"));
        await (provider.connect(signer) as any).registerProvider(
            signer.address,
            "provider-metadata",
            1, // machineType
            2, // region
            cpu,
            gpu,
            memMB,
            diskGB,
            1, // cpuPricePerSecond
            2, // gpuPricePerSecond
            3, // memoryPricePerSecond
            4  // diskPricePerSecond
        );
    }

    describe("Initialization", function() {
        it("should initialize with correct parameters", async function() {
            expect(await marketplace.owner()).to.equal(owner.address);
            expect(await marketplace.paymentToken()).to.equal(await paymentToken.getAddress());
            expect(await marketplace.subnetProviderContract()).to.equal(await provider.getAddress());
        });
    });

    describe("Order Creation", function() {
        it("should create a fixed price order", async function() {
            const tx = await (marketplace.connect(client1) as any).createOrder(
                1, // machineType
                3600, // duration (1 hour)
                ethers.parseEther("10"), // fixedPricePerSecond
                2, // region
                4, // cpuCores
                1, // gpuCores
                16 * 1024, // memoryMB
                500, // diskGB
                "test-specs",
                [], // blacklistedProviders
                []  // whitelistedProviders
            );
            
            const receipt = await tx.wait();
            expect(receipt).to.not.be.null;
            
            const order = await marketplace.orders(1);
            expect(order.status).to.equal(0); // Open
            expect(order.fixedPrice).to.equal(ethers.parseEther("10"));
        });
    });

    describe("Provider Acceptance", function() {
        beforeEach(async function() {
            await (marketplace.connect(client1) as any).createOrder(
                1, 3600, ethers.parseEther("10"), 2, 4, 1, 16 * 1024, 500, "specs", [], []
            );
        });

        it("should allow provider to accept order", async function() {
            await marketplace.connect(provider1).acceptOrderByProvider(1);
            
            const acceptances = await marketplace.getProviderAcceptances(1);
            expect(acceptances.length).to.equal(1);
            expect(acceptances[0].provider).to.equal(provider1.address);
            expect(acceptances[0].isActive).to.be.true;
            
            // Order should remain Open
            const order = await marketplace.orders(1);
            expect(order.status).to.equal(0); // Open
        });

        it("should allow multiple providers to accept same order", async function() {
            await marketplace.connect(provider1).acceptOrderByProvider(1);
            await marketplace.connect(provider2).acceptOrderByProvider(1);
            
            const acceptances = await marketplace.getProviderAcceptances(1);
            expect(acceptances.length).to.equal(2);
            expect(acceptances[0].provider).to.equal(provider1.address);
            expect(acceptances[1].provider).to.equal(provider2.address);
        });

        it("should prevent provider from accepting same order twice", async function() {
            await marketplace.connect(provider1).acceptOrderByProvider(1);
            
            await expect(
                marketplace.connect(provider1).acceptOrderByProvider(1)
            ).to.be.revertedWith("Provider already accepted this order");
        });

        it("should reject if provider does not meet requirements", async function() {
            // Create order with higher requirements
            await (marketplace.connect(client1) as any).createOrder(
                1, 3600, ethers.parseEther("10"), 2, 100, 100, 16 * 1024, 500, "specs", [], []
            );
            
            await expect(
                marketplace.connect(provider1).acceptOrderByProvider(2)
            ).to.be.revertedWith("Provider does not meet requirements");
        });
    });

    describe("Payment Claiming", function() {
        beforeEach(async function() {
            await (marketplace.connect(client1) as any).createOrder(
                1, 3600, ethers.parseEther("10"), 2, 4, 1, 16 * 1024, 500, "specs", [], []
            );
            await marketplace.connect(provider1).acceptOrderByProvider(1);
            
            // Approve for payment claiming
            await paymentToken.connect(client1).approve(await marketplace.getAddress(), ethers.parseEther("10000000"));
        });

        it("should allow provider to claim payment based on actual time used", async function() {
            await ethers.provider.send("evm_increaseTime", [1800]); // 30 minutes
            await ethers.provider.send("evm_mine", []);

            const before = await paymentToken.balanceOf(provider1.address);
            await marketplace.connect(provider1).claimPaymentForFixedPrice(1, 0);
            const after = await paymentToken.balanceOf(provider1.address);
            
            expect(after).to.be.gt(before);
        });

        it("should allow multiple claims", async function() {
            await ethers.provider.send("evm_increaseTime", [900]); // 15 minutes
            await ethers.provider.send("evm_mine", []);
            await marketplace.connect(provider1).claimPaymentForFixedPrice(1, 0);
            
            await ethers.provider.send("evm_increaseTime", [900]); // Another 15 minutes
            await ethers.provider.send("evm_mine", []);
            
            const before = await paymentToken.balanceOf(provider1.address);
            await marketplace.connect(provider1).claimPaymentForFixedPrice(1, 0);
            const after = await paymentToken.balanceOf(provider1.address);
            
            expect(after).to.be.gt(before);
        });
    });

    describe("Closing Acceptance", function() {
        beforeEach(async function() {
            await (marketplace.connect(client1) as any).createOrder(
                1, 3600, ethers.parseEther("10"), 2, 4, 1, 16 * 1024, 500, "specs", [], []
            );
            await marketplace.connect(provider1).acceptOrderByProvider(1);
            await paymentToken.connect(client1).approve(await marketplace.getAddress(), ethers.parseEther("10000000"));
        });

        it("should allow provider to close acceptance", async function() {
            await ethers.provider.send("evm_increaseTime", [1800]);
            await ethers.provider.send("evm_mine", []);

            await marketplace.connect(provider1).closeProviderAcceptance(1, 0);
            
            const acceptances = await marketplace.getProviderAcceptances(1);
            expect(acceptances[0].isActive).to.be.false;
        });

        it("should allow order owner to close acceptance", async function() {
            await marketplace.connect(client1).closeProviderAcceptance(1, 0);
            
            const acceptances = await marketplace.getProviderAcceptances(1);
            expect(acceptances[0].isActive).to.be.false;
        });

        it("should unlock resources when closing", async function() {
            const lockedBefore = await provider.lockedResources(provider1.address);
            expect(lockedBefore.cpuCores).to.be.gt(0);
            
            await marketplace.connect(provider1).closeProviderAcceptance(1, 0);
            
            const lockedAfter = await provider.lockedResources(provider1.address);
            expect(lockedAfter.cpuCores).to.equal(0);
        });
    });

    describe("Order Cancellation", function() {
        beforeEach(async function() {
            await (marketplace.connect(client1) as any).createOrder(
                1, 3600, ethers.parseEther("10"), 2, 4, 1, 16 * 1024, 500, "specs", [], []
            );
        });

        it("should allow order owner to cancel order", async function() {
            await marketplace.connect(client1).cancelOrder(1);
            
            const order = await marketplace.orders(1);
            expect(order.status).to.equal(2); // Closed
        });

        it("should not allow non-owner to cancel", async function() {
            await expect(
                marketplace.connect(provider1).cancelOrder(1)
            ).to.be.revertedWith("Only order owner can cancel");
        });
    });

    describe("Blacklist", function() {
        beforeEach(async function() {
            await (marketplace.connect(client1) as any).createOrder(
                1, 3600, ethers.parseEther("10"), 2, 4, 1, 16 * 1024, 500, "specs", [], []
            );
        });

        it("should blacklist providers when creating order", async function() {
            await (marketplace.connect(client1) as any).createOrder(
                1, 3600, ethers.parseEther("10"), 2, 4, 1, 16 * 1024, 500, "specs",
                [provider1.address], // blacklistedProviders
                []  // whitelistedProviders
            );

            expect(await (marketplace as any).isProviderBlacklisted(2, provider1.address)).to.be.true;
            expect(await (marketplace as any).isProviderBlacklisted(2, provider2.address)).to.be.false;
        });

        it("should prevent blacklisted provider from accepting order", async function() {
            await (marketplace.connect(client1) as any).createOrder(
                1, 3600, ethers.parseEther("10"), 2, 4, 1, 16 * 1024, 500, "specs",
                [provider1.address], // blacklistedProviders
                []  // whitelistedProviders
            );

            await expect(
                marketplace.connect(provider1).acceptOrderByProvider(2)
            ).to.be.revertedWith("Provider is blacklisted");

            // provider2 should be able to accept
            await marketplace.connect(provider2).acceptOrderByProvider(2);
            const acceptances = await marketplace.getProviderAcceptances(2);
            expect(acceptances.length).to.equal(1);
            expect(acceptances[0].provider).to.equal(provider2.address);
        });

        it("should prevent blacklisted provider from claiming payment", async function() {
            await (marketplace.connect(client1) as any).createOrder(
                1, 3600, ethers.parseEther("10"), 2, 4, 1, 16 * 1024, 500, "specs",
                [], []  // no blacklist initially
            );
            
            await marketplace.connect(provider1).acceptOrderByProvider(2);
            await paymentToken.connect(client1).approve(await marketplace.getAddress(), ethers.parseEther("10000000"));
            
            await ethers.provider.send("evm_increaseTime", [1800]);
            await ethers.provider.send("evm_mine", []);

            // Blacklist provider1
            await (marketplace.connect(client1) as any).updateOrderBlacklist(
                2,
                [provider1.address],
                [true]
            );

            // Provider1 should not be able to claim payment
            await expect(
                marketplace.connect(provider1).claimPaymentForFixedPrice(2, 0)
            ).to.be.revertedWith("Provider is blacklisted");
        });

        it("should not pay blacklisted provider when closing acceptance", async function() {
            await (marketplace.connect(client1) as any).createOrder(
                1, 3600, ethers.parseEther("10"), 2, 4, 1, 16 * 1024, 500, "specs",
                [], []  // no blacklist initially
            );
            
            await marketplace.connect(provider1).acceptOrderByProvider(2);
            await paymentToken.connect(client1).approve(await marketplace.getAddress(), ethers.parseEther("10000000"));
            
            await ethers.provider.send("evm_increaseTime", [1800]);
            await ethers.provider.send("evm_mine", []);

            // Blacklist provider1
            await (marketplace.connect(client1) as any).updateOrderBlacklist(
                2,
                [provider1.address],
                [true]
            );

            const balanceBefore = await paymentToken.balanceOf(provider1.address);
            await marketplace.connect(provider1).closeProviderAcceptance(2, 0);
            const balanceAfter = await paymentToken.balanceOf(provider1.address);

            // Provider should not receive payment
            expect(balanceAfter).to.equal(balanceBefore);

            // But acceptance should be closed
            const acceptances = await marketplace.getProviderAcceptances(2);
            expect(acceptances[0].isActive).to.be.false;
        });

        it("should allow order owner to update blacklist", async function() {
            await (marketplace.connect(client1) as any).createOrder(
                1, 3600, ethers.parseEther("10"), 2, 4, 1, 16 * 1024, 500, "specs",
                [], []  // no blacklist initially
            );

            // Add to blacklist
            await (marketplace.connect(client1) as any).updateOrderBlacklist(
                1,
                [provider1.address],
                [true]
            );
            expect(await (marketplace as any).isProviderBlacklisted(1, provider1.address)).to.be.true;

            // Remove from blacklist
            await (marketplace.connect(client1) as any).updateOrderBlacklist(
                1,
                [provider1.address],
                [false]
            );
            expect(await (marketplace as any).isProviderBlacklisted(1, provider1.address)).to.be.false;

            // Provider should be able to accept now
            await marketplace.connect(provider1).acceptOrderByProvider(1);
        });

        it("should allow blacklisting provider with active acceptance", async function() {
            await (marketplace.connect(client1) as any).createOrder(
                1, 3600, ethers.parseEther("10"), 2, 4, 1, 16 * 1024, 500, "specs",
                [], []  // no blacklist initially
            );
            
            await marketplace.connect(provider1).acceptOrderByProvider(1);
            await paymentToken.connect(client1).approve(await marketplace.getAddress(), ethers.parseEther("10000000"));

            // Should be able to blacklist even with active acceptance
            await (marketplace.connect(client1) as any).updateOrderBlacklist(
                1,
                [provider1.address],
                [true]
            );
            expect(await (marketplace as any).isProviderBlacklisted(1, provider1.address)).to.be.true;
        });
    });

    describe("Whitelist", function() {
        beforeEach(async function() {
            await (marketplace.connect(client1) as any).createOrder(
                1, 3600, ethers.parseEther("10"), 2, 4, 1, 16 * 1024, 500, "specs", [], []
            );
        });

        it("should whitelist providers when creating order", async function() {
            await (marketplace.connect(client1) as any).createOrder(
                1, 3600, ethers.parseEther("10"), 2, 4, 1, 16 * 1024, 500, "specs",
                [], // blacklistedProviders
                [provider1.address]  // whitelistedProviders
            );

            expect(await (marketplace as any).isProviderWhitelisted(2, provider1.address)).to.be.true;
            expect(await (marketplace as any).isProviderWhitelisted(2, provider2.address)).to.be.false;
            expect(await (marketplace as any).orderWhitelistCount(2)).to.equal(1);
        });

        it("should only allow whitelisted providers to accept when whitelist exists", async function() {
            await (marketplace.connect(client1) as any).createOrder(
                1, 3600, ethers.parseEther("10"), 2, 4, 1, 16 * 1024, 500, "specs",
                [], // blacklistedProviders
                [provider1.address]  // whitelistedProviders
            );

            // Whitelisted provider should be able to accept
            await marketplace.connect(provider1).acceptOrderByProvider(2);
            const acceptances = await marketplace.getProviderAcceptances(2);
            expect(acceptances.length).to.equal(1);
            expect(acceptances[0].provider).to.equal(provider1.address);

            // Non-whitelisted provider should not be able to accept
            await expect(
                marketplace.connect(provider2).acceptOrderByProvider(2)
            ).to.be.revertedWith("Provider is not whitelisted");
        });

        it("should allow all providers to accept when no whitelist exists", async function() {
            // Use order from beforeEach (orderId = 1, no whitelist)
            expect(await (marketplace as any).orderWhitelistCount(1)).to.equal(0);

            // Both providers should be able to accept
            await marketplace.connect(provider1).acceptOrderByProvider(1);
            await marketplace.connect(provider2).acceptOrderByProvider(1);

            const acceptances = await marketplace.getProviderAcceptances(1);
            expect(acceptances.length).to.equal(2);
        });

        it("should allow order owner to update whitelist", async function() {
            await (marketplace.connect(client1) as any).createOrder(
                1, 3600, ethers.parseEther("10"), 2, 4, 1, 16 * 1024, 500, "specs",
                [], [provider1.address]  // whitelist provider1
            );
            // Order ID will be 2 (because beforeEach created order 1)

            // Add provider2 to whitelist
            await (marketplace.connect(client1) as any).updateOrderWhitelist(
                2,
                [provider2.address],
                [true]
            );
            expect(await (marketplace as any).isProviderWhitelisted(2, provider2.address)).to.be.true;
            expect(await (marketplace as any).orderWhitelistCount(2)).to.equal(2);

            // Remove provider1 from whitelist
            await (marketplace.connect(client1) as any).updateOrderWhitelist(
                2,
                [provider1.address],
                [false]
            );
            expect(await (marketplace as any).isProviderWhitelisted(2, provider1.address)).to.be.false;
            expect(await (marketplace as any).orderWhitelistCount(2)).to.equal(1);

            // provider1 should not be able to accept anymore
            await expect(
                marketplace.connect(provider1).acceptOrderByProvider(2)
            ).to.be.revertedWith("Provider is not whitelisted");

            // provider2 should still be able to accept
            await marketplace.connect(provider2).acceptOrderByProvider(2);
        });

        it("should prioritize blacklist over whitelist", async function() {
            await (marketplace.connect(client1) as any).createOrder(
                1, 3600, ethers.parseEther("10"), 2, 4, 1, 16 * 1024, 500, "specs",
                [provider1.address], // blacklistedProviders
                [provider1.address]  // whitelistedProviders (same provider)
            );
            // Order ID will be 2 (because beforeEach created order 1)

            // Even though provider1 is whitelisted, they are blacklisted so cannot accept
            await expect(
                marketplace.connect(provider1).acceptOrderByProvider(2)
            ).to.be.revertedWith("Provider is blacklisted");
        });
    });
});


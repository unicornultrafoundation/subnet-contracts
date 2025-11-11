import { ethers, ignition } from 'hardhat';
import { expect } from 'chai';
import { ERC20Mock, SubnetProvider, SubnetBidMarketplace } from '../../typechain-types';
import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers';
import SubnetBidMarketplaceModule from '../../ignition/modules/SubnetBidMarketplace';
import SubnetProviderModule from '../../ignition/modules/SubnetProvider';

describe("SubnetBidMarketplace", function () {
    let marketplace: SubnetBidMarketplace;
    let provider: SubnetProvider;
    let paymentToken: ERC20Mock;
    let owner: HardhatEthersSigner;
    let provider1: HardhatEthersSigner;
    let provider2: HardhatEthersSigner;
    let client1: HardhatEthersSigner;
    let client2: HardhatEthersSigner;

    beforeEach(async function () {
        [owner, provider1, provider2, client1, client2] = await ethers.getSigners();

        // Deploy mock ERC20 for payments
        const MockErc20 = await ethers.getContractFactory("ERC20Mock");
        paymentToken = await MockErc20.deploy("Payment Token", "PAY");
        await paymentToken.mint(client1.address, ethers.parseEther("10000000"));
        await paymentToken.mint(client2.address, ethers.parseEther("10000000"));

        // Deploy SubnetProvider contract
        const { proxy: subnetProviderProxy } = await ignition.deploy(SubnetProviderModule);
        provider = await ethers.getContractAt("SubnetProvider", await subnetProviderProxy.getAddress());
        await provider.initialize(owner.address, await paymentToken.getAddress());
        
        // Deploy SubnetBidMarketplace contract
        const { proxy: marketplaceProxy } = await ignition.deploy(SubnetBidMarketplaceModule);
        marketplace = await ethers.getContractAt("SubnetBidMarketplace", await marketplaceProxy.getAddress());
        await marketplace.initialize(owner.address, await paymentToken.getAddress(), await provider.getAddress());

        // Authorize marketplace to lock/unlock resources
        await provider.setAuthorizedLocker(await marketplace.getAddress(), true);

        // Register providers
        await registerProvider(provider1, 4, 1, 8000, 16 * 1024, 500, 1, 2, 3, 4);
        await registerProvider(provider2, 8, 2, 16000, 32 * 1024, 1000, 2, 4, 6, 8);

        // Approve payment tokens
        await paymentToken.connect(client1).approve(await marketplace.getAddress(), ethers.parseEther("10000000"));
        await paymentToken.connect(client2).approve(await marketplace.getAddress(), ethers.parseEther("10000000"));
    });

    async function registerProvider(
        signer: HardhatEthersSigner,
        cpu: number,
        gpu: number,
        gpuMem: number,
        memMB: number,
        diskGB: number,
        cpuPrice: number,
        gpuPrice: number,
        memPrice: number,
        diskPrice: number
    ) {
        await paymentToken.connect(signer).mint(signer.address, ethers.parseEther("10000000"));
        await paymentToken.connect(signer).approve(await provider.getAddress(), ethers.parseEther("10000000"));
        await provider.connect(signer).registerProvider(
            signer.address,
            "provider-metadata",
            1, // machineType
            2, // region
            cpu,
            gpu,
            gpuMem,
            memMB,
            diskGB,
            cpuPrice,
            gpuPrice,
            memPrice,
            diskPrice
        );
    }

    describe("Initialization", function() {
        it("should initialize with correct parameters", async function() {
            expect(await marketplace.owner()).to.equal(owner.address);
            expect(await marketplace.paymentToken()).to.equal(await paymentToken.getAddress());
            expect(await marketplace.subnetProviderContract()).to.equal(await provider.getAddress());
            expect(await marketplace.bidTimeLimit()).to.equal(5 * 60);
        });

        it("should allow owner to update bid time limit", async function() {
            await marketplace.setBidTimeLimit(10 * 60);
            expect(await marketplace.bidTimeLimit()).to.equal(10 * 60);
        });
    });

    describe("Order Creation and Bidding", function() {
        it("should create a bidding order", async function() {
            const tx = await marketplace.connect(client1).createOrder(
                1, // machineType
                3600, // duration (1 hour)
                ethers.parseEther("1"), // minBidPrice
                ethers.parseEther("10"), // maxBidPrice
                2, // region
                4, // cpuCores
                1, // gpuCores
                8000, // gpuMemory
                16 * 1024, // memoryMB
                500, // diskGB
                "test-specs"
            );
            const receipt = await tx.wait();
            expect(receipt).to.not.be.null;
            expect(await marketplace.orderCount()).to.equal(1);
        });

        it("should allow provider to submit bid", async function() {
            await marketplace.connect(client1).createOrder(1, 3600, ethers.parseEther("1"), ethers.parseEther("10"), 2, 4, 1, 8000, 16 * 1024, 500, "specs");
            
            await marketplace.connect(provider1).submitBid(1, ethers.parseEther("5"), provider1.address);
            
            const bids = await marketplace.getBids(1);
            expect(bids.length).to.equal(1);
            expect(bids[0].provider).to.equal(provider1.address);
            expect(bids[0].pricePerSecond).to.equal(ethers.parseEther("5"));
        });

        it("should reject bid if price out of range", async function() {
            await marketplace.connect(client1).createOrder(1, 3600, ethers.parseEther("1"), ethers.parseEther("10"), 2, 4, 1, 8000, 16 * 1024, 500, "specs");
            
            await expect(
                marketplace.connect(provider1).submitBid(1, ethers.parseEther("0.5"), provider1.address)
            ).to.be.revertedWith("Bid price below minimum");

            await expect(
                marketplace.connect(provider1).submitBid(1, ethers.parseEther("20"), provider1.address)
            ).to.be.revertedWith("Bid price above maximum");
        });

        it("should allow order owner to accept bid", async function() {
            await marketplace.connect(client1).createOrder(1, 3600, ethers.parseEther("1"), ethers.parseEther("10"), 2, 4, 1, 8000, 16 * 1024, 500, "specs");
            await marketplace.connect(provider1).submitBid(1, ethers.parseEther("5"), provider1.address);
            
            await marketplace.connect(client1).acceptBid(1, 0);
            
            const order = await marketplace.orders(1);
            expect(order.status).to.equal(1); // Matched
            expect(order.acceptedProvider).to.equal(provider1.address);
        });
    });

    describe("Payment and Closing", function() {
        beforeEach(async function() {
            await marketplace.connect(client1).createOrder(1, 3600, ethers.parseEther("1"), ethers.parseEther("10"), 2, 4, 1, 8000, 16 * 1024, 500, "specs");
            await marketplace.connect(provider1).submitBid(1, ethers.parseEther("5"), provider1.address);
            await marketplace.connect(client1).acceptBid(1, 0);
        });

        it("should allow provider to claim payment", async function() {
            // Advance time
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
            await marketplace.connect(client1).createOrder(1, 3600, ethers.parseEther("1"), ethers.parseEther("10"), 2, 4, 1, 8000, 16 * 1024, 500, "specs");
            await marketplace.connect(provider1).submitBid(1, ethers.parseEther("5"), provider1.address);
            await marketplace.connect(client1).acceptBid(1, 0);
        });

        it("should allow extending order duration", async function() {
            const orderBefore = await marketplace.orders(1);
            const extendAmount = ethers.parseEther("5");
            
            await paymentToken.connect(client1).approve(await marketplace.getAddress(), extendAmount);
            await marketplace.connect(client1).extend(1, extendAmount);
            
            const orderAfter = await marketplace.orders(1);
            expect(orderAfter.expiredAt).to.be.gt(orderBefore.expiredAt);
        });
    });
});


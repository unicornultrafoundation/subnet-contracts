import { ethers, ignition } from 'hardhat';
import { expect } from 'chai';
import { SubnetIPRegistry, ERC20Mock } from '../typechain-types';
import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers';
import SubnetIPRegistryModule from '../ignition/modules/SubnetIPRegistry';

describe("SubnetIPRegistry", function () {
    let subnetIPRegistry: SubnetIPRegistry;
    let owner: HardhatEthersSigner, user: HardhatEthersSigner, addr1: HardhatEthersSigner;
    let paymentToken: ERC20Mock;
    const purchaseFee = ethers.parseEther("10");

    beforeEach(async function () {
        [owner, user, addr1] = await ethers.getSigners();

        // Deploy mock ERC20 token
        const ERC20MockFactory = await ethers.getContractFactory("ERC20Mock");
        paymentToken = await ERC20MockFactory.deploy("Payment Token", "PT");
        await paymentToken.mint(user.address, ethers.parseEther("1000"));

        const { proxy: subnetIPRegistryProxy } = await ignition.deploy(SubnetIPRegistryModule);
        subnetIPRegistry = await ethers.getContractAt("SubnetIPRegistry", await subnetIPRegistryProxy.getAddress());
        await subnetIPRegistry.initialize(owner, paymentToken, owner, purchaseFee);

        await paymentToken.connect(user).approve(subnetIPRegistry.getAddress(), ethers.parseEther("1000"));
    });

    it("should initialize correctly", async function () {
        expect(await subnetIPRegistry.paymentToken()).to.equal(await paymentToken.getAddress());
        expect(await subnetIPRegistry.treasury()).to.equal(owner.address);
        expect(await subnetIPRegistry.purchaseFee()).to.equal(purchaseFee);
    });

    it("should allow purchasing an IP in the 10.x.x.x range", async function () {
        await expect(subnetIPRegistry.connect(user).purchase(user.address))
            .to.emit(subnetIPRegistry, "Transfer") // ERC721 Transfer event
            .withArgs(ethers.ZeroAddress, user.address, 0x0A000001); // First IP: 10.0.0.1

        expect(await subnetIPRegistry.ownerOf(0x0A000001)).to.equal(user.address);
    });

    it("should increment IPs automatically", async function () {
        // First purchase
        await subnetIPRegistry.connect(user).purchase(user.address);
        expect(await subnetIPRegistry.ownerOf(0x0A000001)).to.equal(user.address);

        // Second purchase
        await subnetIPRegistry.connect(user).purchase(user.address);
        expect(await subnetIPRegistry.ownerOf(0x0A000002)).to.equal(user.address);
    });

    it("should transfer the purchase fee to the treasury", async function () {
        const treasuryBalanceBefore = await paymentToken.balanceOf(owner.address);
        await subnetIPRegistry.connect(user).purchase(user.address);
        const treasuryBalanceAfter = await paymentToken.balanceOf(owner.address);

        expect(treasuryBalanceAfter - treasuryBalanceBefore).to.equal(purchaseFee);
    });

    it("should allow binding a peer ID to an owned IP", async function () {
        const peerId = "peer1";
        await subnetIPRegistry.connect(user).purchase(user.address);

        await expect(subnetIPRegistry.connect(user).bindPeer(0x0A000001, peerId))
            .to.emit(subnetIPRegistry, "PeerBound")
            .withArgs(0x0A000001, peerId);

        expect(await subnetIPRegistry.getPeer(0x0A000001)).to.equal(peerId);
    });

    it("should reject binding a peer ID to an IP not owned by the caller", async function () {
        const peerId = "peer2";
        await subnetIPRegistry.connect(user).purchase(user.address);

        await expect(subnetIPRegistry.connect(owner).bindPeer(0x0A000001, peerId))
            .to.be.revertedWith("Not authorized");
    });

    it("should allow the owner to update the treasury address", async function () {
        const newTreasury = addr1.address;

        await subnetIPRegistry.connect(owner).updateTreasury(newTreasury);

        expect(await subnetIPRegistry.treasury()).to.equal(newTreasury);
    });

    it("should reject non-owners from updating the treasury address", async function () {
        const newTreasury = addr1.address;

        await expect(subnetIPRegistry.connect(user).updateTreasury(newTreasury))
        .to.be.revertedWithCustomError(subnetIPRegistry, "OwnableUnauthorizedAccount");
    });

    it("should allow the owner to update the purchase fee", async function () {
        const newPurchaseFee = ethers.parseEther("20");

        await subnetIPRegistry.connect(owner).updatePurchaseFee(newPurchaseFee);

        expect(await subnetIPRegistry.purchaseFee()).to.equal(newPurchaseFee);
    });

    it("should reject non-owners from updating the purchase fee", async function () {
        const newPurchaseFee = ethers.parseEther("20");

        await expect(subnetIPRegistry.connect(user).updatePurchaseFee(newPurchaseFee))
            .to.be.revertedWithCustomError(subnetIPRegistry, "OwnableUnauthorizedAccount");
    });
});

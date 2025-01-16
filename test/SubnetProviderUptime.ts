import { ethers } from 'hardhat';
import { expect } from 'chai';
import { SubnetProviderUptime, SubnetProvider, ERC20Mock } from '../typechain-types';
import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers';
import { StandardMerkleTree } from "@openzeppelin/merkle-tree";
import { BytesLike, Typed } from 'ethers';

describe("SubnetProviderUptime", function () {
    let subnetProviderUptime: SubnetProviderUptime;
    let subnetProvider: SubnetProvider;
    let rewardToken: ERC20Mock;
    let owner: HardhatEthersSigner, addr1: HardhatEthersSigner, addr2: HardhatEthersSigner;

    beforeEach(async function () {
        [owner, addr1, addr2] = await ethers.getSigners();

        // Deploy SubnetProvider contract
        const SubnetProviderFactory = await ethers.getContractFactory("SubnetProvider");
        subnetProvider = await SubnetProviderFactory.deploy();

        // Deploy ERC20Mock contract
        const ERC20MockFactory = await ethers.getContractFactory("ERC20Mock");
        rewardToken = await ERC20MockFactory.deploy("Reward Token", "RT");

        // Deploy SubnetProviderUptime contract
        const SubnetProviderUptimeFactory = await ethers.getContractFactory("SubnetProviderUptime");
        subnetProviderUptime = await SubnetProviderUptimeFactory.deploy(
            owner.address,
            await subnetProvider.getAddress(),
            await rewardToken.getAddress(),
            ethers.parseEther("0.01"), // Reward per second
            "verifierPeerId",
            addr1.address // Operator
        );

        // Mint and approve reward tokens
        await rewardToken.mint(owner.address, ethers.parseEther("100000"));
        await rewardToken.approve(subnetProviderUptime.getAddress(), ethers.parseEther("100000"));
        await subnetProviderUptime.depositRewards(ethers.parseEther("10000"));
    });

    it("should update the reward per second", async function () {
        const newRewardPerSecond = ethers.parseEther("0.02");

        await expect(subnetProviderUptime.updateRewardPerSecond(newRewardPerSecond))
            .to.emit(subnetProviderUptime, "RewardPerSecondUpdated")
            .withArgs(ethers.parseEther("0.01"), newRewardPerSecond);

        expect(await subnetProviderUptime.rewardPerSecond()).to.equal(newRewardPerSecond);
    });

    it("should update the Merkle root", async function () {
        const tree = StandardMerkleTree.of([
            [1, 100]
        ], ["uint256", "uint256"]);

        await expect(subnetProviderUptime.connect(addr1).updateMerkleRoot(tree.root))
            .to.emit(subnetProviderUptime, "MerkleRootUpdated")
            .withArgs(ethers.ZeroHash, tree.root);

        expect(await subnetProviderUptime.merkleRoot()).to.equal(tree.root);
    });

    it("should update the verifier peer ID", async function () {
        const newVerifierPeerId = "newVerifierPeerId";

        await expect(subnetProviderUptime.updateVerifierPeerId(newVerifierPeerId))
            .to.emit(subnetProviderUptime, "VerifierPeerIdUpdated")
            .withArgs("verifierPeerId", newVerifierPeerId);

        expect(await subnetProviderUptime.verifierPeerId()).to.equal(newVerifierPeerId);
    });

    it("should update the operator", async function () {
        const newOperator = addr2.address;

        await expect(subnetProviderUptime.updateOperator(newOperator))
            .to.emit(subnetProviderUptime, "OperatorUpdated")
            .withArgs(addr1.address, newOperator);

        expect(await subnetProviderUptime.operator()).to.equal(newOperator);
    });

    it("should report uptime and calculate pending rewards", async function () {
        await subnetProvider.registerProvider("Provider1", "Metadata1", owner.address, "https://provider1.com");

        const tree = StandardMerkleTree.of([
            [1, 100]
        ], ["uint256", "uint256"]);

        await subnetProviderUptime.connect(addr1).updateMerkleRoot(tree.root);

        const proof = tree.getProof(0);

        await subnetProviderUptime.connect(addr1).reportUptime(1, 100, proof);

        const uptime = await subnetProviderUptime.uptimes(1);
        expect(uptime.claimedUptime).to.equal(100);
        expect(uptime.pendingReward).to.equal(ethers.parseEther("1"));
    });

    it("should claim rewards successfully", async function () {
        await subnetProvider.registerProvider("Provider1", "Metadata1", owner.address, "https://provider1.com");

        const tree = StandardMerkleTree.of([
            [1, 100]
        ], ["uint256", "uint256"]);

        await subnetProviderUptime.connect(addr1).updateMerkleRoot(tree.root);

        const proof = tree.getProof(0);

        await subnetProviderUptime.connect(addr1).reportUptime(1, 100, proof);

        // Simulate 30 days passing
        await ethers.provider.send("evm_increaseTime", [30 * 24 * 60 * 60]);
        await ethers.provider.send("evm_mine", []);

        const initialBalance = await rewardToken.balanceOf(owner.address);

        await expect(subnetProviderUptime.claimReward(1))
            .to.emit(subnetProviderUptime, "RewardClaimed")
            .withArgs(1, owner.address, ethers.parseEther("1"));

        const finalBalance = await rewardToken.balanceOf(owner.address);
        expect(finalBalance - initialBalance).to.equal(ethers.parseEther("1"));
    });

    it("should revert if the claim is not yet unlocked", async function () {
        await subnetProvider.registerProvider("Provider1", "Metadata1", owner.address, "https://provider1.com");

        const tree = StandardMerkleTree.of([
            [1, 100],
            [2, 100],
            [3, 100]
        ], ["uint256", "uint256"]);

        await subnetProviderUptime.connect(addr1).updateMerkleRoot(tree.root);

        const proof = tree.getProof(0);

        await subnetProviderUptime.connect(addr1).reportUptime(1, 100, proof);

        await expect(subnetProviderUptime.claimReward(1))
            .to.be.revertedWith("Claim not yet unlocked");
    });

    it("should revert if the Merkle proof is invalid", async function () {
        await subnetProvider.registerProvider("Provider1", "Metadata1", owner.address, "https://provider1.com");

        const tree = StandardMerkleTree.of([
            [1, 100],
            [2, 100],
            [3, 100]
        ], ["uint256", "uint256"]);

        await subnetProviderUptime.connect(addr1).updateMerkleRoot(tree.root);
        const invalidProof: BytesLike[] | Typed = [];

        await expect(subnetProviderUptime.connect(addr1).reportUptime(1, 100, invalidProof))
            .to.be.revertedWith("Invalid Merkle proof");
    });

    it("should fund the contract with reward tokens", async function () {
        const amount = ethers.parseEther("100");

        await expect(subnetProviderUptime.depositRewards(amount))
            .to.emit(rewardToken, "Transfer")
            .withArgs(owner.address, subnetProviderUptime.getAddress(), amount);

        expect(await rewardToken.balanceOf(subnetProviderUptime.getAddress())).to.equal(10100000000000000000000n);
    });
});

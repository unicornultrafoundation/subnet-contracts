import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { SubnetRegistry, TestNFT } from "../typechain-types";
import { ethers } from "hardhat";
import { expect } from "chai";
import { StandardMerkleTree } from "@openzeppelin/merkle-tree";


describe("SubnetRegistry Contract", function () {
  let subnetRegistry: SubnetRegistry;
  let owner: HardhatEthersSigner, addr1: HardhatEthersSigner, addr2: HardhatEthersSigner, updater: HardhatEthersSigner;
  let nftContract: TestNFT, nftId = 1;

  beforeEach(async function () {
    [owner, addr1, addr2, updater] = await ethers.getSigners();

    // Deploy a mock NFT contract
    const MockNFT = await ethers.getContractFactory("TestNFT");
    nftContract = await MockNFT.deploy();

    // Mint an NFT to addr1
    await nftContract.mint(addr1.address, nftId);

    // Deploy the SubnetRegistry contract
    const SubnetRegistry = await ethers.getContractFactory("SubnetRegistry");

    subnetRegistry = await SubnetRegistry.deploy(
      owner.address,
      await nftContract.getAddress(),
      ethers.parseEther("0.1") // rewardPerSecond
    );
  });

  it("Should deploy correctly", async function () {
    expect(await subnetRegistry.nftContract()).to.equal(await nftContract.getAddress());
    expect(await subnetRegistry.rewardPerSecond()).to.equal(ethers.parseEther("0.1"));
  });

  it("Should register a subnet", async function () {
    await nftContract.connect(addr1).approve(await subnetRegistry.getAddress(), nftId);

    await expect(
      subnetRegistry.connect(addr1).registerSubnet(nftId, "peer1", "metadata1")
    )
      .to.emit(subnetRegistry, "SubnetRegistered")
      .withArgs(1, addr1.address, nftId, "peer1", "metadata1");

    const subnet = await subnetRegistry.getSubnet(1);
    expect(subnet.owner).to.equal(addr1.address);
    expect(subnet.nftId).to.equal(nftId);
    expect(subnet.peerAddr).to.equal("peer1");
    expect(subnet.active).to.be.true;
  });

  it("Should deregister a subnet", async function () {
    await nftContract.connect(addr1).approve(await subnetRegistry.getAddress(), nftId);
    await subnetRegistry.connect(addr1).registerSubnet(nftId, "peer1", "metadata1");

    await expect(
      subnetRegistry.connect(addr1).deregisterSubnet(1)
    )
      .to.emit(subnetRegistry, "SubnetDeregistered")
      .withArgs(1, addr1.address, "peer1", 0);

    const subnet = await subnetRegistry.getSubnet(1);
    expect(subnet.active).to.be.false;
    expect(await nftContract.ownerOf(nftId)).to.equal(addr1.address);
  });

  it("Should update reward per second", async function () {
    const newReward = ethers.parseEther("0.2");
    await expect(
      subnetRegistry.connect(owner).updateRewardPerSecond(newReward)
    )
      .to.emit(subnetRegistry, "RewardPerSecondUpdated")
      .withArgs(ethers.parseEther("0.1"), newReward);

    expect(await subnetRegistry.rewardPerSecond()).to.equal(newReward);
  });

  it("Should add and remove score updater", async function () {
    await expect(subnetRegistry.connect(owner).addScoreUpdater(updater.address))
      .to.emit(subnetRegistry, "ScoreUpdaterAdded")
      .withArgs(updater.address);

    expect(await subnetRegistry.scoreUpdaters(updater.address)).to.be.true;

    await expect(subnetRegistry.connect(owner).removeScoreUpdater(updater.address))
      .to.emit(subnetRegistry, "ScoreUpdaterRemoved")
      .withArgs(updater.address);

    expect(await subnetRegistry.scoreUpdaters(updater.address)).to.be.false;
  });

  it("Should update trust scores", async function () {
    await nftContract.connect(addr1).approve(await subnetRegistry.getAddress(), nftId);
    await subnetRegistry.connect(addr1).registerSubnet(nftId, "peer1", "metadata1");

    await subnetRegistry.connect(owner).addScoreUpdater(updater.address);

    await expect(
      subnetRegistry.connect(updater).increaseTrustScore(1, 50)
    )
      .to.emit(subnetRegistry, "TrustScoreUpdated")
      .withArgs(1, 100050);

    await expect(
      subnetRegistry.connect(updater).decreaseTrustScore(1, 30)
    )
      .to.emit(subnetRegistry, "TrustScoreUpdated")
      .withArgs(1, 100020);

    const subnet = await subnetRegistry.getSubnet(1);
    expect(subnet.trustScores).to.equal(100020);
  });

  it("Should claim rewards", async function () {
    await nftContract.connect(addr1).approve(await subnetRegistry.getAddress(), nftId);
    await subnetRegistry.connect(addr1).registerSubnet(nftId, "peer1", "metadata1");

    const tree = StandardMerkleTree.of([
        [1, 100]
    ], ["uint256", "uint256"]);

    await subnetRegistry.connect(owner).updateMerkleRoot(tree.root);

    const proof = tree.getProof(0);
    await subnetRegistry.connect(owner).deposit({ value: ethers.parseEther("10") });

    await expect(
      subnetRegistry.connect(addr1).claimReward(1, 100, proof)
    )
      .to.emit(subnetRegistry, "RewardClaimed")
      .withArgs(1, addr1.address, "peer1", ethers.parseEther("10"));
  });

  it("Should fund the contract", async function () {
    await subnetRegistry.connect(owner).deposit({ value: ethers.parseEther("1") });
    expect(await ethers.provider.getBalance(await subnetRegistry.getAddress())).to.equal(ethers.parseEther("1"));
  });

  it("Should fail if unauthorized access", async function () {
    await expect(
      subnetRegistry.connect(addr2).updateRewardPerSecond(ethers.parseEther("0.2"))
    ).to.be.revertedWithCustomError(subnetRegistry,"OwnableUnauthorizedAccount");

    await expect(
      subnetRegistry.connect(addr2).increaseTrustScore(1, 50)
    ).to.be.revertedWith("Caller is not an authorized updater");
  });
});

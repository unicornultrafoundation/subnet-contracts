import { expect } from "chai";
import { ethers } from "hardhat";
import { Contract, Signer } from "ethers";
import { SubnetNftVault, SubnetNftVaultFactory, TestNFT } from "../typechain-types";

describe("SubnetNftVault and SubnetNftVaultFactory", function () {
  let nftContract: TestNFT;
  let vaultFactory: SubnetNftVaultFactory;
  let vault: SubnetNftVault;
  let deployer: Signer;
  let user: Signer;

  beforeEach(async function () {
    [deployer, user] = await ethers.getSigners();

    // Deploy a mock ERC721 contract
    const MockNFT = await ethers.getContractFactory("TestNFT");
    nftContract = await MockNFT.deploy();

    // Deploy the SubnetNftVaultFactory
    const VaultFactory = await ethers.getContractFactory("SubnetNftVaultFactory");
    vaultFactory = await VaultFactory.deploy();

    // Deploy a vault using the factory
    const name = "VaultToken";
    const symbol = "VTKN";
    const tx = await vaultFactory.createVault(name, symbol, await nftContract.getAddress());
    const receipt = await tx.wait();
    const logs = await vaultFactory.queryFilter(vaultFactory.filters.VaultCreated(), receipt?.blockNumber, receipt?.blockNumber);
    if (logs.length === 0) throw new Error("VaultCreated event not found");
    const event = logs[0];
    if (!event) throw new Error("VaultCreated event not found");
    vault = await ethers.getContractAt("SubnetNftVault", event.args.vaultAddress);
  });

  it("should lock an NFT and mint ERC20 tokens", async function () {
    // Mint an NFT to the user
    await nftContract.connect(deployer).mint(await user.getAddress(), 1);

    // Approve the vault to transfer the NFT
    await nftContract.connect(user).approve(await vault.getAddress(), 1);

    // Lock the NFT
    await vault.connect(user).lock(1);

    // Check that the NFT is owned by the vault
    expect(await nftContract.ownerOf(1)).to.equal(await vault.getAddress());

    // Check that the user received 1 ERC20 token
    expect(await vault.balanceOf(await user.getAddress())).to.equal(ethers.parseEther("1"));

    // Check that the NFT owner is recorded
    expect(await vault.nftOwner(1)).to.equal(await user.getAddress());
  });

  it("should redeem an NFT by burning ERC20 tokens", async function () {
    // Mint and lock an NFT
    await nftContract.connect(deployer).mint(await user.getAddress(), 1);
    await nftContract.connect(user).approve(await vault.getAddress(), 1);
    await vault.connect(user).lock(1);

    // Redeem the NFT
    await vault.connect(user).redeem(1);

    // Check that the NFT is returned to the user
    expect(await nftContract.ownerOf(1)).to.equal(await user.getAddress());

    // Check that the user burned their ERC20 token
    expect(await vault.balanceOf(await user.getAddress())).to.equal(0);

    // Check that the NFT owner record is cleared
    expect(await vault.nftOwner(1)).to.equal(ethers.ZeroAddress);
  });

  it("should lock multiple NFTs and mint corresponding ERC20 tokens", async function () {
    // Mint multiple NFTs to the user
    await nftContract.connect(deployer).mint(await user.getAddress(), 1);
    await nftContract.connect(deployer).mint(await user.getAddress(), 2);

    // Approve the vault to transfer the NFTs
    await nftContract.connect(user).setApprovalForAll(await vault.getAddress(), true);

    // Lock the NFTs
    await vault.connect(user).lockBatch([1, 2]);

    // Check that the NFTs are owned by the vault
    expect(await nftContract.ownerOf(1)).to.equal(await vault.getAddress());
    expect(await nftContract.ownerOf(2)).to.equal(await vault.getAddress());

    // Check that the user received 2 ERC20 tokens
    expect(await vault.balanceOf(await user.getAddress())).to.equal(ethers.parseEther("2"));
  });

  it("should redeem multiple NFTs by burning corresponding ERC20 tokens", async function () {
    // Mint and lock multiple NFTs
    await nftContract.connect(deployer).mint(await user.getAddress(), 1);
    await nftContract.connect(deployer).mint(await user.getAddress(), 2);
    await nftContract.connect(user).setApprovalForAll(await vault.getAddress(), true);
    await vault.connect(user).lockBatch([1, 2]);

    // Redeem the NFTs
    await vault.connect(user).redeemBatch([1, 2]);

    // Check that the NFTs are returned to the user
    expect(await nftContract.ownerOf(1)).to.equal(await user.getAddress());
    expect(await nftContract.ownerOf(2)).to.equal(await user.getAddress());

    // Check that the user burned their ERC20 tokens
    expect(await vault.balanceOf(await user.getAddress())).to.equal(0);
  });

  it("should compute the correct vault address using the factory", async function () {
    const name = "NewVaultToken";
    const symbol = "NVTKN";
    const expectedAddress = await vaultFactory.computeVaultAddress(name, symbol, await nftContract.getAddress());

    const tx = await vaultFactory.createVault(name, symbol,  await nftContract.getAddress());
    const receipt = await tx.wait();
    const logs = await vaultFactory.queryFilter(vaultFactory.filters.VaultCreated(), receipt?.blockNumber, receipt?.blockNumber);
    if (logs.length == 0) throw new Error("VaultCreated event not found");

    const event = logs[0]
    expect(event.args.vaultAddress).to.equal(expectedAddress);
  });

  it("should track all created vaults", async function () {
    const vaultCount = await vaultFactory.getVaultCount();
    expect(vaultCount).to.equal(1);

    const createdVault = await vaultFactory.getVault(0);
    expect(createdVault).to.equal(await vault.getAddress());
  });
});

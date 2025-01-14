import { ethers } from 'hardhat';
import { expect } from 'chai';
import { SubnetProvider } from '../typechain-types';
import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers';

describe("SubnetProvider", function () {
    let subnetProvider: SubnetProvider;
    let owner: HardhatEthersSigner, addr1: HardhatEthersSigner, addr2: HardhatEthersSigner;

    beforeEach(async function () {
        [owner, addr1, addr2] = await ethers.getSigners();

        // Deploy SubnetProvider contract
        const SubnetProviderFactory = await ethers.getContractFactory("SubnetProvider");
        subnetProvider = await SubnetProviderFactory.deploy();
    });

    it("should register a new provider and mint an NFT", async function () {
        const providerName = "Provider1";
        const metadata = "Metadata1";

        await expect(subnetProvider.connect(addr1).registerProvider(providerName, metadata))
            .to.emit(subnetProvider, "ProviderRegistered")
            .withArgs(addr1.address, 1, providerName, metadata);

        const provider = await subnetProvider.getProvider(1);
        expect(provider.providerName).to.equal(providerName);
        expect(provider.metadata).to.equal(metadata);
        expect(provider.tokenId).to.equal(1);

        const ownerOfToken = await subnetProvider.ownerOf(1);
        expect(ownerOfToken).to.equal(addr1.address);
    });

    it("should update provider information", async function () {
        const providerName = "Provider1";
        const metadata = "Metadata1";

        await subnetProvider.connect(addr1).registerProvider(providerName, metadata);

        const newProviderName = "UpdatedProvider1";
        const newMetadata = "UpdatedMetadata1";

        await expect(subnetProvider.connect(addr1).updateProvider(1, newProviderName, newMetadata))
            .to.emit(subnetProvider, "ProviderUpdated")
            .withArgs(1, newProviderName, newMetadata);

        const provider = await subnetProvider.getProvider(1);
        expect(provider.providerName).to.equal(newProviderName);
        expect(provider.metadata).to.equal(newMetadata);
    });

    it("should delete provider information and burn the NFT", async function () {
        const providerName = "Provider1";
        const metadata = "Metadata1";

        await subnetProvider.connect(addr1).registerProvider(providerName, metadata);

        await expect(subnetProvider.connect(addr1).deleteProvider(1))
            .to.emit(subnetProvider, "ProviderDeleted")
            .withArgs(1);

        expect((await subnetProvider.getProvider(1)).providerName).to.be.eq("");

        await expect(subnetProvider.ownerOf(1)).to.be.revertedWithCustomError(subnetProvider, "ERC721NonexistentToken");
    });

    it("should revert if non-owner tries to update provider information", async function () {
        const providerName = "Provider1";
        const metadata = "Metadata1";

        await subnetProvider.connect(addr1).registerProvider(providerName, metadata);

        const newProviderName = "UpdatedProvider1";
        const newMetadata = "UpdatedMetadata1";

        await expect(subnetProvider.connect(addr2).updateProvider(1, newProviderName, newMetadata))
            .to.be.revertedWith("Not the owner of this token");
    });

    it("should revert if non-owner tries to delete provider information", async function () {
        const providerName = "Provider1";
        const metadata = "Metadata1";

        await subnetProvider.connect(addr1).registerProvider(providerName, metadata);

        await expect(subnetProvider.connect(addr2).deleteProvider(1))
            .to.be.revertedWith("Not the owner of this token");
    });
});

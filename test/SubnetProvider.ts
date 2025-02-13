import { ethers, ignition } from 'hardhat';
import { expect } from 'chai';
import { SubnetProvider } from '../typechain-types';
import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers';
import SubnetProviderModule from '../ignition/modules/SubnetProvider';

describe("SubnetProvider", function () {
    let subnetProvider: SubnetProvider;
    let owner: HardhatEthersSigner, addr1: HardhatEthersSigner, addr2: HardhatEthersSigner;

    beforeEach(async function () {
        [owner, addr1, addr2] = await ethers.getSigners();

        const { proxy} = await ignition.deploy(SubnetProviderModule);
        subnetProvider = await ethers.getContractAt("SubnetProvider", await proxy.getAddress());
        await subnetProvider.initialize();
    });

    it("should register a new provider and mint an NFT", async function () {
        const providerName = "Provider1";
        const metadata = "Metadata1";
        const operator = addr1.address;
        const website = "https://provider1.com";

        await expect(subnetProvider.connect(addr1).registerProvider(providerName, metadata, operator, website))
            .to.emit(subnetProvider, "ProviderRegistered")
            .withArgs(addr1.address, 1, providerName, metadata, operator, website);

        const provider = await subnetProvider.getProvider(1);
        expect(provider.providerName).to.equal(providerName);
        expect(provider.metadata).to.equal(metadata);
        expect(provider.operator).to.equal(operator);
        expect(provider.website).to.equal(website);
        expect(provider.tokenId).to.equal(1);

        const ownerOfToken = await subnetProvider.ownerOf(1);
        expect(ownerOfToken).to.equal(addr1.address);
    });

    it("should update provider information", async function () {
        const providerName = "Provider1";
        const metadata = "Metadata1";
        const operator = addr1.address;
        const website = "https://provider1.com";

        await subnetProvider.connect(addr1).registerProvider(providerName, metadata, operator, website);

        const newProviderName = "UpdatedProvider1";
        const newMetadata = "UpdatedMetadata1";
        const newOperator = addr2.address;
        const newWebsite = "https://updatedprovider1.com";

        await expect(subnetProvider.connect(addr1).updateProvider(1, newProviderName, newMetadata, newOperator, newWebsite))
            .to.emit(subnetProvider, "ProviderUpdated")
            .withArgs(1, newProviderName, newMetadata, newOperator, newWebsite);

        const provider = await subnetProvider.getProvider(1);
        expect(provider.providerName).to.equal(newProviderName);
        expect(provider.metadata).to.equal(newMetadata);
        expect(provider.operator).to.equal(newOperator);
        expect(provider.website).to.equal(newWebsite);
    });

    it("should delete provider information and burn the NFT", async function () {
        const providerName = "Provider1";
        const metadata = "Metadata1";
        const operator = addr1.address;
        const website = "https://provider1.com";

        await subnetProvider.connect(addr1).registerProvider(providerName, metadata, operator, website);

        await expect(subnetProvider.connect(addr1).deleteProvider(1))
            .to.emit(subnetProvider, "ProviderDeleted")
            .withArgs(1);

        expect((await subnetProvider.getProvider(1)).providerName).to.be.eq("");

        await expect(subnetProvider.ownerOf(1)).to.be.revertedWithCustomError(subnetProvider, "ERC721NonexistentToken");
    });

    it("should revert if non-owner tries to update provider information", async function () {
        const providerName = "Provider1";
        const metadata = "Metadata1";
        const operator = addr1.address;
        const website = "https://provider1.com";

        await subnetProvider.connect(addr1).registerProvider(providerName, metadata, operator, website);

        const newProviderName = "UpdatedProvider1";
        const newMetadata = "UpdatedMetadata1";
        const newOperator = addr2.address;
        const newWebsite = "https://updatedprovider1.com";

        await expect(subnetProvider.connect(addr2).updateProvider(1, newProviderName, newMetadata, newOperator, newWebsite))
            .to.be.revertedWith("Not the owner or operator of this token");
    });

    it("should revert if non-owner tries to delete provider information", async function () {
        const providerName = "Provider1";
        const metadata = "Metadata1";
        const operator = addr1.address;
        const website = "https://provider1.com";

        await subnetProvider.connect(addr1).registerProvider(providerName, metadata, operator, website);

        await expect(subnetProvider.connect(addr2).deleteProvider(1))
            .to.be.revertedWith("Not the owner of this token");
    });

    it("should update the operator of a provider", async function () {
        const providerName = "Provider1";
        const metadata = "Metadata1";
        const operator = addr1.address;
        const website = "https://provider1.com";

        await subnetProvider.connect(addr1).registerProvider(providerName, metadata, operator, website);

        const newOperator = addr2.address;

        await expect(subnetProvider.connect(addr1).updateOperator(1, newOperator))
            .to.emit(subnetProvider, "OperatorUpdated")
            .withArgs(1, newOperator);

        const provider = await subnetProvider.getProvider(1);
        expect(provider.operator).to.equal(newOperator);
    });

    it("should update the website of a provider", async function () {
        const providerName = "Provider1";
        const metadata = "Metadata1";
        const operator = addr1.address;
        const website = "https://provider1.com";

        await subnetProvider.connect(addr1).registerProvider(providerName, metadata, operator, website);

        const newWebsite = "https://updatedprovider1.com";

        await expect(subnetProvider.connect(addr1).updateWebsite(1, newWebsite))
            .to.emit(subnetProvider, "WebsiteUpdated")
            .withArgs(1, newWebsite);

        const provider = await subnetProvider.getProvider(1);
        expect(provider.website).to.equal(newWebsite);
    });

    it("should register a new peer node for a provider", async function () {
        const providerName = "Provider1";
        const metadata = "Metadata1";
        const operator = addr1.address;
        const website = "https://provider1.com";

        await subnetProvider.connect(addr1).registerProvider(providerName, metadata, operator, website);

        const peerId = "peer123";
        const peerMetadata = "PeerMetadata";

        await expect(subnetProvider.connect(addr1).registerPeerNode(1, peerId, peerMetadata))
            .to.emit(subnetProvider, "PeerNodeRegistered")
            .withArgs(1, peerId, peerMetadata);

        const peerNode = await subnetProvider.getPeerNode(1, peerId);
        expect(peerNode.isRegistered).to.equal(true);
        expect(peerNode.metadata).to.equal(peerMetadata);
    });

    it("should revert if peer node is already registered", async function () {
        const providerName = "Provider1";
        const metadata = "Metadata1";
        const operator = addr1.address;
        const website = "https://provider1.com";

        await subnetProvider.connect(addr1).registerProvider(providerName, metadata, operator, website);

        const peerId = "peer123";
        const peerMetadata = "PeerMetadata";

        await subnetProvider.connect(addr1).registerPeerNode(1, peerId, peerMetadata);

        await expect(subnetProvider.connect(addr1).registerPeerNode(1, peerId, peerMetadata))
            .to.be.revertedWith("Peer node already registered");
    });

    it("should update a peer node for a provider", async function () {
        const providerName = "Provider1";
        const metadata = "Metadata1";
        const operator = addr1.address;
        const website = "https://provider1.com";

        await subnetProvider.connect(addr1).registerProvider(providerName, metadata, operator, website);

        const peerId = "peer123";
        const peerMetadata = "PeerMetadata";

        await subnetProvider.connect(addr1).registerPeerNode(1, peerId, peerMetadata);

        const newPeerMetadata = "UpdatedPeerMetadata";

        await expect(subnetProvider.connect(addr1).updatePeerNode(1, peerId, newPeerMetadata))
            .to.emit(subnetProvider, "PeerNodeUpdated")
            .withArgs(1, peerId, newPeerMetadata);

        const peerNode = await subnetProvider.getPeerNode(1, peerId);
        expect(peerNode.isRegistered).to.equal(true);
        expect(peerNode.metadata).to.equal(newPeerMetadata);
    });

    it("should delete a peer node for a provider", async function () {
        const providerName = "Provider1";
        const metadata = "Metadata1";
        const operator = addr1.address;
        const website = "https://provider1.com";

        await subnetProvider.connect(addr1).registerProvider(providerName, metadata, operator, website);

        const peerId = "peer123";
        const peerMetadata = "PeerMetadata";

        await subnetProvider.connect(addr1).registerPeerNode(1, peerId, peerMetadata);

        await expect(subnetProvider.connect(addr1).deletePeerNode(1, peerId))
            .to.emit(subnetProvider, "PeerNodeDeleted")
            .withArgs(1, peerId);

        const peerNode = await subnetProvider.getPeerNode(1, peerId);
        expect(peerNode.isRegistered).to.equal(false);
    });
});

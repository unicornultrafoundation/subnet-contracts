import { ethers } from 'hardhat';
import { expect } from 'chai';
import { ERC20Mock, SubnetVerifier } from '../typechain-types';
import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers';

describe("SubnetVerifier", function () {
    let subnetVerifier: SubnetVerifier;
    let owner: HardhatEthersSigner, addr1: HardhatEthersSigner, addr2: HardhatEthersSigner;
    let stakingToken: ERC20Mock;

    beforeEach(async function () {
        [owner, addr1, addr2] = await ethers.getSigners();

        const MockErc20 = await ethers.getContractFactory("ERC20Mock");
        stakingToken = await MockErc20.deploy("Staking Token", "ST");
        await stakingToken.mint(owner.address, ethers.parseEther("10000"));

        const SubnetVerifierFactory = await ethers.getContractFactory("SubnetVerifier");
        subnetVerifier = await SubnetVerifierFactory.deploy();
        await subnetVerifier.initialize(owner.address, await stakingToken.getAddress(), ethers.parseEther("100"), 86400);
    });

    it("should register a new verifier", async function () {
        const peerId = "peer1";
        const name = "Verifier1";
        const website = "https://verifier1.com";
        const metadata = "metadata1";

        await stakingToken.approve(subnetVerifier.getAddress(), ethers.parseEther("100"));
        await expect(subnetVerifier.register(addr1.address, peerId, name, website, metadata))
            .to.emit(subnetVerifier, "VerifierRegistered")
            .withArgs(addr1.address, ethers.parseEther("100"), name, website, metadata);

        const verifier = await subnetVerifier.getVerifier(addr1.address);
        expect(verifier.isRegistered).to.equal(true);
        expect(verifier.peerId).to.equal(peerId);
        expect(verifier.name).to.equal(name);
        expect(verifier.website).to.equal(website);
        expect(verifier.metadata).to.equal(metadata);
    });

    it("should update the peer ID for a verifier", async function () {
        const peerId = "peer1";
        const name = "Verifier1";
        const website = "https://verifier1.com";
        const metadata = "metadata1";

        await stakingToken.approve(subnetVerifier.getAddress(), ethers.parseEther("100"));
        await subnetVerifier.register(addr1.address, peerId, name, website, metadata);

        const newPeerId = "peer2";
        await expect(subnetVerifier.updatePeerIds(addr1.address, newPeerId))
            .to.emit(subnetVerifier, "PeerIdsUpdated")
            .withArgs(addr1.address, newPeerId);

        const verifier = await subnetVerifier.getVerifier(addr1.address);
        expect(verifier.peerId).to.equal(newPeerId);
    });

    it("should update the verifier information", async function () {
        const peerId = "peer1";
        const name = "Verifier1";
        const website = "https://verifier1.com";
        const metadata = "metadata1";

        await stakingToken.approve(subnetVerifier.getAddress(), ethers.parseEther("100"));
        await subnetVerifier.register(addr1.address, peerId, name, website, metadata);

        const newName = "Verifier2";
        const newWebsite = "https://verifier2.com";
        const newMetadata = "metadata2";
        await expect(subnetVerifier.updateInfo(addr1.address, newName, newWebsite, newMetadata))
            .to.emit(subnetVerifier, "VerifierInfoUpdated")
            .withArgs(addr1.address, newName, newWebsite, newMetadata);

        const verifier = await subnetVerifier.getVerifier(addr1.address);
        expect(verifier.name).to.equal(newName);
        expect(verifier.website).to.equal(newWebsite);
        expect(verifier.metadata).to.equal(newMetadata);
    });

    it("should exit a verifier", async function () {
        const peerId = "peer1";
        const name = "Verifier1";
        const website = "https://verifier1.com";
        const metadata = "metadata1";

        await stakingToken.approve(subnetVerifier.getAddress(), ethers.parseEther("100"));
        await subnetVerifier.register(addr1.address, peerId, name, website, metadata);

        await expect(subnetVerifier.exit(addr1.address))
            .to.emit(subnetVerifier, "Exiting")

        await ethers.provider.send("evm_increaseTime", [86400]);
        await ethers.provider.send("evm_mine", []);

        await expect(subnetVerifier.exit(addr1.address))
            .to.emit(subnetVerifier, "Exited")
            .withArgs(addr1.address, ethers.parseEther("100"));

        const verifier = await subnetVerifier.getVerifier(addr1.address);
        expect(verifier.status).to.equal(3); // Status.Exited
    });

    it("should exit a verifier after being slashed", async function () {
        const peerId = "peer1";
        const name = "Verifier1";
        const website = "https://verifier1.com";
        const metadata = "metadata1";

        await stakingToken.approve(subnetVerifier.getAddress(), ethers.parseEther("100"));
        await subnetVerifier.register(addr1.address, peerId, name, website, metadata);

        await subnetVerifier.slash(addr1.address, 50);

        await expect(subnetVerifier.exit(addr1.address))
            .to.emit(subnetVerifier, "Exiting");

        await ethers.provider.send("evm_increaseTime", [86400]);
        await ethers.provider.send("evm_mine", []);

        await expect(subnetVerifier.exit(addr1.address))
            .to.emit(subnetVerifier, "Exited")
            .withArgs(addr1.address, ethers.parseEther("50")); // 50% slashed

        const verifier = await subnetVerifier.getVerifier(addr1.address);
        expect(verifier.status).to.equal(3); // Status.Exited
    });

    it("should slash a verifier", async function () {
        const peerId = "peer1";
        const name = "Verifier1";
        const website = "https://verifier1.com";
        const metadata = "metadata1";

        await stakingToken.approve(subnetVerifier.getAddress(), ethers.parseEther("100"));
        await subnetVerifier.register(addr1.address, peerId, name, website, metadata);

        await expect(subnetVerifier.slash(addr1.address, 50))
            .to.emit(subnetVerifier, "VerifierSlashed")
            .withArgs(addr1.address, 50);

        const verifier = await subnetVerifier.getVerifier(addr1.address);
        expect(verifier.slashPercentage).to.equal(50);
        expect(verifier.status).to.equal(1); // Status.Slashed
    });

    it("should slash a verifier using execute", async function () {
        const peerId = "peer1";
        const name = "Verifier1";
        const website = "https://verifier1.com";
        const metadata = "metadata1";

        await stakingToken.approve(subnetVerifier.getAddress(), ethers.parseEther("100"));
        await subnetVerifier.register(addr1.address, peerId, name, website, metadata);

        const slashData = subnetVerifier.interface.encodeFunctionData("slash", [addr1.address, 50]);

        const domain = {
            name: "SubnetVerifier",
            version: "1",
            chainId: (await ethers.provider.getNetwork()).chainId,
            verifyingContract: await subnetVerifier.getAddress(),
        };

        const types = {
            Execute: [
                { name: "target", type: "address" },
                { name: "data", type: "bytes" },
                { name: "nonce", type: "uint256" },
            ],
        };

        const value = {
            target: await subnetVerifier.getAddress(),
            data: slashData,
            nonce: await subnetVerifier.nonce(),
        };

        const signature = await addr1.signTypedData(domain, types, value);
        const signatures = [signature];

        await subnetVerifier.transferOwnership(await subnetVerifier.getAddress())

        await expect(subnetVerifier.execute(subnetVerifier.getAddress(), slashData, signatures))
            .to.emit(subnetVerifier, "VerifierSlashed")
            .withArgs(addr1.address, 50);

        const verifier = await subnetVerifier.getVerifier(addr1.address);
        expect(verifier.slashPercentage).to.equal(50);
        expect(verifier.status).to.equal(1); // Status.Slashed
    });
});

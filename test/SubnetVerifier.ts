import { ethers, ignition } from 'hardhat';
import { expect } from 'chai';
import { SubnetVerifier } from '../typechain-types';
import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers';
import SubnetVerifierModule from '../ignition/modules/SubnetVerifier';

describe("SubnetVerifier", function () {
    let subnetVerifier: SubnetVerifier;
    let owner: HardhatEthersSigner, addr1: HardhatEthersSigner, addr2: HardhatEthersSigner;

    beforeEach(async function () {
        [owner, addr1, addr2] = await ethers.getSigners();

        const { proxy } = await ignition.deploy(SubnetVerifierModule);
        subnetVerifier = await ethers.getContractAt("SubnetVerifier", await proxy.getAddress());
        await subnetVerifier.initialize(owner.address);
    });

    it("should register a new verifier", async function () {
        const peerIds = ["peer1", "peer2"];

        await expect(subnetVerifier.registerVerifier(addr1.address, peerIds))
            .to.emit(subnetVerifier, "VerifierRegistered")
            .withArgs(addr1.address);

        const verifier = await subnetVerifier.getVerifierInfo(addr1.address);
        expect(verifier.isRegistered).to.equal(true);
        expect(verifier.peerIds).to.deep.equal(peerIds);
    });

    it("should update the peer nodes for a verifier", async function () {
        const peerIds = ["peer1", "peer2"];
        await subnetVerifier.registerVerifier(addr1.address, peerIds);

        const newPeerIds = ["peer3", "peer4"];
        await expect(subnetVerifier.connect(addr1).updateVerifierPeers(addr1.address, newPeerIds))
            .to.emit(subnetVerifier, "VerifierPeersUpdated")
            .withArgs(addr1.address, newPeerIds);

        const verifier = await subnetVerifier.getVerifierInfo(addr1.address);
        expect(verifier.peerIds).to.deep.equal(newPeerIds);
    });

    it("should delete a verifier", async function () {
        const peerIds = ["peer1", "peer2"];
        await subnetVerifier.registerVerifier(addr1.address, peerIds);

        await expect(subnetVerifier.deleteVerifier(addr1.address))
            .to.emit(subnetVerifier, "VerifierDeleted")
            .withArgs(addr1.address);

        const verifier = await subnetVerifier.getVerifierInfo(addr1.address);
        expect(verifier.isRegistered).to.equal(false);
    });

    it("should revert if non-owner tries to register a verifier", async function () {
        const peerIds = ["peer1", "peer2"];
        await expect(subnetVerifier.connect(addr1).registerVerifier(addr2.address, peerIds))
            .to.be.revertedWithCustomError(subnetVerifier, "OwnableUnauthorizedAccount");
    });

    it("should revert if non-owner tries to delete a verifier", async function () {
        const peerIds = ["peer1", "peer2"];
        await subnetVerifier.registerVerifier(addr1.address, peerIds);

        await expect(subnetVerifier.connect(addr1).deleteVerifier(addr1.address))
            .to.be.revertedWithCustomError(subnetVerifier, "OwnableUnauthorizedAccount");
    });

    it("should revert if non-owner tries to update peer nodes for a verifier", async function () {
        const peerIds = ["peer1", "peer2"];
        await subnetVerifier.registerVerifier(addr1.address, peerIds);

        const newPeerIds = ["peer3", "peer4"];
        await expect(subnetVerifier.connect(addr2).updateVerifierPeers(addr1.address, newPeerIds))
            .to.be.revertedWith("Only the verifier or owner can update peers");
    });
});

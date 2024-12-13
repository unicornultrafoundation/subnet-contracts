import { ethers } from 'hardhat'

async function main() {
    const [owner] = await ethers.getSigners();

    const nft = await ethers.getContractAt("TestNFT", "0x9CEb5fBb9734aC71F365d7cc0EedA48bB9763891");
    //await nft.mint(owner.address, 2)
    //await nft.approve("0x227e43cf2bb30e1ae11122cc8f02d66796bde321", 2)

    // Replace with your compiled contract name
    const subnetNftVaultFactory = await ethers.getContractAt("SubnetNftVault", "0x227e43cf2bb30e1ae11122cc8f02d66796bde321");

    const tx = await subnetNftVaultFactory.lock(2)
    await tx.wait();

    console.log("Vault locked successfully!");
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });

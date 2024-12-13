import { ethers } from 'hardhat'

async function main() {
    //const [owner] = await ethers.getSigners();

    // const nft = await ethers.getContractAt("TestNFT", "0x9CEb5fBb9734aC71F365d7cc0EedA48bB9763891");
    // await nft.mint(owner.address, 1)
    // await nft.approve("0xA69e8B32E1B508aa79ada9d3bd34607fF6bE74aA", 1)

    // Replace with your compiled contract name
    const subnetNftVaultFactory = await ethers.getContractAt("SubnetNftVaultFactory", "0xA69e8B32E1B508aa79ada9d3bd34607fF6bE74aA");

    const tx = await subnetNftVaultFactory.createVault(
        "Subnet Node Nft License Vault",
        "SNLV",
        "0x9CEb5fBb9734aC71F365d7cc0EedA48bB9763891"
    )

    await tx.wait();

    console.log("Vault created successfully!");
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });

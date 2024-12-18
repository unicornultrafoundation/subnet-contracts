import { ethers } from 'hardhat'

async function main() {
    const [owner] = await ethers.getSigners();

    //const nft = await ethers.getContractAt("TestNFT", "0x9CEb5fBb9734aC71F365d7cc0EedA48bB9763891");
    //await nft.mint(owner.address, 1)
    //await nft.approve("0x857C4FB4d4195A24ce78E840b01261C5F9d8c9BF", 1)

    // Replace with your compiled contract name
    const subnetStakingPoolFactory = await ethers.getContractAt("SubnetStakingPoolFactory", "0x8B2d79D0be52C7B96247fe97a1aA938D57a3A107");

    const tx = await subnetStakingPoolFactory.createPool(
        "0xc3108100a10c0d92bd36e8f779c899a6b9e87c30",
        "0x0000000000000000000000000000000000000000",
        10000000000000n,
        1733997601n,
        1765533601n
    )

    await tx.wait();
    console.log("Staking Pool created successfully!");
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });

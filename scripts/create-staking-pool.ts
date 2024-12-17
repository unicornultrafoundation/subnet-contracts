import { ethers } from 'hardhat'

async function main() {
    const [owner] = await ethers.getSigners();

    //const nft = await ethers.getContractAt("TestNFT", "0x9CEb5fBb9734aC71F365d7cc0EedA48bB9763891");
    //await nft.mint(owner.address, 1)
    //await nft.approve("0x857C4FB4d4195A24ce78E840b01261C5F9d8c9BF", 1)

    // Replace with your compiled contract name
    const subnetStakingPoolFactory = await ethers.getContractAt("SubnetStakingPoolFactory", "0xF1229Ed597B2E8f68D42452B01C4E69a2649F78C");

    const tx = await subnetStakingPoolFactory.createPool(
        "0xb40cfa4ab51a3f61920815ddd4977428933a5487",
        "0xC5f15624b4256C1206e4BB93f2CCc9163A75b703",
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

import { ethers } from 'hardhat'

async function main() {
    const [owner] = await ethers.getSigners();

    //const nft = await ethers.getContractAt("TestNFT", "0x9CEb5fBb9734aC71F365d7cc0EedA48bB9763891");
    //await nft.mint(owner.address, 1)
    //await nft.approve("0x857C4FB4d4195A24ce78E840b01261C5F9d8c9BF", 1)

    // Replace with your compiled contract name
    const subnetStakingPoolFactory = await ethers.getContractAt("SubnetStakingPoolFactory", "0xaDD9cF84389087cd366EbA7a54703a902Ca72863");

    const tx = await subnetStakingPoolFactory.createPool(
        "0x227e43cf2bb30e1ae11122cc8f02d66796bde321",
        "0xC5f15624b4256C1206e4BB93f2CCc9163A75b703",
        1000000000000000n,
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

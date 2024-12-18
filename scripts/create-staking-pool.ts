import { ethers } from 'hardhat'

async function main() {
    const [owner] = await ethers.getSigners();

    //const nft = await ethers.getContractAt("TestNFT", "0x9CEb5fBb9734aC71F365d7cc0EedA48bB9763891");
    //await nft.mint(owner.address, 1)
    //await nft.approve("0x857C4FB4d4195A24ce78E840b01261C5F9d8c9BF", 1)

    // Replace with your compiled contract name
    const subnetStakingPoolFactory = await ethers.getContractAt("SubnetStakingPoolFactory", "0x180A9CecB99c555b879B02AACFfD8799E8D59293");

    const tx = await subnetStakingPoolFactory.createPool(
        "0xc3108100a10c0d92bd36e8f779c899a6b9e87c30",
        "0x0000000000000000000000000000000000000000",
        231481000000000n,
        1734509135n,
        1735689599n
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

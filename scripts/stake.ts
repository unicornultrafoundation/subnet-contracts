import { ethers } from 'hardhat'

async function main() {
    const [owner] = await ethers.getSigners();

    // Replace with your compiled contract name
    const vault = await ethers.getContractAt("SubnetNftVault", "0x227e43cf2bb30e1ae11122cc8f02d66796bde321");

    const pool = await ethers.getContractAt("SubnetStakingPool", "0x3dfac9f4f00b767c7670d8d250c15dc462156d7a");

    let tx  = await vault.approve(await pool.getAddress(), 100000000n)
    await tx.wait();

    tx = await pool.stake(100000000n)
    await tx.wait();
    console.log("Pool staked successfully!");

    tx = await pool.claimReward()
    await tx.wait();

    tx = await pool.withdraw(100000000n)
    await tx.wait();
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });

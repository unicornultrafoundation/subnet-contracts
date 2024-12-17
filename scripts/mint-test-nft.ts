import { ethers } from 'hardhat'

async function main() {
    const [owner] = await ethers.getSigners();

    
    const nft = await ethers.getContractAt("TestNFT", "0x9CEb5fBb9734aC71F365d7cc0EedA48bB9763891");
    for (let i  = 1030; i < 1040; i ++) {
        const tx = await nft.mint("0x3c28139470241CeCA6ec803851eBD513b00C13Df", i)
        await tx.wait();
        console.log(i)
    }

    for (let i  = 1040; i < 1050; i ++) {
        const tx = await nft.mint("0xc0E9B65CB944874546Ec3eC15e6a2949b8a57201", i)
        await tx.wait();
        console.log(i)
    }

    for (let i  = 1050; i < 1060; i ++) {
        const tx = await nft.mint("0x7Ba391144C044Eafa392FAbef3cdf6e28B2DE60d", i)
        await tx.wait();
        console.log(i)
    }

    for (let i  = 1060; i < 1070; i ++) {
        const tx = await nft.mint("0xB4A9cAB492C74A6e1C2503A3577b51d3856F8a8C", i)
        await tx.wait();
        console.log(i)
    }

    for (let i  = 1080; i < 1090; i ++) {
        const tx = await nft.mint("0x8cb3C64E938065b1Ab4b137dB2b0e9953f66c3Eb", i)
        await tx.wait();
        console.log(i)
    }
    console.log("Staking Pool created successfully!");
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });

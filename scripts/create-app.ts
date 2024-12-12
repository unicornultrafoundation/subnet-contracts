import { ethers } from 'hardhat'

async function main() {
    const [owner] = await ethers.getSigners();

    const nft = await ethers.getContractAt("TestNFT", "0x9CEb5fBb9734aC71F365d7cc0EedA48bB9763891");
    //await nft.mint(owner.address, 1)
    //await nft.approve("0x857C4FB4d4195A24ce78E840b01261C5F9d8c9BF", 1)

    // Replace with your compiled contract name
    const subnetRegistry = await ethers.getContractAt("SubnetRegistry", "0x857C4FB4d4195A24ce78E840b01261C5F9d8c9BF");

    // Create a subnet
    // console.log("Creating a subnet...");
    // const subnetTx = await subnetRegistry.registerSubnet(
    //     1n,
    //     "12D3KooWGNQYBFWmKgiAgEsQ4u2WznEgR2NmrBbYcfq33yQo4D8a",
    //     "Node1",
    //     ""
    // );
    // await subnetTx.wait();
    // console.log("Subnet created successfully!");

    const subnetAppRegistry = await ethers.getContractAt("SubnetAppRegistry", "0x4c1c54b9D8a5937C7b72C7e9773e687A787Ba202");

    // Create an application
    console.log("Creating an app...");
    const appTx = await subnetAppRegistry.createApp(
        "App1",                      // name
        "APP1",                      // symbol
        "12D3KooWGNQYBFWmKgiAgEsQ4u2WznEgR2NmrBbYcfq33yQo4D8a",                   // peerId
        ethers.parseEther("1000.0"), // budget (1 ETH in wei)
        1000,                          // maxNodes
        4,                           // minCpu
        1,                           // minGpu
        8,                           // minMemory (GB)
        50,                          // minUploadBandwidth (Mbps)
        50,                          // minDownloadBandwidth (Mbps)
        ethers.parseEther("0.01"), // pricePerCpu
        ethers.parseEther("0.02"), // pricePerGpu
        ethers.parseEther("0.005"), // pricePerMemoryGB
        ethers.parseEther("0.001"), // pricePerStorageGB
        ethers.parseEther("0.0001"), // pricePerBandwidthGB
        "ewogICAgImFwcEluZm8iOiB7CgkJCSJuYW1lIjogIk15QXBwIiwKCQkJImRlc2NyaXB0aW9uIjogIlRoaXMgaXMgYSBzYW1wbGUgZGVjZW50cmFsaXplZCBhcHBsaWNhdGlvbi4iLAoJCQkibG9nbyI6ICJodHRwczovL2V4YW1wbGUuY29tL2xvZ28ucG5nIiwKCQkJIndlYnNpdGUiOiAiaHR0cHM6Ly9leGFtcGxlLmNvbSIKCQl9LAoJCSJjb250YWluZXJDb25maWciOiB7CgkJCSJpbWFnZSI6ICJuZ2lueDpsYXRlc3QiCgkJfSwKCQkiY29udGFjdEluZm8iOiB7CgkJCSJlbWFpbCI6ICJzdXBwb3J0QGV4YW1wbGUuY29tIiwKCQkJImdpdGh1YiI6ICJodHRwczovL2dpdGh1Yi5jb20vbXlhcHAiCgkJfQp9"            // metadata
    , { value: ethers.parseEther("1000.0")});
    await appTx.wait();
    console.log("App created successfully!");
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });

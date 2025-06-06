import { ethers, ignition } from 'hardhat';
import { expect } from 'chai';
import { SubnetDeployment, SubnetAppStore, ERC20Mock } from '../typechain-types';
import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers';
import SubnetProviderModule from '../ignition/modules/SubnetProvider';
import SubnetAppStoreModule from '../ignition/modules/SubnetAppStoreV2';
import SubnetDeploymentModule from '../ignition/modules/SubnetDeployment';

describe("SubnetDeployment", function () {
  let subnetDeployment: SubnetDeployment;
  let subnetAppStore: SubnetAppStore;
  let rewardToken: ERC20Mock;
  let owner: HardhatEthersSigner, appOwner: HardhatEthersSigner, operator: HardhatEthersSigner, treasury: HardhatEthersSigner, nonOwner: HardhatEthersSigner, verifier: HardhatEthersSigner;

  const dockerConfig = '{"image":"nginx:latest","ports":["80:80"],"environment":{"NODE_ENV":"production"}}';
  const appId = 1;
  const nodeIp = 12345678; // Numeric representation of IP for simplicity

  beforeEach(async function () {
    [owner, appOwner, operator, treasury, nonOwner, verifier] = await ethers.getSigners();

    // Setup the ERC20 token
    const MockErc20 = await ethers.getContractFactory("ERC20Mock");
    rewardToken = await MockErc20.deploy("Reward Token", "RT");
    await rewardToken.mint(appOwner.address, ethers.parseEther("100"));

    // Deploy and set up SubnetProvider
    const { proxy: subnetProviderProxy } = await ignition.deploy(SubnetProviderModule);
    const subnetProvider = await ethers.getContractAt("SubnetProvider", await subnetProviderProxy.getAddress());
    await subnetProvider.initialize(verifier.address);
    
    // Register a provider
    await subnetProvider.registerProvider("Provider1", "metadata", owner.address, "https://provider1.com");
    
    // Deploy and set up SubnetAppStore
    const { proxy: subnetAppStoreProxy } = await ignition.deploy(SubnetAppStoreModule);
    subnetAppStore = await ethers.getContractAt("SubnetAppStore", await subnetAppStoreProxy.getAddress());
    await subnetAppStore.initialize(
      await subnetProvider.getAddress(), 
      owner.address, 
      treasury.address, 
      50, 
      30 * 24 * 60 * 60
    );

    // Deploy SubnetDeployment
    const { proxy: subnetDeploymentProxy } = await ignition.deploy(SubnetDeploymentModule);
    subnetDeployment = await ethers.getContractAt("SubnetDeployment", await subnetDeploymentProxy.getAddress());
    await subnetDeployment.initialize(await subnetAppStore.getAddress());

    // Create an app in the SubnetAppStore
    await rewardToken.connect(appOwner).approve(subnetAppStore.getAddress(), ethers.parseEther("10"));
    await subnetAppStore.connect(appOwner).createApp(
      "TestApp", 
      "TAPP", 
      ["peer123"], 
      ethers.parseEther("10"), // budget
      ethers.parseEther("0.00001"), // pricePerCpu
      ethers.parseEther("0.00001"), // pricePerGpu
      ethers.parseEther("0.00001"), // pricePerMemoryGB
      ethers.parseEther("0.00001"), // pricePerStorageGB
      ethers.parseEther("0.00001"), // pricePerBandwidthGB
      "metadata", 
      operator.address, 
      verifier.address, 
      await rewardToken.getAddress()
    );
  });

  describe("Deployment Management", function () {
    it("should allow app owner to deploy a subnet", async function () {
      await expect(
        subnetDeployment.connect(appOwner).deploySubnet(appId, nodeIp, dockerConfig)
      )
        .to.emit(subnetDeployment, "SubnetDeployed")
        .withArgs(appId, nodeIp, appOwner.address);

      const deployment = await subnetDeployment.getDeployment(appId, nodeIp);
      expect(deployment.dockerConfig).to.equal(dockerConfig);
      expect(deployment.owner).to.equal(appOwner.address);
    });

    it("should not allow non-owner to deploy a subnet", async function () {
      await expect(
        subnetDeployment.connect(nonOwner).deploySubnet(appId, nodeIp, dockerConfig)
      ).to.be.revertedWith("Only app owner can deploy subnets");
    });

    it("should allow deployment owner to update docker config", async function () {
      await subnetDeployment.connect(appOwner).deploySubnet(appId, nodeIp, dockerConfig);
      
      const updatedDockerConfig = '{"image":"nginx:1.19","ports":["80:80","443:443"]}';
      
      await expect(
        subnetDeployment.connect(appOwner).updateDeployment(appId, nodeIp, updatedDockerConfig)
      )
        .to.emit(subnetDeployment, "SubnetDeploymentUpdated")
        .withArgs(appId, nodeIp, updatedDockerConfig);
      
      const deployment = await subnetDeployment.getDeployment(appId, nodeIp);
      expect(deployment.dockerConfig).to.equal(updatedDockerConfig);
    });

    it("should not allow non-owner to update docker config", async function () {
      await subnetDeployment.connect(appOwner).deploySubnet(appId, nodeIp, dockerConfig);
      
      const updatedDockerConfig = '{"image":"nginx:1.19","ports":["80:80","443:443"]}';
      
      await expect(
        subnetDeployment.connect(nonOwner).updateDeployment(appId, nodeIp, updatedDockerConfig)
      ).to.be.revertedWith("Only deployment owner can update");
    });

    it("should allow deployment owner to delete a deployment", async function () {
      await subnetDeployment.connect(appOwner).deploySubnet(appId, nodeIp, dockerConfig);
      
      await expect(
        subnetDeployment.connect(appOwner).deleteDeployment(appId, nodeIp)
      )
        .to.emit(subnetDeployment, "SubnetDeploymentDeleted")
        .withArgs(appId, nodeIp, appOwner.address);
      
      const exists = await subnetDeployment.deploymentExists(appId, nodeIp);
      expect(exists).to.be.false;
    });

    it("should not allow non-owner to delete a deployment", async function () {
      await subnetDeployment.connect(appOwner).deploySubnet(appId, nodeIp, dockerConfig);
      
      await expect(
        subnetDeployment.connect(nonOwner).deleteDeployment(appId, nodeIp)
      ).to.be.revertedWith("Only deployment owner can delete");
    });

    it("should handle batch deletion correctly", async function () {
      // Deploy multiple subnets
      const nodeIp1 = 11111111;
      const nodeIp2 = 22222222;
      const nodeIp3 = 33333333;
      
      await subnetDeployment.connect(appOwner).deploySubnet(appId, nodeIp1, dockerConfig);
      await subnetDeployment.connect(appOwner).deploySubnet(appId, nodeIp2, dockerConfig);
      await subnetDeployment.connect(appOwner).deploySubnet(appId, nodeIp3, dockerConfig);
      
      // Batch delete
      await subnetDeployment.connect(appOwner).batchDeleteDeployments(appId, [nodeIp1, nodeIp2, nodeIp3]);
      
      // Verify all are deleted
      expect(await subnetDeployment.deploymentExists(appId, nodeIp1)).to.be.false;
      expect(await subnetDeployment.deploymentExists(appId, nodeIp2)).to.be.false;
      expect(await subnetDeployment.deploymentExists(appId, nodeIp3)).to.be.false;
    });
  });

  describe("Deployment Queries", function () {
    beforeEach(async function () {
      await subnetDeployment.connect(appOwner).deploySubnet(appId, nodeIp, dockerConfig);
    });

    it("should correctly report if a deployment exists", async function () {
      expect(await subnetDeployment.deploymentExists(appId, nodeIp)).to.be.true;
      expect(await subnetDeployment.deploymentExists(appId, 99999)).to.be.false;
    });

    it("should retrieve correct deployment information", async function () {
      const deployment = await subnetDeployment.getDeployment(appId, nodeIp);
      expect(deployment.dockerConfig).to.equal(dockerConfig);
      expect(deployment.owner).to.equal(appOwner.address);
    });
  });

  describe("Edge Cases", function () {
    it("should handle deployments for different apps correctly", async function () {
      // Create a second app
      await rewardToken.mint(nonOwner.address, ethers.parseEther("10"));
      await rewardToken.connect(nonOwner).approve(subnetAppStore.getAddress(), ethers.parseEther("10"));
      
      await subnetAppStore.connect(nonOwner).createApp(
        "SecondApp", 
        "SAPP", 
        ["peer456"], 
        ethers.parseEther("5"), 
        ethers.parseEther("0.00001"),
        ethers.parseEther("0.00001"),
        ethers.parseEther("0.00001"),
        ethers.parseEther("0.00001"),
        ethers.parseEther("0.00001"),
        "metadata2", 
        operator.address, 
        verifier.address, 
        await rewardToken.getAddress()
      );
      
      const secondAppId = 2;
      
      // Deploy to both apps with same node IP
      await subnetDeployment.connect(appOwner).deploySubnet(appId, nodeIp, dockerConfig);
      await subnetDeployment.connect(nonOwner).deploySubnet(secondAppId, nodeIp, dockerConfig);
      
      // Verify correct ownership
      const deployment1 = await subnetDeployment.getDeployment(appId, nodeIp);
      const deployment2 = await subnetDeployment.getDeployment(secondAppId, nodeIp);
      
      expect(deployment1.owner).to.equal(appOwner.address);
      expect(deployment2.owner).to.equal(nonOwner.address);
    });

    it("should handle deletion of non-existent deployment gracefully", async function () {
      // Try to delete a deployment that doesn't exist
      await expect(
        subnetDeployment.connect(appOwner).deleteDeployment(999, 999)
      ).to.be.revertedWith("Only deployment owner can delete");
    });

    it("should allow redeploying after deletion", async function () {
      // Deploy, delete, and redeploy
      await subnetDeployment.connect(appOwner).deploySubnet(appId, nodeIp, dockerConfig);
      await subnetDeployment.connect(appOwner).deleteDeployment(appId, nodeIp);
      
      const newDockerConfig = '{"image":"redis:latest","ports":["6379:6379"]}';
      
      await expect(
        subnetDeployment.connect(appOwner).deploySubnet(appId, nodeIp, newDockerConfig)
      ).to.emit(subnetDeployment, "SubnetDeployed");
      
      const deployment = await subnetDeployment.getDeployment(appId, nodeIp);
      expect(deployment.dockerConfig).to.equal(newDockerConfig);
    });
  });
});

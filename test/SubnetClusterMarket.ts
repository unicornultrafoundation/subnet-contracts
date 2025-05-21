import { ethers, ignition } from "hardhat";
import { expect } from "chai";
import { ERC20, ERC20Mock, SubnetClusterMarket } from '../typechain-types';
import SubnetClusterMarketModule from '../ignition/modules/SubnetClusterMarket';


describe("SubnetClusterMarket", function () {
    let clusterMarket: SubnetClusterMarket;
    let owner: any, operator: any, user: any, user2: any, token: ERC20Mock;

    beforeEach(async function () {
        [owner, operator, user, user2] = await ethers.getSigners();

        // Deploy mock ERC20 token
        const ERC20Mock = await ethers.getContractFactory("ERC20Mock");
        token = await ERC20Mock.deploy("MockToken", "MTK");
        await token.mint(user.address, ethers.parseEther("1000"));
        await token.mint(user2.address, ethers.parseEther("1000"));

         // Deploy subnetClusterMarketProxy contract
        const { proxy: subnetClusterMarketProxy } = await ignition.deploy(SubnetClusterMarketModule);
        clusterMarket = await ethers.getContractAt("SubnetClusterMarket", await subnetClusterMarketProxy.getAddress());

        await clusterMarket.initialize(owner, operator, 1, 1, 1, 1, 1);
        await clusterMarket.setOperator(operator);
        await clusterMarket.setPaymentToken(await token.getAddress());

        // Set resource price
        await clusterMarket.setResourcePrice(1, 1, 1, 1, 1);
    });


    it("should create a new order and confirm it", async function () {
        await token.connect(user).approve(await clusterMarket.getAddress(), ethers.parseEther("1000"));
        await clusterMarket.connect(user).createOrder(1, 2, 3, 4, 5, 6, 10);

        const order = await clusterMarket.orders(1);
        expect(order.user).to.equal(user.address);
        expect(order.status).to.equal(0); // Pending

        // Confirm order
        await clusterMarket.connect(owner).confirmOrder(1, [111, 222], 999);
        const cluster = await clusterMarket.getCluster(1);
        expect(cluster.active).to.equal(true);
        expect(cluster.renter).to.equal(user.address);
        expect(cluster.nodeIps.length).to.equal(2);
    });

    it("should allow user to scale cluster", async function () {
        await token.connect(user).approve(clusterMarket.getAddress(), ethers.parseEther("1000"));
        await clusterMarket.connect(user).createOrder(1, 2, 3, 4, 5, 6, 10);
        await clusterMarket.connect(owner).confirmOrder(1, [111], 999);

        await clusterMarket.connect(user).scale(1, 1, 1, 1, 1, 1);
        const orderId = await clusterMarket.nextOrderId() - 1n;
        await clusterMarket.connect(owner).confirmScaleOrder(orderId);

        const cluster = await clusterMarket.getCluster(1);
        expect(cluster.gpu).to.equal(2 + 1);
        expect(cluster.cpu).to.equal(3 + 1);
    });

    it("should allow user to cancel pending order and refund", async function () {
        await token.connect(user).approve(clusterMarket.getAddress(), ethers.parseEther("1000"));
        await clusterMarket.connect(user).createOrder(1, 2, 3, 4, 5, 6, 10);

        const beforeBalance = await token.balanceOf(user.address);
        await expect(clusterMarket.connect(user).cancelOrder(1))
            .to.emit(clusterMarket, "OrderCanceled");
        const afterBalance = await token.balanceOf(user.address);
        expect(afterBalance).to.be.gt(beforeBalance);
    });

    it("should mark expired clusters as inactive", async function () {
        await token.connect(user).approve(clusterMarket.getAddress(), ethers.parseEther("1000"));
        await clusterMarket.connect(user).createOrder(1, 2, 3, 4, 5, 6, 1);
        await clusterMarket.connect(owner).confirmOrder(1, [111], 999);

        // Increase time to expire cluster
        await ethers.provider.send("evm_increaseTime", [2]);
        await ethers.provider.send("evm_mine", []);

        await clusterMarket.inactiveExpiredClusters([1]);
        const cluster = await clusterMarket.clusters(1);
        expect(cluster.active).to.equal(false);
    });

    it("should allow recreate cluster by owner or operator", async function () {
        await token.connect(user).approve(clusterMarket.getAddress(), ethers.parseEther("1000"));
        await clusterMarket.connect(user).createOrder(1, 2, 3, 4, 5, 6, 1);
        await clusterMarket.connect(owner).confirmOrder(1, [111], 999);

        // Recreate by owner
        await expect(clusterMarket.connect(owner).recreateCluster(1, [222]))
            .to.emit(clusterMarket, "ClusterNodesAdded");
        const cluster = await clusterMarket.getCluster(1);
        expect(cluster.active).to.equal(true);
        expect(cluster.nodeIps[0]).to.equal(222);
    });

    it("should not allow non-owner/operator to recreate cluster", async function () {
        await token.connect(user).approve(clusterMarket.getAddress(), ethers.parseEther("1000"));
        await clusterMarket.connect(user).createOrder(1, 2, 3, 4, 5, 6, 1);
        await clusterMarket.connect(owner).confirmOrder(1, [111], 999);

        // Expire and inactive
        await ethers.provider.send("evm_increaseTime", [2]);
        await ethers.provider.send("evm_mine", []);
        await clusterMarket.inactiveExpiredClusters([1]);

        await expect(clusterMarket.connect(user2).recreateCluster(1, [333]))
            .to.be.revertedWith("Not authorized");
    });

    it("should check areNodesInAnySameCluster returns true only for active clusters", async function () {
        await token.connect(user).approve(clusterMarket.getAddress(), ethers.parseEther("1000"));
        await clusterMarket.connect(user).createOrder(1, 2, 3, 4, 5, 6, 1);
        await clusterMarket.connect(owner).confirmOrder(1, [111, 222], 999);

        let same = await clusterMarket.areNodesInAnySameCluster(111, 222);
        expect(same).to.equal(true);

        // Expire and inactive
        await ethers.provider.send("evm_increaseTime", [2]);
        await ethers.provider.send("evm_mine", []);
        await clusterMarket.inactiveExpiredClusters([0]);

        same = await clusterMarket.areNodesInAnySameCluster(111, 222);
        expect(same).to.equal(false);
    });
});

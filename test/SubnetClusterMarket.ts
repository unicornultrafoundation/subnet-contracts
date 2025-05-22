import { ethers, ignition } from "hardhat";
import { expect } from "chai";
import { ERC20, ERC20Mock, SubnetClusterMarket } from '../typechain-types';
import SubnetClusterMarketModule from '../ignition/modules/SubnetClusterMarket';
import { time } from "@nomicfoundation/hardhat-network-helpers";


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
        // price = (2+3+4+5+6)*10 = 20*10 = 200
        await clusterMarket.connect(user).createOrder(1, 2, 3, 4, 5, 6, 10, 200n);

        const order = await clusterMarket.orders(1);
        expect(order.user).to.equal(user.address);
        expect(order.status).to.equal(0); // Pending

        // Confirm order (price param is ignored in contract, but keep for signature)
        await clusterMarket.connect(owner).confirmOrder(1, [111, 222]);
        const cluster = await clusterMarket.getCluster(1);
        expect(cluster.active).to.equal(true);
        expect(cluster.renter).to.equal(user.address);
        expect(cluster.nodeIps.length).to.equal(2);
    });

    it("should allow user to scale cluster", async function () {
        await token.connect(user).approve(clusterMarket.getAddress(), ethers.parseEther("1000"));
        await clusterMarket.connect(user).createOrder(1, 2, 3, 4, 5, 6, 10, 200n);
        await clusterMarket.connect(owner).confirmOrder(1, [111]);

        // scale: price = (1+1+1+1+1)*(expiration-now) = 5*10 = 50
        await clusterMarket.connect(user).scale(1, 1, 1, 1, 1, 1, 60n);
        const orderId = await clusterMarket.nextOrderId() - 1n;
        await clusterMarket.connect(owner).confirmScaleOrder(orderId);

        const cluster = await clusterMarket.getCluster(1);
        expect(cluster.gpu).to.equal(2 + 1);
        expect(cluster.cpu).to.equal(3 + 1);
    });

    it("should allow user to cancel pending order and refund", async function () {
        await token.connect(user).approve(clusterMarket.getAddress(), ethers.parseEther("1000"));
        await clusterMarket.connect(user).createOrder(1, 2, 3, 4, 5, 6, 10, 200n);

        const beforeBalance = await token.balanceOf(user.address);
        await expect(clusterMarket.connect(user).cancelOrder(1))
            .to.emit(clusterMarket, "OrderCanceled");
        const afterBalance = await token.balanceOf(user.address);
        expect(afterBalance).to.be.gt(beforeBalance);
    });

    it("should mark expired clusters as inactive", async function () {
        await token.connect(user).approve(clusterMarket.getAddress(), ethers.parseEther("1000"));
        await clusterMarket.connect(user).createOrder(1, 2, 3, 4, 5, 6, 1, 20n);
        await clusterMarket.connect(owner).confirmOrder(1, [111]);

        // Increase time to expire cluster
        await ethers.provider.send("evm_increaseTime", [2]);
        await ethers.provider.send("evm_mine", []);

        await clusterMarket.inactiveExpiredClusters([1]);
        const cluster = await clusterMarket.clusters(1);
        expect(cluster.active).to.equal(false);
    });

    it("should allow recreate cluster by owner or operator", async function () {
        await token.connect(user).approve(clusterMarket.getAddress(), ethers.parseEther("1000"));
        await clusterMarket.connect(user).createOrder(1, 2, 3, 4, 5, 6, 1, 20n);
        await clusterMarket.connect(owner).confirmOrder(1, [111]);

        // Recreate by owner
        await expect(clusterMarket.connect(owner).recreateCluster(1, [222]))
            .to.emit(clusterMarket, "ClusterNodesAdded");
        const cluster = await clusterMarket.getCluster(1);
        expect(cluster.active).to.equal(true);
        expect(cluster.nodeIps[0]).to.equal(222);
    });

    it("should not allow non-owner/operator to recreate cluster", async function () {
        await token.connect(user).approve(clusterMarket.getAddress(), ethers.parseEther("1000"));
        await clusterMarket.connect(user).createOrder(1, 2, 3, 4, 5, 6, 1, 20n);
        await clusterMarket.connect(owner).confirmOrder(1, [111]);

        // Expire and inactive
        await ethers.provider.send("evm_increaseTime", [2]);
        await ethers.provider.send("evm_mine", []);
        await clusterMarket.inactiveExpiredClusters([1]);

        await expect(clusterMarket.connect(user2).recreateCluster(1, [333]))
            .to.be.revertedWith("Not authorized");
    });

    it("should check areNodesInAnySameCluster returns true only for active clusters", async function () {
        await token.connect(user).approve(clusterMarket.getAddress(), ethers.parseEther("1000"));
        await clusterMarket.connect(user).createOrder(1, 2, 3, 4, 5, 6, 1, 20n);
        await clusterMarket.connect(owner).confirmOrder(1, [111, 222]);

        let same = await clusterMarket.areNodesInAnySameCluster(111, 222);
        expect(same).to.equal(true);

        // Expire and inactive
        await ethers.provider.send("evm_increaseTime", [2]);
        await ethers.provider.send("evm_mine", []);
        await clusterMarket.inactiveExpiredClusters([0]);

        same = await clusterMarket.areNodesInAnySameCluster(111, 222);
        expect(same).to.equal(false);
    });

    it("should allow owner to set operator", async function () {
        await clusterMarket.setOperator(user.address);
        expect(await clusterMarket.operator()).to.equal(user.address);
    });

    it("should allow owner to set resource price", async function () {
        await clusterMarket.setResourcePrice(2, 3, 4, 5, 6);
        const price = await clusterMarket.resourcePrice();
        expect(price.gpu).to.equal(2);
        expect(price.cpu).to.equal(3);
        expect(price.memoryBytes).to.equal(4);
        expect(price.disk).to.equal(5);
        expect(price.network).to.equal(6);
    });

    it("should allow owner to set payment token", async function () {
        const ERC20Mock = await ethers.getContractFactory("ERC20Mock");
        const newToken = await ERC20Mock.deploy("NewToken", "NTK");
        await clusterMarket.setPaymentToken(await newToken.getAddress());
        expect(await clusterMarket.paymentToken()).to.equal(await newToken.getAddress());
    });

    it("should allow owner to add discount and get discount percent", async function () {
        await clusterMarket.addDiscount(100, 10);
        await clusterMarket.addDiscount(200, 20);
        expect(await clusterMarket.getDiscountPercent(50)).to.equal(0);
        expect(await clusterMarket.getDiscountPercent(100)).to.equal(10);
        expect(await clusterMarket.getDiscountPercent(200)).to.equal(20);
        expect(await clusterMarket.getDiscountPercent(300)).to.equal(20);
    });

    it("should allow owner to add nodes to cluster", async function () {
        await token.connect(user).approve(await clusterMarket.getAddress(), ethers.parseEther("1000"));
        await clusterMarket.connect(user).createOrder(1, 2, 3, 4, 5, 6, 10, 200n);
        await clusterMarket.connect(owner).confirmOrder(1, [111]);

        await expect(clusterMarket.addNodesToCluster(1, [222, 333]))
            .to.emit(clusterMarket, "ClusterNodesAdded");
        const cluster = await clusterMarket.getCluster(1);
        expect(cluster.nodeIps.length).to.equal(3);
        expect(cluster.nodeIps[1]).to.equal(222);
        expect(cluster.nodeIps[2]).to.equal(333);
    });

    it("should allow owner to remove node from cluster", async function () {
        await token.connect(user).approve(await clusterMarket.getAddress(), ethers.parseEther("1000"));
        await clusterMarket.connect(user).createOrder(1, 2, 3, 4, 5, 6, 10, 200n);
        await clusterMarket.connect(owner).confirmOrder(1, [111, 222]);

        await expect(clusterMarket.removeNodeFromCluster(1, 222))
            .to.emit(clusterMarket, "ClusterNodeRemoved");
        const cluster = await clusterMarket.getCluster(1);
        expect(cluster.nodeIps.length).to.equal(1);
        expect(cluster.nodeIps[0]).to.equal(111);
    });

    it("should allow owner to remove multiple nodes from cluster", async function () {
        await token.connect(user).approve(await clusterMarket.getAddress(), ethers.parseEther("1000"));
        await clusterMarket.connect(user).createOrder(1, 2, 3, 4, 5, 6, 10, 200n);
        await clusterMarket.connect(owner).confirmOrder(1, [111, 222, 333]);

        await expect(clusterMarket.removeNodesFromCluster(1, [222, 333]))
            .to.not.be.reverted;
        const cluster = await clusterMarket.getCluster(1);
        expect(cluster.nodeIps.length).to.equal(1);
        expect(cluster.nodeIps[0]).to.equal(111);
    });

    it("should return correct clusters for a node ip", async function () {
        await token.connect(user).approve(await clusterMarket.getAddress(), ethers.parseEther("1000"));
        await clusterMarket.connect(user).createOrder(1, 2, 3, 4, 5, 6, 10, 200n);
        await clusterMarket.connect(owner).confirmOrder(1, [111, 222]);

        const clustersFor111 = await clusterMarket.getClustersOfNode(111);
        expect(clustersFor111).to.include(1n);
        const clustersFor222 = await clusterMarket.getClustersOfNode(222);
        expect(clustersFor222).to.include(1n);
    });

    it("should allow owner to update cluster ip if not expired", async function () {
        await token.connect(user).approve(await clusterMarket.getAddress(), ethers.parseEther("1000"));
        await clusterMarket.connect(user).createOrder(1, 2, 3, 4, 5, 6, 10, 200n);
        await clusterMarket.connect(owner).confirmOrder(1, [111, 222]);

        await clusterMarket.connect(owner).updateClusterIp(1, 333);
        const cluster = await clusterMarket.getCluster(1);
        expect(cluster.ip).to.equal(333);
    });

    it("should return cluster info from getCluster", async function () {
        await token.connect(user).approve(await clusterMarket.getAddress(), ethers.parseEther("1000"));
        await clusterMarket.connect(user).createOrder(1, 2, 3, 4, 5, 6, 10, 200n);
        await clusterMarket.connect(owner).confirmOrder(1, [111, 222]);

        const cluster = await clusterMarket.getCluster(1);
        expect(cluster.owner).to.equal(owner.address);
        expect(cluster.renter).to.equal(user.address);
        expect(cluster.nodeIps.length).to.equal(2);
        expect(cluster.active).to.equal(true);
    });

    it("should revert if order price is changed before user confirms", async function () {
        await token.connect(user).approve(await clusterMarket.getAddress(), ethers.parseEther("1000"));
        // Set resource price to 1 for all, so price = (2+3+4+5+6)*10 = 20*10 = 200
        // Now, user expects price 200, but owner changes price before order
        await clusterMarket.setResourcePrice(2, 3, 4, 5, 6); // price will be higher now

        // Try to create order with old expected price (should revert)
        await expect(
            clusterMarket.connect(user).createOrder(1, 2, 3, 4, 5, 6, 10, 200n)
        ).to.be.revertedWith("Price changed, please retry");
    });

    it("should allow order if expected price matches calculated price", async function () {
        await token.connect(user).approve(await clusterMarket.getAddress(), ethers.parseEther("1000"));
        // Set resource price to 1 for all, so price = (2+3+4+5+6)*10 = 20*10 = 200
        await clusterMarket.setResourcePrice(1, 1, 1, 1, 1);
        await expect(
            clusterMarket.connect(user).createOrder(1, 2, 3, 4, 5, 6, 10, 200n)
        ).to.not.be.reverted;
    });
});

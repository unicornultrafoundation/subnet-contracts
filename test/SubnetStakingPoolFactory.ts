import { expect } from "chai";
import { ethers } from "hardhat";
import { Signer } from "ethers";
import {
  SubnetStakingPoolFactory,
  ERC20Mock,
} from "../typechain-types";

describe("SubnetStakingPoolFactory", () => {
  let owner: Signer;
  let user: Signer;
  let user1: Signer;
  let user2: Signer;
  let stakingToken: ERC20Mock;
  let rewardToken: ERC20Mock;
  let factory: SubnetStakingPoolFactory;
  let startTime: number, endTime: number;

  beforeEach(async () => {
    [owner, user, user1, user2] = await ethers.getSigners();

    // Deploy mock ERC20 tokens for staking and rewards
    const ERC20Mock = await ethers.getContractFactory("ERC20Mock");
    stakingToken = await ERC20Mock.deploy("Staking Token", "STK");
    rewardToken = await ERC20Mock.deploy("Reward Token", "RWD");

    // Mint tokens to owner and user for testing
    await stakingToken.mint(await owner.getAddress(), ethers.parseEther("1000"));
    await stakingToken.mint(await user.getAddress(), ethers.parseEther("1000"));
    await stakingToken.mint(await user1.getAddress(), ethers.parseEther("1000"));
    await stakingToken.mint(await user2.getAddress(), ethers.parseEther("1000"));

    await rewardToken.mint(await owner.getAddress(), ethers.parseEther("100000"));

    // Deploy the factory
    const Factory = await ethers.getContractFactory("SubnetStakingPoolFactory");
    factory = await Factory.deploy(await owner.getAddress());

    // Set start and end times
    startTime = (await ethers.provider.getBlock("latest"))!.timestamp + 10; // Starts in 10 seconds
    endTime = startTime + 100; // Ends after 100 seconds

  });

  it("should deploy a new pool with correct parameters", async () => {
    const rewardRatePerSecond = ethers.parseEther("1");
    const startTime = (await ethers.provider.getBlock("latest"))!.timestamp + 60; // 1 minute from now
    const endTime = startTime + 3600; // 1 hour duration

    const tx = await factory.createPool(
      await stakingToken.getAddress(),
      await rewardToken.getAddress(),
      rewardRatePerSecond,
      startTime,
      endTime
    );
    const receipt = await tx.wait();
    const logs = await factory.queryFilter(factory.filters.PoolCreated(), receipt!.blockNumber, receipt!.blockNumber);
    const event = logs[0];
    expect(event).to.exist;

    const poolAddress = event?.args?.poolAddress;
    expect(poolAddress).to.not.be.undefined;

    const pool = await ethers.getContractAt("SubnetStakingPool", poolAddress);

    expect(await pool.stakingToken()).to.equal(await stakingToken.getAddress());
    expect(await pool.rewardToken()).to.equal(await rewardToken.getAddress());
    expect(await pool.rewardRatePerSecond()).to.equal(rewardRatePerSecond);
  });

  it("should correctly store deployed pools in the factory", async () => {
    const rewardRatePerSecond = ethers.parseEther("1");
    const startTime = (await ethers.provider.getBlock("latest"))!.timestamp + 60;
    const endTime = startTime + 3600;

    await factory.createPool(
      await stakingToken.getAddress(),
      await rewardToken.getAddress(),
      rewardRatePerSecond,
      startTime,
      endTime
    );

    const poolCount = await factory.getPoolCount();
    expect(poolCount).to.equal(1);

    const poolAddress = await factory.getPool(0);
    expect(poolAddress).to.not.be.undefined;
  });

  it("should revert if end time is before start time", async () => {
    const rewardRatePerSecond = ethers.parseEther("1");
    const startTime = (await ethers.provider.getBlock("latest"))!.timestamp + 60;
    const endTime = startTime - 10;

    await expect(
      factory.createPool(
        await stakingToken.getAddress(),
        await rewardToken.getAddress(),
        rewardRatePerSecond,
        startTime,
        endTime
      )
    ).to.be.rejectedWith("End time must be after start time");
  });

  it("should allow staking and reward claiming in deployed pool", async () => {
    const rewardRatePerSecond = ethers.parseEther("0.001");
    const startTime = (await ethers.provider.getBlock("latest"))!.timestamp + 1; // Starts immediately
    const endTime = startTime + 3700; // 1 hour duration

    const tx = await factory.createPool(
      stakingToken.getAddress(),
      rewardToken.getAddress(),
      rewardRatePerSecond,
      startTime,
      endTime
    );
    const receipt = await tx.wait();
    const logs = await factory.queryFilter(factory.filters.PoolCreated(), receipt!.blockNumber, receipt!.blockNumber);

    const poolAddress = logs[0].args?.poolAddress;
    const pool = await ethers.getContractAt("SubnetStakingPool", poolAddress);

    await rewardToken.transfer(poolAddress, ethers.parseEther("1000"))

    const userAddress = await user.getAddress();

    // Approve and stake tokens
    const stakeAmount = ethers.parseEther("10");
    await stakingToken.connect(user).approve(await pool.getAddress(), stakeAmount);
    await pool.connect(user).stake(stakeAmount);

    expect(await pool.totalStaked()).to.equal(stakeAmount);
    expect(await pool.userStaked(userAddress)).to.equal(stakeAmount);

    // Fast forward time
    await ethers.provider.send("evm_increaseTime", [3600]);
    await ethers.provider.send("evm_mine", []);

    // Claim rewards
    const rewardBalanceBefore = await rewardToken.balanceOf(userAddress);
    await pool.connect(user).claimReward();
    let rewardBalanceAfter = await rewardToken.balanceOf(userAddress);
    expect(rewardBalanceAfter).to.be.eq(ethers.parseEther("3.601"));
    expect(rewardBalanceAfter).to.be.gt(rewardBalanceBefore);

    // Fast forward time
    await ethers.provider.send("evm_increaseTime", [1000]);
    await ethers.provider.send("evm_mine", []);

    await pool.connect(user).claimReward();
    rewardBalanceAfter = await rewardToken.balanceOf(userAddress);
    expect(rewardBalanceAfter).to.be.eq(ethers.parseEther("3.697"));

     // Fast forward time
     await ethers.provider.send("evm_increaseTime", [1000]);
     await ethers.provider.send("evm_mine", []);

    await expect(pool.connect(user).claimReward()).to.be.revertedWith("No rewards to claim")
  });

  it("should distribute rewards equally among 3 users staking equally", async () => {
    const rewardRatePerSecond = ethers.parseEther("1"); // 1 tokens per second
    const startTime = (await ethers.provider.getBlock("latest"))!.timestamp + 1;
    const endTime = startTime + 3600;

    const tx = await factory.createPool(
      await stakingToken.getAddress(),
      await rewardToken.getAddress(),
      rewardRatePerSecond,
      startTime,
      endTime
    );
    const receipt = await tx.wait();
    const logs = await factory.queryFilter(factory.filters.PoolCreated(), receipt!.blockNumber, receipt!.blockNumber);

    const poolAddress = logs[0].args?.poolAddress;
    await rewardToken.transfer(poolAddress, ethers.parseEther("20000"))

    const pool = await ethers.getContractAt("SubnetStakingPool", poolAddress);

    const stakeAmount = ethers.parseEther("10");

    // User1 stakes
    await stakingToken.connect(user).approve(await pool.getAddress(), stakeAmount);
    await pool.connect(user).stake(stakeAmount);

    // User2 stakes
    await stakingToken.connect(user1).approve(await pool.getAddress(), stakeAmount);
    await pool.connect(user1).stake(stakeAmount);

    // User3 stakes
    await stakingToken.connect(user2).approve(await pool.getAddress(), stakeAmount);
    await pool.connect(user2).stake(stakeAmount);

    expect(await pool.totalStaked()).to.equal(ethers.parseEther("30"));

    // Fast forward time
    await ethers.provider.send("evm_increaseTime", [3600]);
    await ethers.provider.send("evm_mine", []);

    // User1 claims rewards
    const rewardBalanceBefore1 = await rewardToken.balanceOf(await user.getAddress());
    await pool.connect(user).claimReward();
    const rewardBalanceAfter1 = await rewardToken.balanceOf(await user.getAddress());

    // User2 claims rewards
    const rewardBalanceBefore2 = await rewardToken.balanceOf(await user1.getAddress());
    await pool.connect(user1).claimReward();
    const rewardBalanceAfter2 = await rewardToken.balanceOf(await user1.getAddress());

    // User3 claims rewards
    const rewardBalanceBefore3 = await rewardToken.balanceOf(await user2.getAddress());
    await pool.connect(user2).claimReward();
    const rewardBalanceAfter3 = await rewardToken.balanceOf(await user2.getAddress());

    const expectedReward = ethers.parseEther("1210")

    expect(rewardBalanceAfter1 - rewardBalanceBefore1).to.lt(expectedReward);
    expect(rewardBalanceAfter2 - rewardBalanceBefore2).to.lt(expectedReward);
    expect(rewardBalanceAfter3 - rewardBalanceBefore3).to.lt(expectedReward);
  });

  it("should allow staking and withdrawing staked tokens", async () => {
    const rewardRatePerSecond = ethers.parseEther("1");
    const startTime = (await ethers.provider.getBlock("latest"))!.timestamp + 1; // Starts immediately
    const endTime = startTime + 3600; // 1 hour duration

    const tx = await factory.createPool(
      await stakingToken.getAddress(),
      await rewardToken.getAddress(),
      rewardRatePerSecond,
      startTime,
      endTime
    );
    const receipt = await tx.wait();
    const logs = await factory.queryFilter(factory.filters.PoolCreated(), receipt!.blockNumber, receipt!.blockNumber);

    const poolAddress = logs[0].args?.poolAddress;
    const pool = await ethers.getContractAt("SubnetStakingPool", poolAddress);

    const userAddress1 = await user1.getAddress();

    // Approve and stake tokens
    const stakeAmount = ethers.parseEther("10");
    await stakingToken.connect(user1).approve(await pool.getAddress(), stakeAmount);
    await pool.connect(user1).stake(stakeAmount);

    expect(await pool.totalStaked()).to.equal(stakeAmount);
    expect(await pool.userStaked(userAddress1)).to.equal(stakeAmount);

    // Withdraw staked tokens
    await pool.connect(user1).withdraw(stakeAmount);

    expect(await pool.totalStaked()).to.equal(0n);
    expect(await pool.userStaked(userAddress1)).to.equal(0n);

    const stakingBalanceAfterWithdraw = await stakingToken.balanceOf(userAddress1);
    expect(stakingBalanceAfterWithdraw).to.equal(ethers.parseEther("1000")); // Original balance restored
  });

  it("should not allow staking after the end time", async function () {
    const rewardRatePerSecond = ethers.parseEther("1");
    
    const tx = await factory.createPool(
      await stakingToken.getAddress(),
      await rewardToken.getAddress(),
      rewardRatePerSecond,
      startTime,
      endTime
    );
    const receipt = await tx.wait();
    const logs = await factory.queryFilter(factory.filters.PoolCreated(), receipt!.blockNumber, receipt!.blockNumber);

    const poolAddress = logs[0].args?.poolAddress;
    const pool = await ethers.getContractAt("SubnetStakingPool", poolAddress);

    // Fast forward to after the end time
    await ethers.provider.send("evm_increaseTime", [endTime - (await ethers.provider.getBlock("latest"))!.timestamp + 1]);
    await ethers.provider.send("evm_mine");

    // Attempt to stake
    await stakingToken.connect(user).approve(await pool.getAddress(), ethers.parseUnits("10", 18));
    await expect(pool.connect(user).stake(ethers.parseUnits("10", 18))).to.be.revertedWith("Staking period ended");
  });

});

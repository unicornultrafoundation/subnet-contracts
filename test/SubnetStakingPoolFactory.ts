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

    // Set start and end times for pools
    startTime = (await ethers.provider.getBlock("latest"))!.timestamp + 10; // Starts in 10 seconds
    endTime = startTime + 100; // Ends after 100 seconds
  });

  it("should deploy a new pool with correct parameters", async () => {
    const rewardRatePerSecond = ethers.parseEther("1");
    const startTime = (await ethers.provider.getBlock("latest"))!.timestamp + 60; // Starts in 1 minute
    const endTime = startTime + 3600; // Ends in 1 hour

    // Create the staking pool
    const tx = await factory.createPool(
      await stakingToken.getAddress(),
      await rewardToken.getAddress(),
      rewardRatePerSecond,
      startTime,
      endTime
    );

    const receipt = await tx.wait();
    const logs = await factory.queryFilter(factory.filters.PoolCreated(), receipt!.blockNumber, receipt!.blockNumber);
    const poolAddress = logs[0]?.args?.poolAddress;

    expect(poolAddress).to.not.be.undefined;

    // Fetch the deployed pool and verify its configuration
    const pool = await ethers.getContractAt("SubnetStakingPool", poolAddress);
    expect(await pool.stakingToken()).to.equal(await stakingToken.getAddress());
    expect(await pool.rewardToken()).to.equal(await rewardToken.getAddress());
    expect(await pool.rewardRatePerSecond()).to.equal(rewardRatePerSecond);
  });

  it("should prevent staking after the end time", async () => {
    const rewardRatePerSecond = ethers.parseEther("1");

    // Create a staking pool
    const tx = await factory.createPool(
      await stakingToken.getAddress(),
      await rewardToken.getAddress(),
      rewardRatePerSecond,
      startTime,
      endTime
    );

    const receipt = await tx.wait();
    const logs = await factory.queryFilter(factory.filters.PoolCreated(), receipt!.blockNumber);
    const poolAddress = logs[0].args?.poolAddress;
    const pool = await ethers.getContractAt("SubnetStakingPool", poolAddress);

    // Move time beyond the staking period
    await ethers.provider.send("evm_increaseTime", [endTime - startTime + 10000]);
    await ethers.provider.send("evm_mine");

    // Attempt to stake and expect revert
    await stakingToken.connect(user).approve(poolAddress, ethers.parseEther("10"));
    await expect(pool.connect(user).stake(ethers.parseEther("10"))).to.be.revertedWith("Staking period ended");
  });

  it("should distribute rewards proportionally among multiple users", async () => {
    const rewardRatePerSecond = ethers.parseEther("0.01");
    const duration = 3600; // 1 hour
    const startTime = (await ethers.provider.getBlock("latest"))!.timestamp + 1;
    const endTime = startTime + duration;

    // Create pool
    const tx = await factory.createPool(
      await stakingToken.getAddress(),
      await rewardToken.getAddress(),
      rewardRatePerSecond,
      startTime,
      endTime
    );
    const receipt = await tx.wait();
    const logs = await factory.queryFilter(factory.filters.PoolCreated(), receipt!.blockNumber);
    const poolAddress = logs[0].args?.poolAddress;
    const pool = await ethers.getContractAt("SubnetStakingPool", poolAddress);

    // Transfer rewards to the pool
    await rewardToken.transfer(poolAddress, ethers.parseEther("5000"));

    const stakeAmount = ethers.parseEther("10");

    // Three users stake equal amounts
    for (const u of [user, user1, user2]) {
      await stakingToken.connect(u).approve(poolAddress, stakeAmount);
      await pool.connect(u).stake(stakeAmount);
    }

    // Fast forward time
    await ethers.provider.send("evm_increaseTime", [3600]);
    await ethers.provider.send("evm_mine");

    // All users claim rewards
    for (const u of [user, user1, user2]) {
      const rewardBalanceBefore = await rewardToken.balanceOf(await u.getAddress());
      await pool.connect(u).claimReward();
      const rewardBalanceAfter = await rewardToken.balanceOf(await u.getAddress());
      const earnedReward = rewardBalanceAfter - rewardBalanceBefore;

      expect(earnedReward).to.be.closeTo(ethers.parseEther("360"), ethers.parseEther("1"));
    }
  });

  it("should handle native ETH rewards when rewardToken is address(0)", async () => {
    const rewardRatePerSecond = ethers.parseEther("0.01");
    const startTime = (await ethers.provider.getBlock("latest"))!.timestamp + 1;
    const endTime = startTime + 3600;

    // Create pool with native ETH rewards
    const tx = await factory.createPool(
      await stakingToken.getAddress(),
      ethers.ZeroAddress, // Native ETH as reward
      rewardRatePerSecond,
      startTime,
      endTime
    );

    const receipt = await tx.wait();
    const logs = await factory.queryFilter(factory.filters.PoolCreated(), receipt!.blockNumber);
    const poolAddress = logs[0].args?.poolAddress;
    const pool = await ethers.getContractAt("SubnetStakingPool", poolAddress);

    // Fund the pool with ETH
    await owner.sendTransaction({ to: poolAddress, value: ethers.parseEther("5000") });

    // Stake tokens
    const stakeAmount = ethers.parseEther("10");
    await stakingToken.connect(user1).approve(poolAddress, stakeAmount);
    await pool.connect(user1).stake(stakeAmount);

    // Fast forward time
    await ethers.provider.send("evm_increaseTime", [3600]);
    await ethers.provider.send("evm_mine");

    // Claim rewards
    const balanceBefore = await ethers.provider.getBalance(await user1.getAddress());
    const txClaim = await pool.connect(user1).claimReward();
    const gasUsed = (await txClaim.wait())!.gasUsed * txClaim.gasPrice!;
    const balanceAfter = await ethers.provider.getBalance(await user1.getAddress());

    expect(balanceAfter - balanceBefore + gasUsed).to.be.closeTo(ethers.parseEther("360"), ethers.parseEther("1"));
  });

  it("should correctly update reward rate during the staking period", async () => {
    const initialRewardRate = ethers.parseEther("1");
    const updatedRewardRate = ethers.parseEther("2");

    const startTime = (await ethers.provider.getBlock("latest"))!.timestamp + 1;
    const endTime = startTime + 3600;
  
    // Create a staking pool
    const tx = await factory.createPool(
      await stakingToken.getAddress(),
      await rewardToken.getAddress(),
      initialRewardRate,
      startTime,
      endTime
    );
  
    const receipt = await tx.wait();
    const logs = await factory.queryFilter(factory.filters.PoolCreated(), receipt!.blockNumber);
    const poolAddress = logs[0].args?.poolAddress;
    const pool = await ethers.getContractAt("SubnetStakingPool", poolAddress);
  
    // Transfer rewards to the pool
    await rewardToken.transfer(poolAddress, ethers.parseEther("5000"));
  
    const stakeAmount = ethers.parseEther("1");
  
    // User stakes tokens
    await stakingToken.connect(user1).approve(poolAddress, stakeAmount);
    await pool.connect(user1).stake(stakeAmount);
  
    // Fast forward 50 seconds
    await ethers.provider.send("evm_increaseTime", [50]);
    await ethers.provider.send("evm_mine");
  
    // Update reward rate
    await expect(pool.connect(owner).updateRewardRate(updatedRewardRate))
      .to.emit(pool, "RewardRateUpdated")
      .withArgs(updatedRewardRate);
  
    // Fast forward another 50 seconds
    await ethers.provider.send("evm_increaseTime", [50]);
    await ethers.provider.send("evm_mine");
  
    // User claims rewards
    const rewardBalanceBefore = await rewardToken.balanceOf(await user1.getAddress());
    await pool.connect(user1).claimReward();
    const rewardBalanceAfter = await rewardToken.balanceOf(await user1.getAddress());
    const earnedReward = rewardBalanceAfter - rewardBalanceBefore;
  
    // Check the rewards calculation: 50 seconds at rate 1 + 50 seconds at rate 2
    const expectedReward = ethers.parseEther("150"); // 10 * 50 * 1 + 10 * 50 * 2
    expect(earnedReward).to.be.closeTo(expectedReward, ethers.parseEther("3"));
  });
  
});

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
  

  it("should allow full withdrawal of staked tokens", async () => {
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
  
    const stakeAmount = ethers.parseEther("100");
    await stakingToken.connect(user1).approve(poolAddress, stakeAmount);
    await pool.connect(user1).stake(stakeAmount);
  
    // Withdraw full amount
    const balanceBefore = await stakingToken.balanceOf(await user1.getAddress());
    await pool.connect(user1).withdraw(stakeAmount);
    const balanceAfter = await stakingToken.balanceOf(await user1.getAddress());
  
    expect(balanceAfter - balanceBefore).to.equal(stakeAmount);
  });
  
  it("should allow partial withdrawal of staked tokens", async () => {
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
  
    const stakeAmount = ethers.parseEther("100");
    const withdrawAmount = ethers.parseEther("40");
    await stakingToken.connect(user1).approve(poolAddress, stakeAmount);
    await pool.connect(user1).stake(stakeAmount);
  
    // Withdraw partial amount
    const balanceBefore = await stakingToken.balanceOf(await user1.getAddress());
    await pool.connect(user1).withdraw(withdrawAmount);
    const balanceAfter = await stakingToken.balanceOf(await user1.getAddress());
  
    expect(balanceAfter - balanceBefore).to.equal(withdrawAmount);
  
    // Ensure remaining stake is correct
    const remainingStake = await pool.userStaked(await user1.getAddress());
    expect(remainingStake).to.equal(stakeAmount - withdrawAmount);
  });
  
  it("should prevent withdrawal if user has not staked", async () => {
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
  
    // Attempt withdrawal without staking
    await expect(pool.connect(user1).withdraw(ethers.parseEther("10"))).to.be.revertedWith("Withdraw amount exceeds staked");
  });
  
  it("should allow withdrawal after the staking period has ended", async () => {
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
  
    const stakeAmount = ethers.parseEther("50");
    await stakingToken.connect(user1).approve(poolAddress, stakeAmount);
    await pool.connect(user1).stake(stakeAmount);
  
    // Fast forward to after the staking period
    await ethers.provider.send("evm_increaseTime", [duration + 10]);
    await ethers.provider.send("evm_mine");
  
    // Withdraw after the staking period
    const balanceBefore = await stakingToken.balanceOf(await user1.getAddress());
    await pool.connect(user1).withdraw(stakeAmount);
    const balanceAfter = await stakingToken.balanceOf(await user1.getAddress());
  
    expect(balanceAfter - balanceBefore).to.equal(stakeAmount);
  });
  
  it("should correctly adjust user balance and pool total balance after withdrawal", async () => {
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
  
    const stakeAmount = ethers.parseEther("100");
    const withdrawAmount = ethers.parseEther("40");
    await stakingToken.connect(user1).approve(poolAddress, stakeAmount);
    await pool.connect(user1).stake(stakeAmount);
  
    const totalBalanceBefore = await pool.userStaked(await user1.getAddress());
    await pool.connect(user1).withdraw(withdrawAmount);
    const totalBalanceAfter = await pool.userStaked(await user1.getAddress());
  
    expect(totalBalanceBefore - totalBalanceAfter).to.equal(withdrawAmount);
  
    const remainingStake = await pool.userStaked(await user1.getAddress());
    expect(remainingStake).to.equal(stakeAmount- withdrawAmount);
  });
  
  it("should allow staking during the staking period", async () => {
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
  
    const stakeAmount = ethers.parseEther("10");
  
    // Approve and stake
    await stakingToken.connect(user1).approve(poolAddress, stakeAmount);
    await pool.connect(user1).stake(stakeAmount);
  
    const stakedBalance = await pool.userStaked(await user1.getAddress());
    expect(stakedBalance).to.equal(stakeAmount);
  
    const totalStaked = await stakingToken.balanceOf(await pool.getAddress());
    expect(totalStaked).to.equal(stakeAmount);
  });
  
  it("should prevent staking before the staking period", async () => {
    const rewardRatePerSecond = ethers.parseEther("0.01");
    const startTime = (await ethers.provider.getBlock("latest"))!.timestamp + 10; // Starts in 10 seconds
    const endTime = startTime + 3600; // Ends in 1 hour
  
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
  
    const stakeAmount = ethers.parseEther("10");
  
    // Attempt staking before the staking period starts
    await stakingToken.connect(user1).approve(poolAddress, stakeAmount);
    await expect(pool.connect(user1).stake(stakeAmount)).to.be.revertedWith("Staking not started yet");
  });
  
  it("should prevent staking after the staking period has ended", async () => {
    const rewardRatePerSecond = ethers.parseEther("0.01");
    const startTime = (await ethers.provider.getBlock("latest"))!.timestamp + 1;
    const endTime = startTime + 3600; // 1 hour
  
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
  
    const stakeAmount = ethers.parseEther("10");
  
    // Fast forward time to after the staking period
    await ethers.provider.send("evm_increaseTime", [3600 + 10]);
    await ethers.provider.send("evm_mine");
  
    // Attempt staking after the staking period ends
    await stakingToken.connect(user1).approve(poolAddress, stakeAmount);
    await expect(pool.connect(user1).stake(stakeAmount)).to.be.revertedWith("Staking period ended");
  });
  
  it("should correctly update total staked amount when multiple users stake", async () => {
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
  
    const stakeAmount1 = ethers.parseEther("10");
    const stakeAmount2 = ethers.parseEther("20");
  
    // User1 stakes
    await stakingToken.connect(user1).approve(poolAddress, stakeAmount1);
    await pool.connect(user1).stake(stakeAmount1);
  
    // User2 stakes
    await stakingToken.connect(user2).approve(poolAddress, stakeAmount2);
    await pool.connect(user2).stake(stakeAmount2);
  
    // Verify total staked
    const totalStaked = await stakingToken.balanceOf(await pool.getAddress());
    expect(totalStaked).to.equal(stakeAmount1 + stakeAmount2);
  });
  
  it("should prevent staking with insufficient token allowance", async () => {
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
  
    const stakeAmount = ethers.parseEther("10");
  
    // Attempt staking without sufficient allowance
    await expect(pool.connect(user1).stake(stakeAmount)).to.be.revertedWithCustomError(stakingToken,"ERC20InsufficientAllowance");
  });
  
  it("should prevent staking with insufficient token balance", async () => {
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
  
    const stakeAmount = ethers.parseEther("100000"); // Exceeds user's balance
  
    // Approve but attempt staking more than balance
    await stakingToken.connect(user1).approve(poolAddress, stakeAmount);
    await expect(pool.connect(user1).stake(stakeAmount)).to.be.revertedWithCustomError(stakingToken, "ERC20InsufficientBalance");
  });
  it("should allow the owner to update the staking pool endTime", async () => {
    const rewardRatePerSecond = ethers.parseEther("0.01");
    const startTime = (await ethers.provider.getBlock("latest"))!.timestamp + 10; // Starts in 10 seconds
    const endTime = startTime + 3600; // 1 hour
  
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
  
    // Extend endTime by 1 hour
    const newEndTime = endTime + 3600; // Extend by 1 hour
    await expect(pool.connect(owner).updateEndTime(newEndTime))
      .to.emit(pool, "EndTimeUpdated")
      .withArgs(newEndTime);
  
    // Verify the updated endTime
    const updatedEndTime = await pool.endTime();
    expect(updatedEndTime).to.equal(newEndTime);
  });
  
  it("should prevent non-owner from updating the staking pool endTime", async () => {
    const rewardRatePerSecond = ethers.parseEther("0.01");
    const startTime = (await ethers.provider.getBlock("latest"))!.timestamp + 10; // Starts in 10 seconds
    const endTime = startTime + 3600; // 1 hour
  
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
  
    // Attempt to update endTime as a non-owner
    const newEndTime = endTime + 3600; // Extend by 1 hour
    await expect(pool.connect(user1).updateEndTime(newEndTime)).to.be.revertedWithCustomError(pool, "OwnableUnauthorizedAccount");
  });
  
  it("should prevent setting endTime in the past", async () => {
    const rewardRatePerSecond = ethers.parseEther("0.01");
    const startTime = (await ethers.provider.getBlock("latest"))!.timestamp + 10; // Starts in 10 seconds
    const endTime = startTime + 3600; // 1 hour
  
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
  
    // Attempt to set endTime in the past
    const pastEndTime = startTime - 10; // 10 seconds before startTime
    await expect(pool.connect(owner).updateEndTime(pastEndTime)).to.be.revertedWith("End time must be in the future");
  });
  
  it("should allow reducing the endTime if it is still in the future", async () => {
    const rewardRatePerSecond = ethers.parseEther("0.01");
    const startTime = (await ethers.provider.getBlock("latest"))!.timestamp + 10; // Starts in 10 seconds
    const endTime = startTime + 3600; // 1 hour
  
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
  
    // Reduce endTime to 30 minutes
    const newEndTime = startTime + 1800; // 30 minutes
    await expect(pool.connect(owner).updateEndTime(newEndTime))
      .to.emit(pool, "EndTimeUpdated")
      .withArgs(newEndTime);
  
    // Verify the updated endTime
    const updatedEndTime = await pool.endTime();
    expect(updatedEndTime).to.equal(newEndTime);
  });

  it("should allow the owner to recover native ETH if rewardToken is not native", async () => {
    // Create pool with non-native reward token
    const rewardRatePerSecond = ethers.parseEther("0.01");
    const startTime = (await ethers.provider.getBlock("latest"))!.timestamp + 1;
    const endTime = startTime + 3600;
  
    const tx = await factory.createPool(
      await stakingToken.getAddress(),
      await rewardToken.getAddress(), // Non-native reward token
      rewardRatePerSecond,
      startTime,
      endTime
    );
    const receipt = await tx.wait();
    const logs = await factory.queryFilter(factory.filters.PoolCreated(), receipt!.blockNumber);
    const poolAddress = logs[0].args?.poolAddress;
    const pool = await ethers.getContractAt("SubnetStakingPool", poolAddress);
  
    // Send native ETH to the pool contract
    const depositAmount = ethers.parseEther("1");
    await owner.sendTransaction({
      to: poolAddress,
      value: depositAmount,
    });
  
    // Check initial contract balance
    const contractBalanceBefore = await ethers.provider.getBalance(poolAddress);
    expect(contractBalanceBefore).to.equal(depositAmount);
  
    // Recover native ETH
    const ownerBalanceBefore = await ethers.provider.getBalance(await owner.getAddress());
    const recoverTx = await pool.connect(owner).recoverNative();
    const recoverReceipt = await recoverTx.wait();
  
    const gasUsed = recoverReceipt!.gasUsed - recoverTx.gasPrice!;
    const ownerBalanceAfter = await ethers.provider.getBalance(await owner.getAddress());
    const contractBalanceAfter = await ethers.provider.getBalance(poolAddress);
  
    // Verify the recovery
    expect(contractBalanceAfter).to.equal(0);
    expect(ownerBalanceAfter + gasUsed).to.be.closeTo(ownerBalanceBefore + depositAmount, ethers.parseEther("0.001"));
  });
  
  it("should revert recoverNative if rewardToken is native ETH", async () => {
    // Create pool with native ETH as reward token
    const rewardRatePerSecond = ethers.parseEther("0.01");
    const startTime = (await ethers.provider.getBlock("latest"))!.timestamp + 1;
    const endTime = startTime + 3600;
  
    const tx = await factory.createPool(
      await stakingToken.getAddress(),
      ethers.ZeroAddress, // Native ETH as reward token
      rewardRatePerSecond,
      startTime,
      endTime
    );
    const receipt = await tx.wait();
    const logs = await factory.queryFilter(factory.filters.PoolCreated(), receipt!.blockNumber);
    const poolAddress = logs[0].args?.poolAddress;
    const pool = await ethers.getContractAt("SubnetStakingPool", poolAddress);
  
    // Attempt to recover native ETH
    await expect(pool.connect(owner).recoverNative()).to.be.revertedWith("Cannot recover native ETH if reward token is native ETH");
  });
  
  it("should revert recoverNative if no ETH is available", async () => {
    // Create pool with non-native reward token
    const rewardRatePerSecond = ethers.parseEther("0.01");
    const startTime = (await ethers.provider.getBlock("latest"))!.timestamp + 1;
    const endTime = startTime + 3600;
  
    const tx = await factory.createPool(
      await stakingToken.getAddress(),
      await rewardToken.getAddress(), // Non-native reward token
      rewardRatePerSecond,
      startTime,
      endTime
    );
    const receipt = await tx.wait();
    const logs = await factory.queryFilter(factory.filters.PoolCreated(), receipt!.blockNumber);
    const poolAddress = logs[0].args?.poolAddress;
    const pool = await ethers.getContractAt("SubnetStakingPool", poolAddress);
  
    // Attempt to recover native ETH with zero balance
    await expect(pool.connect(owner).recoverNative()).to.be.revertedWith("No native Ether to recover");
  });
  
  it("should prevent non-owner from calling recoverNative", async () => {
    // Create pool with non-native reward token
    const rewardRatePerSecond = ethers.parseEther("0.01");
    const startTime = (await ethers.provider.getBlock("latest"))!.timestamp + 1;
    const endTime = startTime + 3600;
  
    const tx = await factory.createPool(
      await stakingToken.getAddress(),
      await rewardToken.getAddress(), // Non-native reward token
      rewardRatePerSecond,
      startTime,
      endTime
    );
    const receipt = await tx.wait();
    const logs = await factory.queryFilter(factory.filters.PoolCreated(), receipt!.blockNumber);
    const poolAddress = logs[0].args?.poolAddress;
    const pool = await ethers.getContractAt("SubnetStakingPool", poolAddress);
  
    // Send native ETH to the pool contract
    const depositAmount = ethers.parseEther("1");
    await owner.sendTransaction({
      to: poolAddress,
      value: depositAmount,
    });
  
    // Attempt recovery by a non-owner
    await expect(pool.connect(user1).recoverNative()).to.be.revertedWithCustomError(pool, "OwnableUnauthorizedAccount");
  });
  
  it("should allow users to claim rewards successfully during the staking period", async () => {
    const rewardRatePerSecond = ethers.parseEther("0.01"); // Reward rate
    const startTime = (await ethers.provider.getBlock("latest"))!.timestamp + 1; // Starts in 1 second
    const endTime = startTime + 3600; // Ends in 1 hour
  
    // Create staking pool
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
  
    const stakeAmount = ethers.parseEther("1");
    await stakingToken.connect(user1).approve(poolAddress, stakeAmount);
    await pool.connect(user1).stake(stakeAmount);
  
    // Fast forward 30 minutes (1800 seconds)
    await ethers.provider.send("evm_increaseTime", [1800]);
    await ethers.provider.send("evm_mine");
  
    // Claim rewards
    const rewardBalanceBefore = await rewardToken.balanceOf(await user1.getAddress());
    const txClaim = await pool.connect(user1).claimReward();
    const rewardBalanceAfter = await rewardToken.balanceOf(await user1.getAddress());
  
    // Check the rewards
    const expectedReward = rewardRatePerSecond * 1800n; // RewardRate * ElapsedTime
    const earnedReward = rewardBalanceAfter - rewardBalanceBefore;
  
    expect(earnedReward).to.be.closeTo(expectedReward, ethers.parseEther("0.1"));
  });
  
  it("should revert if there are no rewards to claim", async () => {
    const rewardRatePerSecond = ethers.parseEther("0.01");
    const startTime = (await ethers.provider.getBlock("latest"))!.timestamp + 1;
    const endTime = startTime + 3600;
    // Create staking pool
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
  
    const stakeAmount = ethers.parseEther("10");
    await stakingToken.connect(user1).approve(poolAddress, stakeAmount);
    //await pool.connect(user1).stake(stakeAmount);
    
    // Immediately claim reward without waiting
    await expect(pool.connect(user1).claimReward()).to.be.revertedWith("No rewards to claim");
  });
  
  it("should allow claiming rewards after the staking period ends", async () => {
    const rewardRatePerSecond = ethers.parseEther("0.01");
    const startTime = (await ethers.provider.getBlock("latest"))!.timestamp + 1;
    const endTime = startTime + 3600;
  
    // Create staking pool
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
  
    const stakeAmount = ethers.parseEther("1");
    await stakingToken.connect(user1).approve(poolAddress, stakeAmount);
    await pool.connect(user1).stake(stakeAmount);
  
    // Fast forward past the staking period
    await ethers.provider.send("evm_increaseTime", [3600 + 100]);
    await ethers.provider.send("evm_mine");
  
    // Claim rewards
    const rewardBalanceBefore = await rewardToken.balanceOf(await user1.getAddress());
    await pool.connect(user1).claimReward();
    const rewardBalanceAfter = await rewardToken.balanceOf(await user1.getAddress());
  
    const expectedReward = rewardRatePerSecond * 3600n; // Rewards for the entire staking period
    const earnedReward = rewardBalanceAfter - rewardBalanceBefore;
  
    expect(earnedReward).to.be.closeTo(expectedReward, ethers.parseEther("0.1"));
  });
  
});

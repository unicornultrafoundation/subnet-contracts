// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/**
 * @title SubnetStakingPool
 * @dev This contract implements a staking pool where users can stake tokens and earn rewards over time.
 * It supports configurable reward rates, staking periods, and allows the contract owner to recover tokens sent by mistake.
 */
contract SubnetStakingPool is Ownable {
    // Staking and reward tokens
    IERC20Metadata public immutable stakingToken;
    IERC20Metadata public immutable rewardToken;

    // Reward rate per second (token reward distribution rate)
    uint256 public rewardRatePerSecond;

    // Precision factor to adjust for reward token decimals (to avoid floating-point inaccuracies)
    uint256 public PRECISION_FACTOR;

    // Start and end times of the staking pool
    uint256 public startTime;
    uint256 public endTime;

    // Structure to store reward rate changes over time
    struct RewardRateSnapshot {
        uint256 time; // Time when the reward rate was updated
        uint256 rate; // New reward rate
    }

    // History of reward rate changes
    RewardRateSnapshot[] public rewardRateHistory;

    // Mappings to track user stakes, last claimed reward time, pending rewards, and snapshot index
    mapping(address => uint256) public userStaked; // Tracks amount staked by users
    mapping(address => uint256) public userLastClaimedTime; // Last time rewards were claimed
    mapping(address => uint256) public userRewards; // Accumulated rewards for users
    mapping(address => uint256) public userLastSnapshotIndex; // Last snapshot index for rewards calculation

    // Events to log important contract interactions
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 reward);
    event EndTimeUpdated(uint256 newEndTime);
    event RewardRateUpdated(uint256 newRate);

    /**
     * @dev Constructor initializes the staking pool.
     * @param initialOwner Address of the contract owner.
     * @param _stakingToken ERC20 token used for staking.
     * @param _rewardToken ERC20 token distributed as rewards.
     * @param _rewardRatePerSecond Reward rate per second.
     * @param _startTime Start time of the staking period.
     * @param _endTime End time of the staking period.
     */
    constructor(
        address initialOwner,
        IERC20Metadata _stakingToken,
        IERC20Metadata _rewardToken,
        uint256 _rewardRatePerSecond,
        uint256 _startTime,
        uint256 _endTime
    ) Ownable(initialOwner) {
        require(_startTime < _endTime, "Start time must be before end time");
        require(_rewardRatePerSecond > 0, "Reward rate must be positive");

        // Initialize staking and reward tokens
        stakingToken = _stakingToken;
        rewardToken = _rewardToken;
        startTime = _startTime;
        endTime = _endTime;
        
        rewardRatePerSecond = _rewardRatePerSecond;

        // Add initial reward rate snapshot
        rewardRateHistory.push(RewardRateSnapshot({
            time: block.timestamp,
            rate: rewardRatePerSecond
        }));

        // Calculate precision factor based on staking token's decimals
        uint256 decimalsStakingToken = uint256(stakingToken.decimals());
        PRECISION_FACTOR = uint256(10**decimalsStakingToken);
    }

    /**
     * @dev Modifier to update the rewards for a user before executing a function.
     * Updates the user's pending rewards and last claimed time.
     */
    modifier updateReward(address account) {
        if (account != address(0)) {
            userRewards[account] += _pendingReward(account);
            userLastClaimedTime[account] = block.timestamp;
            userLastSnapshotIndex[account] = rewardRateHistory.length - 1;
        }
        _;
    }

    /**
     * @dev Modifier to ensure the staking period is active.
     */
    modifier withinStakingPeriod() {
        require(block.timestamp >= startTime, "Staking not started yet");
        require(block.timestamp <= endTime, "Staking period ended");
        _;
    }

    /**
     * @dev Internal function to calculate the pending rewards for a user.
     * @param account Address of the user.
     * @return Pending reward amount.
     */
    function _pendingReward(address account) internal view returns (uint256) {
        uint256 totalReward = 0;
        uint256 staked = userStaked[account];
        uint256 lastClaimTime = userLastClaimedTime[account];
        uint256 lastSnapshotIndex = userLastSnapshotIndex[account];

        // Loop through reward rate history starting from the last snapshot index
        for (uint256 i = lastSnapshotIndex; i < rewardRateHistory.length; i++) {
            RewardRateSnapshot memory snapshot = rewardRateHistory[i];

            // Determine the effective start and end times for reward calculation
            uint256 effectiveStartTime = snapshot.time > lastClaimTime ? snapshot.time : lastClaimTime;
            effectiveStartTime = effectiveStartTime < startTime ? startTime : effectiveStartTime;

            uint256 effectiveEndTime = (i == rewardRateHistory.length - 1) ? block.timestamp : rewardRateHistory[i + 1].time;
            effectiveEndTime = effectiveEndTime > endTime ? endTime : effectiveEndTime;

            if (effectiveEndTime <= effectiveStartTime) {
                continue; // Skip if no valid time range exists
            }

            // Calculate time elapsed and rewards accrued
            uint256 timeElapsed = effectiveEndTime - effectiveStartTime;
            totalReward += (staked * snapshot.rate * timeElapsed) / PRECISION_FACTOR;
        }

        return totalReward;
    }

    /**
     * @dev View function to calculate the total earned rewards for a user.
     * @param account Address of the user.
     * @return Total earned rewards.
     */
    function earned(address account) public view returns (uint256) {
        return userRewards[account] + _pendingReward(account);
    }

    /**
     * @dev Allows users to stake tokens in the pool.
     * @param amount Amount of tokens to stake.
     */
    function stake(uint256 amount) external withinStakingPeriod updateReward(msg.sender) {
        require(amount > 0, "Cannot stake 0");

        userStaked[msg.sender] += amount;

        stakingToken.transferFrom(msg.sender, address(this), amount);

        emit Staked(msg.sender, amount);
    }

    /**
     * @dev Allows users to withdraw their staked tokens.
     * @param amount Amount of tokens to withdraw.
     */
    function withdraw(uint256 amount) external updateReward(msg.sender) {
        require(amount > 0, "Cannot withdraw 0");
        require(userStaked[msg.sender] >= amount, "Withdraw amount exceeds staked");

        userStaked[msg.sender] -= amount;

        stakingToken.transfer(msg.sender, amount);

        emit Withdrawn(msg.sender, amount);
    }

    /**
     * @dev Allows users to claim their earned rewards.
     */
    function claimReward() external updateReward(msg.sender) {
        uint256 reward = userRewards[msg.sender];
        require(reward > 0, "No rewards to claim");

        userRewards[msg.sender] = 0;

        if (address(rewardToken) == address(0)) {
            (bool success, ) = msg.sender.call{value: reward}("");
            require(success, "ETH transfer failed");
        } else {
            require(rewardToken.balanceOf(address(this)) >= reward, "Insufficient reward token balance");
            rewardToken.transfer(msg.sender, reward);
        }

        emit RewardClaimed(msg.sender, reward);
    }

    /**
     * @dev Updates the reward rate for future calculations. Only callable by the owner.
     * @param newRate New reward rate per second.
     */
    function updateRewardRate(uint256 newRate) external onlyOwner {
        require(newRate > 0, "Reward rate must be positive");
        rewardRatePerSecond = newRate;

        rewardRateHistory.push(RewardRateSnapshot({
            time: block.timestamp,
            rate: rewardRatePerSecond
        }));

        emit RewardRateUpdated(newRate);
    }

    /**
     * @dev Updates the staking end time. Only callable by the owner.
     * @param newEndTime New end time for staking.
     */
    function updateEndTime(uint256 newEndTime) external onlyOwner {
        require(newEndTime > block.timestamp, "End time must be in the future");
        require(newEndTime > startTime, "End time must be after start time");
        endTime = newEndTime;

        emit EndTimeUpdated(newEndTime);
    }

    /**
     * @dev Allows the owner to recover tokens mistakenly sent to the contract.
     * @param token Address of the token to recover.
     * @param amount Amount of tokens to recover.
     * @param to Address to send the recovered tokens to.
     */
    function recoverERC20(address token, uint256 amount, address to) external onlyOwner {
        require(token != address(stakingToken), "Cannot withdraw staking token");
        require(token != address(rewardToken), "Cannot withdraw reward token");
        require(to != address(0), "Invalid recipient address");

        IERC20(token).transfer(to, amount);
    }

    
    /**
     * @dev Allows the owner to recover native ETH from the contract.
     * Only callable if the reward token is not native ETH.
     */
    function recoverNative() external onlyOwner {
        require(address(rewardToken) != address(0), "Cannot recover native ETH if reward token is native ETH");
        uint256 balance = address(this).balance;
        require(balance > 0, "No native Ether to recover");
        payable(owner()).transfer(balance);
    }

    /**
     * @dev Fallback function to accept native ETH transfers.
     */
    receive() external payable {}

    fallback() external payable {}
}

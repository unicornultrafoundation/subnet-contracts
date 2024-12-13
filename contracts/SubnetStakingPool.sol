// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract SubnetStakingPool is Ownable {
    IERC20Metadata public immutable stakingToken;
    IERC20Metadata public immutable rewardToken; // Reward token to be distributed

    uint256 public rewardRatePerSecond; // Reward rate in tokens per second
    uint256 public totalStaked; // Total tokens staked in the pool
    uint256 public lastRewardTime; // Timestamp of the last reward update
    uint256 public rewardPerTokenStored; // Accumulated reward per token
    uint256 public PRECISION_FACTOR; // The precision factor

    uint256 public startTime; // Staking and rewards start time
    uint256 public endTime; // Staking and rewards end time

    mapping(address => uint256) public userStaked; // Staked amount per user
    mapping(address => uint256) public userRewardPerTokenPaid; // Reward debt per user
    mapping(address => uint256) public userRewards; // Rewards available for withdrawal

    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 reward);
    event RewardRateUpdated(uint256 newRate);
    event EndTimeUpdated(uint256 newEndTime);

    constructor(
        address initialOwner,
        IERC20Metadata _stakingToken,
        IERC20Metadata _rewardToken,
        uint256 _rewardRatePerSecond,
        uint256 _startTime,
        uint256 _endTime
    ) Ownable(initialOwner) {
        require(_startTime < _endTime, "Start time must be before end time");

        stakingToken = _stakingToken;
        rewardToken = _rewardToken;
        rewardRatePerSecond = _rewardRatePerSecond;
        startTime = _startTime;
        endTime = _endTime;
        lastRewardTime = _startTime;

        uint256 decimalsRewardToken = uint256(rewardToken.decimals());
        require(decimalsRewardToken < 30, "Must be inferior to 30");

        PRECISION_FACTOR = uint256(10**(uint256(30) - decimalsRewardToken));
    }

    /// @notice Updates the reward calculations for all users
    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastRewardTime = block.timestamp;

        if (account != address(0)) {
            userRewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    /// @notice Ensures the function is called within the staking period
    modifier withinStakingPeriod() {
        require(block.timestamp >= startTime, "Staking not started yet");
        require(block.timestamp <= endTime, "Staking period ended");
        _;
    }

    /// @notice Calculates the reward per token
    /// @return The reward per token scaled by 1e18
    function rewardPerToken() public view returns (uint256) {
        if (totalStaked == 0 || block.timestamp < startTime) {
            return rewardPerTokenStored;
        }

        uint256 applicableEndTime = block.timestamp > endTime ? endTime : block.timestamp;
        if (applicableEndTime <= lastRewardTime) {
            return rewardPerTokenStored;
        }

        return
            rewardPerTokenStored +
            ((applicableEndTime - lastRewardTime) * rewardRatePerSecond * PRECISION_FACTOR) / totalStaked;
    }


    /// @notice Calculates the earned rewards for a user
    /// @param account The address of the user
    /// @return The total rewards earned by the user
    function earned(address account) public view returns (uint256) {
        return
            ((userStaked[account] * (rewardPerToken() - userRewardPerTokenPaid[account])) / PRECISION_FACTOR) +
            userRewards[account];
    }

    /// @notice Allows a user to stake tokens
    /// @param amount The amount of tokens to stake
    function stake(uint256 amount) external withinStakingPeriod updateReward(msg.sender) {
        require(amount > 0, "Cannot stake 0");
        totalStaked += amount;
        userStaked[msg.sender] += amount;

        stakingToken.transferFrom(msg.sender, address(this), amount);
        emit Staked(msg.sender, amount);
    }

    /// @notice Allows a user to withdraw staked tokens
    /// @param amount The amount of tokens to withdraw
    function withdraw(uint256 amount) external updateReward(msg.sender) {
        require(amount > 0, "Cannot withdraw 0");
        require(userStaked[msg.sender] >= amount, "Withdraw amount exceeds staked");

        totalStaked -= amount;
        userStaked[msg.sender] -= amount;

        stakingToken.transfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    /// @notice Allows a user to claim their rewards
    function claimReward() external updateReward(msg.sender) {
        uint256 reward = userRewards[msg.sender];
        require(reward > 0, "No rewards to claim");
        require(
            rewardToken.balanceOf(address(this)) >= reward,
            "Insufficient reward token balance"
        );

        userRewards[msg.sender] = 0;
        rewardToken.transfer(msg.sender, reward);
        emit RewardClaimed(msg.sender, reward);
    }

        /// @notice Allows the owner to update the end time
    /// @param newEndTime The new end time for staking and rewards
    function updateEndTime(uint256 newEndTime) external onlyOwner {
        require(newEndTime > block.timestamp, "End time must be in the future");
        require(newEndTime > startTime, "End time must be after start time");
        endTime = newEndTime;
        emit EndTimeUpdated(newEndTime);
    }

    /// @notice Allows the owner to update the reward rate
    /// @param newRewardRate The new reward rate per second
    function updateRewardRate(uint256 newRewardRate) external onlyOwner updateReward(address(0)){
        require(newRewardRate > 0, "Reward rate must be greater than 0");
        rewardRatePerSecond = newRewardRate;
        emit RewardRateUpdated(newRewardRate);
    }

    /// @notice Allows the owner to withdraw tokens sent to the contract by mistake
    /// @param token The address of the token to withdraw
    /// @param amount The amount of the token to withdraw
    /// @param to The address to send the withdrawn tokens to
    function recoverERC20(
        address token,
        uint256 amount,
        address to
    ) external onlyOwner {
        require(token != address(stakingToken), "Cannot withdraw staking token");
        require(to != address(0), "Invalid recipient address");

        IERC20(token).transfer(to, amount);
    }
}

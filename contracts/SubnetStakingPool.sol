// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract SubnetStakingPool is Ownable {
    IERC20 public immutable stakingToken;
    IERC20 public immutable rewardToken; // Reward token to be distributed

    uint256 public rewardRatePerSecond; // Reward rate in tokens per second
    uint256 public totalStaked; // Total tokens staked in the pool
    uint256 public lastRewardTime; // Timestamp of the last reward update
    uint256 public rewardPerTokenStored; // Accumulated reward per token

    mapping(address => uint256) public userStaked; // Staked amount per user
    mapping(address => uint256) public userRewardPerTokenPaid; // Reward debt per user
    mapping(address => uint256) public userRewards; // Rewards available for withdrawal

    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 reward);
    event RewardRateUpdated(uint256 newRate);

    constructor(
        address initialOwner,
        IERC20 _stakingToken,
        IERC20 _rewardToken,
        uint256 _rewardRatePerSecond
    ) Ownable(initialOwner) {
        stakingToken = _stakingToken;
        rewardToken = _rewardToken;
        rewardRatePerSecond = _rewardRatePerSecond;
        lastRewardTime = block.timestamp;
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

    /// @notice Calculates the reward per token
    /// @return The reward per token scaled by 1e18
    function rewardPerToken() public view returns (uint256) {
        if (totalStaked == 0) {
            return rewardPerTokenStored;
        }
        return
            rewardPerTokenStored +
            ((block.timestamp - lastRewardTime) * rewardRatePerSecond * 1e18) / totalStaked;
    }

    /// @notice Calculates the earned rewards for a user
    /// @param account The address of the user
    /// @return The total rewards earned by the user
    function earned(address account) public view returns (uint256) {
        return
            ((userStaked[account] * (rewardPerToken() - userRewardPerTokenPaid[account])) / 1e18) +
            userRewards[account];
    }

    /// @notice Allows a user to stake tokens
    /// @param amount The amount of tokens to stake
    function stake(uint256 amount) external updateReward(msg.sender) {
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

    /// @notice Updates the reward rate per second
    /// @param newRate The new reward rate per second
    function updateRewardRate(uint256 newRate) external onlyOwner updateReward(address(0)) {
        rewardRatePerSecond = newRate;
        emit RewardRateUpdated(newRate);
    }
}

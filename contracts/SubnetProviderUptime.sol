// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./SubnetProvider.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title SubnetProviderUptime
 * @dev Contract to track the uptime of providers and distribute rewards.
 */
contract SubnetProviderUptime is Ownable {
    using SafeERC20 for IERC20;

    SubnetProvider public subnetProvider;
    IERC20 public rewardToken;
    uint256 public rewardPerSecond;
    bytes32 public merkleRoot;

    struct Uptime {
        uint256 totalUptime; // Total uptime in seconds
        uint256 lastUpdate;  // Last update timestamp
        uint256 claimedUptime; // Claimed uptime in seconds
        uint256 pendingReward; // Pending reward to be claimed
        uint256 lastClaimTime; // Last time reward was claimed
    }

    mapping(uint256 => Uptime) public uptimes;

    event UptimeUpdated(uint256 indexed tokenId, uint256 totalUptime);
    event RewardReported(uint256 indexed tokenId, uint256 pendingReward);
    event RewardClaimed(uint256 indexed tokenId, address indexed owner, uint256 amount);
    event RewardPerSecondUpdated(uint256 oldRewardPerSecond, uint256 newRewardPerSecond);
    event MerkleRootUpdated(bytes32 oldMerkleRoot, bytes32 newMerkleRoot);

    /**
     * @dev Constructor for initializing the contract.
     * @param _owner Address of the contract owner.
     * @param _subnetProvider Address of the Subnet Provider contract.
     * @param _rewardToken Address of the ERC20 token used for rewards.
     * @param _rewardPerSecond Reward amount per second of uptime.
     */
    constructor(
        address _owner,
        address _subnetProvider,
        address _rewardToken,
        uint256 _rewardPerSecond
    ) Ownable(_owner) {
        require(_subnetProvider != address(0), "Invalid SubnetProvider address");
        require(_rewardToken != address(0), "Invalid reward token address");
        require(_rewardPerSecond > 0, "Reward must be greater than zero");

        subnetProvider = SubnetProvider(_subnetProvider);
        rewardToken = IERC20(_rewardToken);
        rewardPerSecond = _rewardPerSecond;
    }

    /**
     * @dev Updates the reward per second.
     * @param _rewardPerSecond New reward amount per second.
     */
    function updateRewardPerSecond(uint256 _rewardPerSecond) external onlyOwner {
        require(_rewardPerSecond > 0, "Reward must be greater than zero");
        uint256 oldRewardPerSecond = rewardPerSecond;
        rewardPerSecond = _rewardPerSecond;

        emit RewardPerSecondUpdated(oldRewardPerSecond, _rewardPerSecond);
    }

    /**
     * @dev Updates the Merkle root for uptime validation.
     * @param _merkleRoot New Merkle root.
     */
    function updateMerkleRoot(bytes32 _merkleRoot) external onlyOwner {
        bytes32 oldMerkleRoot = merkleRoot;
        merkleRoot = _merkleRoot;

        emit MerkleRootUpdated(oldMerkleRoot, _merkleRoot);
    }

    /**
     * @dev Reports uptime and calculates pending rewards using a Merkle proof.
     * @param tokenId ID of the provider's token.
     * @param totalUptime Total uptime (in seconds) from Merkle tree.
     * @param proof Merkle proof to validate the claim.
     */
    function reportUptime(uint256 tokenId, uint256 totalUptime, bytes32[] calldata proof) external {
        Uptime storage uptime = uptimes[tokenId];
        require(totalUptime > uptime.claimedUptime, "No new uptime to report");

        // Validate Merkle proof
        bytes32 leaf = keccak256(abi.encodePacked(tokenId, totalUptime));
        require(MerkleProof.verify(proof, merkleRoot, leaf), "Invalid Merkle proof");

        uint256 newUptime = totalUptime - uptime.claimedUptime;
        uint256 reward = newUptime * rewardPerSecond;

        // Update claimed uptime and pending reward
        uptime.claimedUptime = totalUptime;
        uptime.pendingReward += reward;

        emit RewardReported(tokenId, uptime.pendingReward);
    }

    /**
     * @dev Claims pending rewards for uptime.
     * @param tokenId ID of the provider's token.
     */
    function claimReward(uint256 tokenId) external {
        require(subnetProvider.ownerOf(tokenId) == msg.sender, "Caller is not the owner of the token");

        Uptime storage uptime = uptimes[tokenId];
        uint256 reward = uptime.pendingReward;

        // Ensure 30 days have passed since the last claim
        require(block.timestamp >= uptime.lastClaimTime + 30 days, "Claim not yet unlocked");

        require(rewardToken.balanceOf(address(this)) >= reward, "Insufficient contract balance");

        // Update last claim time and reset pending reward
        uptime.lastClaimTime = block.timestamp;
        uptime.pendingReward = 0;

        // Transfer reward
        rewardToken.safeTransfer(msg.sender, reward);

        emit RewardClaimed(tokenId, msg.sender, reward);
    }

    /**
     * @dev Retrieves the total uptime for a provider.
     * @param tokenId ID of the provider's token.
     * @return Total uptime in seconds.
     */
    function getTotalUptime(uint256 tokenId) external view returns (uint256) {
        require(subnetProvider.ownerOf(tokenId) != address(0), "Provider does not exist");
        return uptimes[tokenId].totalUptime;
    }

    /**
     * @dev Fund the contract with reward tokens.
     * @param amount Amount of tokens to deposit.
     */
    function depositRewards(uint256 amount) external {
        require(amount > 0, "Must deposit tokens");
        rewardToken.safeTransferFrom(msg.sender, address(this), amount);
    }
}

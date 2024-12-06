// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

interface IERC721 {
    function transferFrom(address from, address to, uint256 tokenId) external;
    function ownerOf(uint256 tokenId) external view returns (address);
}

contract SubnetRegistry is Ownable {
    address public immutable nftContract; // Allowed NFT contract
    uint256 public rewardPerSecond; // Reward per second of uptime
    uint256 public subnetCounter; // Subnet ID counter
    bytes32 public merkleRoot; // Merkle root for uptime validation

    struct Subnet {
        uint256 nftId;
        address owner;
        string peerAddr;
        string metadata;
        uint256 startTime;
        uint256 totalUptime;
        uint256 claimedUptime;
        bool active;
        uint256 trustScores;
    }

    mapping(uint256 => Subnet) public subnets; // Mapping from subnet ID to subnet data
    mapping(string => uint256) public peerToSubnet; // Mapping from peer address to subnet ID
    // Default trust score
    uint256 public constant DEFAULT_TRUST_SCORE = 100000;
    // Mapping to track addresses with permission to update trust scores
    mapping(address => bool) public scoreUpdaters;

    // Events
    event SubnetRegistered(uint256 indexed subnetId, address indexed owner, uint256 nftId, string peerAddr, string metadata);
    event SubnetDeregistered(uint256 indexed subnetId, address indexed owner, string peerAddr, uint256 uptime);
    event RewardClaimed(uint256 indexed subnetId, address indexed owner, string peerAddr, uint256 amount);
    event RewardPerSecondUpdated(uint256 oldRewardPerSecond, uint256 newRewardPerSecond);
    // Event for trust score updates
    event TrustScoreUpdated(uint256 indexed subnetId, uint256 newScore);
    // Event emitted when an address is granted the updater role
    event ScoreUpdaterAdded(address indexed updater);
    // Event emitted when an address is revoked from the updater role
    event ScoreUpdaterRemoved(address indexed updater);

    /**
    * @dev Modifier to restrict access to authorized score updaters.
    */
    modifier onlyScoreUpdater() {
        require(scoreUpdaters[msg.sender], "Caller is not an authorized updater");
        _;
    }

    /**
     * @dev Constructor to set immutable variables.
     * @param _nftContract Address of the allowed NFT contract
     * @param _rewardPerSecond Reward amount per second of uptime
     */
    constructor(address initialOwner, address _nftContract, uint256 _rewardPerSecond) Ownable(initialOwner) {
        require(_nftContract != address(0), "Invalid NFT contract address");
        require(_rewardPerSecond > 0, "Reward must be greater than zero");
        nftContract = _nftContract;
        rewardPerSecond = _rewardPerSecond;
    }

     /**
     * @dev Update the reward per second.
     * @param _rewardPerSecond New reward amount per second
     */
    function updateRewardPerSecond(uint256 _rewardPerSecond) external onlyOwner {
        require(_rewardPerSecond > 0, "Reward must be greater than zero");
        uint256 oldRewardPerSecond = rewardPerSecond;
        rewardPerSecond = _rewardPerSecond;

        emit RewardPerSecondUpdated(oldRewardPerSecond, _rewardPerSecond);
    }

    /**
     * @dev Update the Merkle root for uptime validation.
     * @param _merkleRoot New Merkle root
     */
    function updateMerkleRoot(bytes32 _merkleRoot) external onlyOwner {
        merkleRoot = _merkleRoot;
    }

    /**
    * @dev Grants the score updater role to an address.
    * Can only be called by the contract owner.
    * @param updater The address to be granted the updater role.
    */
    function addScoreUpdater(address updater) external onlyOwner {
        require(updater != address(0), "Invalid address");
        require(!scoreUpdaters[updater], "Address is already an updater");

        scoreUpdaters[updater] = true;
        emit ScoreUpdaterAdded(updater);
    }

    /**
    * @dev Revokes the score updater role from an address.
    * Can only be called by the contract owner.
    * @param updater The address to be revoked.
    */
    function removeScoreUpdater(address updater) external onlyOwner {
        require(scoreUpdaters[updater], "Address is not an updater");

        scoreUpdaters[updater] = false;
        emit ScoreUpdaterRemoved(updater);
    }

    /**
     * @dev Register a new subnet and lock an NFT.
     * @param nftId ID of the NFT to lock
     * @param peerAddr Peer address (e.g., PeerID or multiaddress)
     * @param metadata Metadata for the subnet
     */
    function registerSubnet(uint256 nftId, string memory peerAddr, string memory metadata) external {
        require(peerToSubnet[peerAddr] == 0, "Peer address already registered");
        require(IERC721(nftContract).ownerOf(nftId) == msg.sender, "Caller is not the NFT owner");

        // Transfer the NFT to this contract
        IERC721(nftContract).transferFrom(msg.sender, address(this), nftId);

        subnetCounter++;
        subnets[subnetCounter] = Subnet({
            nftId: nftId,
            owner: msg.sender,
            peerAddr: peerAddr,
            metadata: metadata,
            startTime: block.timestamp,
            totalUptime: 0,
            claimedUptime: 0,
            active: true,
            trustScores: DEFAULT_TRUST_SCORE
        });

        peerToSubnet[peerAddr] = subnetCounter;

        emit SubnetRegistered(subnetCounter, msg.sender, nftId, peerAddr, metadata);
    }

    /**
     * @dev Deregister a subnet and unlock the NFT.
     * @param subnetId ID of the subnet to deregister
     */
    function deregisterSubnet(uint256 subnetId) external {
        Subnet storage subnet = subnets[subnetId];
        require(subnet.active, "Subnet is not active");
        require(subnet.owner == msg.sender, "Caller is not the owner");

        subnet.active = false;

        // Transfer the NFT back to the owner
        IERC721(nftContract).transferFrom(address(this), subnet.owner, subnet.nftId);

        emit SubnetDeregistered(subnetId, subnet.owner, subnet.peerAddr, subnet.totalUptime);
    }

    /**
     * @dev Claim rewards for uptime using a Merkle proof.
     * @param subnetId ID of the subnet
     * @param owner Address of the subnet owner
     * @param totalUptime Total uptime (in seconds) from Merkle tree
     * @param proof Merkle proof to validate the claim
     */
    function claimReward(uint256 subnetId, address owner, uint256 totalUptime, bytes32[] calldata proof) external {
        Subnet storage subnet = subnets[subnetId];
        require(subnet.owner == owner, "Caller is not the subnet owner");
        require(totalUptime > subnet.claimedUptime, "No new uptime to claim");

        // Validate Merkle proof
        bytes32 leaf = keccak256(abi.encodePacked(subnetId, owner, totalUptime));
        require(MerkleProof.verify(proof, merkleRoot, leaf), "Invalid Merkle proof");

        uint256 newUptime = totalUptime - subnet.claimedUptime;
        uint256 reward = newUptime * rewardPerSecond;
        require(address(this).balance >= reward, "Insufficient contract balance");

        // Update claimed uptime and transfer reward
        subnet.claimedUptime = totalUptime;
        (bool success, ) = owner.call{value: reward}("");
        require(success, "Reward transfer failed");

        emit RewardClaimed(subnetId, owner, subnet.peerAddr, reward);
    }

   /**
    * @dev Increases the trust score of a subnet.
    * Can only be called by authorized score updaters.
    * @param subnetId The ID of the subnet.
    * @param points The number of points to add to the trust score.
    */
    function increaseTrustScore(uint256 subnetId, uint256 points) external onlyScoreUpdater {
        // Fetch the subnet details
        Subnet storage subnet = subnets[subnetId];

        // Ensure the subnet exists
        require(subnet.owner != address(0), "Subnet does not exist");

        // Increment the trust score
        subnet.trustScores += points;

        // Emit an event for the updated trust score
        emit TrustScoreUpdated(subnetId, subnet.trustScores);
    }

    /**
    * @dev Decreases the trust score of a subnet.
    * Can only be called by authorized score updaters.
    * @param subnetId The ID of the subnet.
    * @param points The number of points to subtract from the trust score.
    */
    function decreaseTrustScore(uint256 subnetId, uint256 points) external onlyScoreUpdater {
        // Fetch the subnet details
        Subnet storage subnet = subnets[subnetId];

        // Ensure the subnet exists
        require(subnet.owner != address(0), "Subnet does not exist");

        // Decrease the trust score, ensuring it doesn't underflow
        subnet.trustScores = subnet.trustScores > points ? subnet.trustScores - points : 0;

        // Emit an event for the updated trust score
        emit TrustScoreUpdated(subnetId, subnet.trustScores);
    }

    /**
     * @dev Fund the contract with native tokens for rewards.
     */
    function deposit() external payable {
        require(msg.value > 0, "Must deposit tokens");
    }

    /**
     * @dev Retrieves the details of a specific subnet.
     */
    function getSubnet(uint256 subnetId) external view returns (Subnet memory) {
        // Fetch the subnet from the mapping
        Subnet memory subnet = subnets[subnetId];

        // Ensure the subnet exists
        require(subnet.owner != address(0), "Subnet does not exist");

        // Return the subnet details
        return subnet;
    }
}

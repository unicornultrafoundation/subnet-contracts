// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";

contract SubnetVerifier is Initializable, OwnableUpgradeable, EIP712Upgradeable {
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;

    // Struct to store verifier information
    struct VerifierInfo {
        address owner;
        bool isRegistered;
        uint256 stakeAmount;
        string peerId;
        string name;
        string website;
        string metadata;
        uint256 slashPercentage;
        bool isSlashed;
    }

    // Struct to store unstake request information
    struct UnstakeRequest {
        uint256 amount;
        uint256 unlockTime;
    }

    // State variables
    IERC20 public stakingToken;
    IERC20 public profitToken;
    uint256 public fixedStakeAmount;
    uint256 public unstakeLockPeriod;
    uint256 public totalStaked;
    uint256 public nonce;
    uint256 public verifierCount; // Add verifier count

    // Mappings to store various data
    mapping(address => VerifierInfo) public verifiers;
    mapping(address => uint256) public verifierRewards;
    mapping(address => mapping(address => UnstakeRequest[])) public unstakeRequests;
    mapping(bytes32 => bool) public usedHashes;
    mapping(address => uint256) public nonces;
    mapping(address => mapping(address => uint256)) public userRewardDebt;

    // Events
    event VerifierRegistered(address indexed verifier, uint256 stakeAmount, uint256 feeRate, string name, string website, string metadata);
    event Staked(address indexed user, address indexed verifier, uint256 amount);
    event UnstakeRequested(address indexed user, address indexed verifier, uint256 amount, uint256 unlockTime);
    event Unstaked(address indexed user, address indexed verifier, uint256 amount);
    event RewardWithdrawn(address indexed user, address indexed verifier, uint256 amount);
    event ProfitAdded(address indexed verifier, uint256 amount);
    event FeeRateUpdated(address indexed verifier, uint256 newFeeRate);
    event PeerIdsUpdated(address indexed verifier, string newPeerId);
    event VerifierInfoUpdated(address indexed verifier, string name, string website, string metadata);
    event VerifierSlashed(address indexed verifier, uint256 slashPercentage);
    event Executed(address indexed target, bytes data);

    // Initialize function to set initial values
    function initialize(
        address _initialOwner,
        address _stakingToken,
        uint256 _fixedStakeAmount,
        uint256 _unstakeLockPeriod
    ) external initializer {
        __Ownable_init(_initialOwner);
        __EIP712_init("SubnetVerifier", "1");
        stakingToken = IERC20(_stakingToken);
        fixedStakeAmount = _fixedStakeAmount;
        unstakeLockPeriod = _unstakeLockPeriod;
        verifierCount = 0; // Initialize verifier count
    }

    // Modifier to check if the caller is the owner of the verifier
    modifier onlyVerifierOwner(address verifier) {
        require(verifiers[verifier].owner == msg.sender, "Caller is not a registered verifier");
        _;
    }

    /**
     * @dev Registers a new verifier.
     * @param verifier The address of the verifier.
     * @param owner The owner of the verifier.
     * @param feeRate The fee rate for the verifier.
     * @param peerId The peer IDs of the verifier.
     * @param name The name of the verifier.
     * @param website The website of the verifier.
     * @param metadata Additional metadata for the verifier.
     */
    function register(
        address verifier,
        address owner,
        uint256 feeRate,
        string memory peerId,
        string memory name,
        string memory website,
        string memory metadata
    ) external {
        require(!verifiers[verifier].isRegistered, "Verifier already registered");

        // Require a fixed amount of tokens to be staked during registration
        uint256 stakeAmount = fixedStakeAmount;
        require(stakeAmount > 0, "Stake amount must be greater than 0");

        verifiers[verifier] = VerifierInfo({
            owner: owner,
            isRegistered: true,
            stakeAmount: stakeAmount,
            peerId: peerId,
            name: name,
            website: website,
            metadata: metadata,
            slashPercentage: 0,
            isSlashed: false
        });

        verifierCount++; // Increment verifier count

        emit VerifierRegistered(verifier, stakeAmount, feeRate, name, website, metadata);

        // Transfer staking tokens from the sender to the contract
        stakingToken.safeTransferFrom(msg.sender, address(this), stakeAmount);
        totalStaked += stakeAmount;

        emit Staked(msg.sender, verifier, stakeAmount);
    }

    /**
     * @dev Requests to unstake tokens for a verifier.
     * @param verifier The address of the verifier.
     * @param amount The amount of tokens to unstake.
     */
    function requestUnstake(address verifier, uint256 amount) external onlyVerifierOwner(verifier) {
        require(verifiers[verifier].stakeAmount >= amount, "Not enough staked");
        require(amount > 0, "Amount must be greater than 0");

        // Update verifier's stake amount
        verifiers[verifier].stakeAmount -= amount;
        totalStaked -= amount;

        // Create a new unstake request
        unstakeRequests[msg.sender][verifier].push(UnstakeRequest({
            amount: amount,
            unlockTime: block.timestamp + unstakeLockPeriod
        }));

        emit UnstakeRequested(msg.sender, verifier, amount, block.timestamp + unstakeLockPeriod);
    }

    /**
     * @dev Unstakes tokens after the lock period.
     * @param verifier The address of the verifier.
     */
    function unstake(address verifier) external onlyVerifierOwner(verifier) {
        // Get the unstake requests for the caller and verifier
        UnstakeRequest[] storage requests = unstakeRequests[msg.sender][verifier];
        require(requests.length > 0, "No unstake requests found");

        uint256 totalAmount = 0;
        // Iterate through the unstake requests and sum up the amounts that can be unstaked
        for (uint256 i = 0; i < requests.length; i++) {
            if (block.timestamp >= requests[i].unlockTime) {
                totalAmount += requests[i].amount;
                delete requests[i];
            }
        }

        require(totalAmount > 0, "Tokens are still locked");

        // If the verifier is slashed, apply the slash percentage
        if (verifiers[verifier].isSlashed) {
            uint256 slashedAmount = (totalAmount * verifiers[verifier].slashPercentage) / 100;
            totalAmount -= slashedAmount;
        }

        // Transfer the unstaked tokens to the verifier
        stakingToken.safeTransfer(msg.sender, totalAmount);

        emit Unstaked(msg.sender, verifier, totalAmount);
    }

    /**
     * @dev Updates the information of a verifier.
     * @param verifier The address of the verifier.
     * @param name The new name of the verifier.
     * @param website The new website of the verifier.
     * @param metadata The new metadata of the verifier.
     */
    function updateVerifierInfo(
        address verifier,
        string memory name,
        string memory website,
        string memory metadata
    ) external onlyVerifierOwner(verifier) {
        require(verifiers[verifier].isRegistered, "Verifier not registered");

        // Update the verifier's information
        verifiers[verifier].name = name;
        verifiers[verifier].website = website;
        verifiers[verifier].metadata = metadata;

        emit VerifierInfoUpdated(verifier, name, website, metadata);
    }

    /**
     * @dev Updates the peer IDs of a verifier.
     * @param verifier The address of the verifier.
     * @param newPeerId The new peer IDs of the verifier.
     */
    function updatePeerIds(address verifier, string memory newPeerId) external onlyVerifierOwner(verifier) {
        require(verifiers[verifier].isRegistered, "Verifier not registered");

        // Update the verifier's peer IDs
        verifiers[verifier].peerId = newPeerId;

        emit PeerIdsUpdated(verifier, newPeerId);
    }

    /**
     * @dev Slashes a verifier by reducing their stake.
     * @param verifier The address of the verifier.
     * @param slashPercentage The percentage of the stake to slash.
     */
    function slashVerifier(address verifier, uint256 slashPercentage) external onlyOwner {
        require(verifiers[verifier].isRegistered, "Verifier not registered");
        require(slashPercentage > 0 && slashPercentage <= 100, "Invalid slash percentage");
        require(!verifiers[verifier].isSlashed, "Verifier already slashed");

        // Update the verifier's slash percentage and mark as slashed
        verifiers[verifier].slashPercentage = slashPercentage;
        verifiers[verifier].isSlashed = true;

        verifierCount--; // Decrement verifier count

        emit VerifierSlashed(verifier, slashPercentage);
    }

    /**
     * @dev Executes a transaction with signatures from verifiers.
     * @param target The address of the target contract.
     * @param data The data to be executed.
     * @param signatures The signatures from the verifiers.
     */
    function execute(address target, bytes memory data, bytes[] memory signatures) external {
        require(target != address(0), "Invalid target address");

        // Create the struct hash for the transaction
        bytes32 structHash = keccak256(abi.encode(
            keccak256("Execute(address target,bytes data,uint256 nonce)"),
            target,
            keccak256(data),
            nonce
        ));
        // Create the message hash
        bytes32 msgHash = _hashTypedDataV4(structHash);

        // Verify the signatures and count the number of verifiers
        for (uint256 i = 0; i < signatures.length; i++) {
            address signer = ECDSA.recover(msgHash, signatures[i]);
            require(verifiers[signer].isRegistered, "Invalid signature");
        }

        // Ensure that the number of verifiers is at least 2/3 of the total registered verifiers
        require(signatures.length >= (2 * verifierCount) / 3, "Not enough verifiers");

        // Increment the nonce
        nonce++;

        // Execute the transaction
        (bool success, ) = target.call(data);
        require(success, "Data execution failed");

        emit Executed(target, data);
    }

    /**
     * @dev Sets the unstake lock period.
     * @param _unstakeLockPeriod The new unstake lock period.
     */
    function setUnstakeLockPeriod(uint256 _unstakeLockPeriod) external onlyOwner {
        unstakeLockPeriod = _unstakeLockPeriod;
    }

    /**
     * @dev Sets the required stake amount.
     * @param _fixedStakeAmount The new minimum stake amount.
     */
    function setRequireStakeAmount(uint256 _fixedStakeAmount) external onlyOwner {
        fixedStakeAmount = _fixedStakeAmount;
    }

    // Function to get the version of the contract
    function version() public pure returns (string memory) {
        return "1.0.0";
    }
}
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

    // Enum to represent verifier status
    enum Status {
        Active,
        Slashed,
        Exiting,
        Exited
    }

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
        uint256 unlockTime; // Add unlockTime
        Status status; // Add status
    }

    // State variables
    IERC20 public stakingToken;
    uint256 public fixedStakeAmount;
    uint256 public unstakeLockPeriod;
    uint256 public nonce;
    uint256 public verifierCount; // Add verifier count

    // Mappings to store various data
    mapping(address => VerifierInfo) public verifiers;
    mapping(address => uint256) public nonces;

    // Events
    event VerifierRegistered(address indexed verifier, uint256 stakeAmount, string name, string website, string metadata);
    event PeerIdsUpdated(address indexed verifier, string newPeerId);
    event VerifierInfoUpdated(address indexed verifier, string name, string website, string metadata);
    event VerifierSlashed(address indexed verifier, uint256 slashPercentage);
    event Executed(address indexed target, bytes data);
    event Exiting(address indexed verifier, uint256 unlockTime);
    event Exited(address indexed verifier, uint256 remainingAmount);

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
     * @param peerId The peer IDs of the verifier.
     * @param name The name of the verifier.
     * @param website The website of the verifier.
     * @param metadata Additional metadata for the verifier.
     */
    function register(
        address verifier,
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
            owner: msg.sender,
            isRegistered: true,
            stakeAmount: stakeAmount,
            peerId: peerId,
            name: name,
            website: website,
            metadata: metadata,
            slashPercentage: 0,
            isSlashed: false,
            unlockTime: block.timestamp + unstakeLockPeriod, // Set unlockTime
            status: Status.Active // Set status to Active
        });

        verifierCount++; // Increment verifier count


        // Transfer staking tokens from the sender to the contract
        stakingToken.safeTransferFrom(msg.sender, address(this), stakeAmount);

        emit VerifierRegistered(verifier, stakeAmount, name, website, metadata);
    }

    /**
     * @dev Marks a verifier as exiting or exited.
     * @param verifier The address of the verifier.
     */
    function exit(address verifier) external onlyVerifierOwner(verifier) {
        require(verifiers[verifier].isRegistered, "Verifier not registered");
        require(verifiers[verifier].status != Status.Exited, "Verifier already exited");

        if (verifiers[verifier].status != Status.Exiting) {
            // Mark the verifier as exiting and set unlock time
            verifiers[verifier].status = Status.Exiting;
            verifiers[verifier].unlockTime = block.timestamp + unstakeLockPeriod;
            emit Exiting(verifier, verifiers[verifier].unlockTime);
        } else {
            require(block.timestamp >= verifiers[verifier].unlockTime, "Unlock time not reached");

            uint256 stakeAmount = verifiers[verifier].stakeAmount;
            uint256 slashedAmount = (stakeAmount * verifiers[verifier].slashPercentage) / 100;
            uint256 remainingAmount = stakeAmount - slashedAmount;

            if (slashedAmount > 0) {
                // Transfer the slashed amount to the zero address
                stakingToken.safeTransfer(address(0xdead), slashedAmount);
            }

            // Transfer the remaining stake amount to the owner
            stakingToken.safeTransfer(verifiers[verifier].owner, remainingAmount);

            // Mark the verifier as exited
            verifiers[verifier].status = Status.Exited;
            emit Exited(verifier, remainingAmount);
        }
    }

    /**
     * @dev Updates the information of a verifier.
     * @param verifier The address of the verifier.
     * @param name The new name of the verifier.
     * @param website The new website of the verifier.
     * @param metadata The new metadata of the verifier.
     */
    function updateInfo(
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
    function slash(address verifier, uint256 slashPercentage) external onlyOwner {
        require(verifiers[verifier].isRegistered, "Verifier not registered");
        require(slashPercentage > 0 && slashPercentage <= 100, "Invalid slash percentage");
        require(!verifiers[verifier].isSlashed, "Verifier already slashed");

        // Update the verifier's slash percentage and mark as slashed
        verifiers[verifier].slashPercentage = slashPercentage;
        verifiers[verifier].isSlashed = true;
        verifiers[verifier].status = Status.Slashed; // Set status to Slashed

        verifierCount--; // Decrement verifier count

        emit VerifierSlashed(verifier, slashPercentage);
    }

    /**
     * @dev Executes a transaction with signatures from verifiers.
     * @param target The address of the target contract.
     * @param data The data to be executed.
     * @param signatures The signatures from the verifiers.
     */
    function execute(address target, bytes memory data, bytes[] memory signatures) external payable returns (bool success) {
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

        // Verify the signatures and count the number of active verifiers
        uint256 activeVerifierCount = 0;
        for (uint256 i = 0; i < signatures.length; i++) {
            address signer = ECDSA.recover(msgHash, signatures[i]);
            require(verifiers[signer].isRegistered, "Invalid signature");
            require(verifiers[signer].status == Status.Active, "Verifier not active");
            activeVerifierCount++;
        }

        // Ensure that the number of active verifiers is at least 2/3 of the total registered verifiers
        require(activeVerifierCount >= (2 * verifierCount) / 3, "Not enough active verifiers");

        // Increment the nonce
        nonce++;

        // Execute the transaction
        (success, ) = target.call(data);
        if (!success) {
            /* solhint-disable no-inline-assembly */
            /// @solidity memory-safe-assembly
            assembly {
                let ptr := mload(0x40)
                returndatacopy(ptr, 0, returndatasize())
                revert(ptr, returndatasize())
            }
            /* solhint-enable no-inline-assembly */
        }

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

    /**
     * @dev Returns the owner of the verifier.
     * @param verifier The address of the verifier.
     * @return The owner address of the verifier.
     */
    function ownerOf(address verifier) external view returns (address) {
        return verifiers[verifier].owner;
    }

    /**
     * @dev Returns the information of a verifier.
     * @param verifier The address of the verifier.
     * @return VerifierInfo struct containing the verifier's information.
     */
    function getVerifier(address verifier) external view returns (VerifierInfo memory) {
        return verifiers[verifier];
    }

    /**
     * @dev Checks if a verifier is active.
     * @param verifier The address of the verifier.
     * @return True if the verifier is active, false otherwise.
     */
    function isActive(address verifier) external view returns (bool) {
        return verifiers[verifier].status == Status.Active;
    }

    // Function to get the version of the contract
    function version() public pure returns (string memory) {
        return "1.0.0";
    }
}
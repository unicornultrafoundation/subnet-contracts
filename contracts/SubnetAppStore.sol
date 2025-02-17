// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./SubnetProvider.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/**
 * @title SubnetAppStore
 * @dev Registry to manage applications running on subnets and reward nodes based on resource usage.
 * Implements EIP-712 for structured data signing and Ownable for admin functionalities.
 */
contract SubnetAppStore is Initializable, EIP712Upgradeable, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    // EIP-712 Domain Separator constants
    string private constant SIGNING_DOMAIN = "SubnetAppStore";
    string private constant SIGNATURE_VERSION = "1";

    // Struct representing an application
    struct App {
        string peerId;
        address owner; // Application owner
        address operator; // Application operator
        address verifier; // Verifier address
        string name; // Application name
        string symbol; // Unique symbol
        uint256 budget; // Total budget for the app
        uint256 spentBudget; // Spent budget
        uint256 pricePerCpu; // Price per CPU unit
        uint256 pricePerGpu; // Price per GPU unit
        uint256 pricePerMemoryGB; // Price per GB of memory
        uint256 pricePerStorageGB; // Price per GB of storage
        uint256 pricePerBandwidthGB; // Price per GB of bandwidth
        string metadata; // Metadata
        address paymentToken; // ERC20 token for payment
    }

    // Struct for tracking node-specific resource usage
    struct Deployment {
        bool isRegistered;
        uint256 lastClaimTime; // Last time reward was claimed
        uint256 pendingReward; // Pending reward to be claimed
    }

    // Struct representing resource usage for a claim
    struct Usage {
        uint256 providerId;
        uint256 appId;
        string peerId;
        uint256 usedCpu;
        uint256 usedGpu;
        uint256 usedMemory;
        uint256 usedStorage;
        uint256 usedUploadBytes;
        uint256 usedDownloadBytes;
        uint256 duration;
        uint256 timestamp; // Timestamp of the usage report
    }

    // State variables
    uint256 public appCount; // Counter for applications
    mapping(uint256 => App) public apps; // Map app ID to App struct
    mapping(string => uint256) public symbolToAppId; // Map symbol to app ID
    SubnetProvider public subnetProvider; // Reference to the Subnet Provider contract
    mapping(uint256 => mapping(uint256 => Deployment)) public deployments; // Map app ID and provider ID to deployment-specific data
    mapping(bytes32 => bool) public usedMessageHashes; // Track used message hashes to prevent replay attacks
    address public treasury; // Treasury address
    uint256 public feeRate; // Fee rate in parts per thousand (e.g., 50 = 5%)
    uint256 public verifierRewardRate; // Reward rate for verifiers in parts per thousand (e.g., 10 = 1%)

    // Events
    event AppCreated(
        uint256 indexed appId,
        string name,
        string symbol,
        address indexed owner,
        uint256 budget
    );
    event RewardClaimed(
        uint256 indexed appId,
        uint256 indexed providerId,
        uint256 reward
    );
    event DeploymentCreated(uint256 indexed providerId, uint256 indexed appId);
    event DeploymentClosed(uint256 indexed providerId, uint256 indexed appId);
    event UsageReported(
        uint256 indexed appId,
        uint256 indexed providerId,
        string peerId,
        uint256 usedCpu,
        uint256 usedGpu,
        uint256 usedMemory,
        uint256 usedStorage,
        uint256 usedUploadBytes,
        uint256 usedDownloadBytes,
        uint256 duration,
        uint256 timestamp,
        uint256 reward
    );
    event BudgetDeposited(uint256 indexed appId, uint256 amount);
    event BudgetRefunded(uint256 indexed appId, uint256 amount);
    event ProviderRefunded(uint256 indexed appId, uint256 indexed providerId, uint256 amount);

    /**
     * @dev Emitted when an application is updated.
     */
    event AppUpdated(uint256 appId);

    event VerifierRewardClaimed(address indexed verifier, uint256 reward);

    /**
     * @dev Initializes the contract. This function is called by the proxy.
     * @param _subnetProvider Address of the Subnet Provider.
     * @param initialOwner Address of the initial owner of the contract.
     * @param _treasury Address of the treasury to collect fees.
     * @param _feeRate Fee rate as parts per thousand.
     */
    function initialize(
        address _subnetProvider,
        address initialOwner,
        address _treasury,
        uint256 _feeRate
    ) external initializer {
        require(
            _subnetProvider != address(0),
            "Invalid SubnetProvider address"
        );
        subnetProvider = SubnetProvider(_subnetProvider);
        treasury = _treasury;
        feeRate = _feeRate;
        __Ownable_init(initialOwner);
        __EIP712_init(SIGNING_DOMAIN, SIGNATURE_VERSION);
    }

    /**
     * @dev Updates the treasury address.
     * @param _treasury The new treasury address.
     */
    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "Invalid treasury address");
        treasury = _treasury;
    }

    /**
     * @dev Updates the fee rate.
     * @param _feeRate The new fee rate in parts per thousand.
     */
    function setFeeRate(uint256 _feeRate) external onlyOwner {
        require(_feeRate <= 1000, "Fee rate must be <= 1000 (100%)");
        feeRate = _feeRate;
    }

    /**
     * @dev Updates the verifier reward rate.
     * @param _verifierRewardRate The new verifier reward rate in parts per thousand.
     */
    function setVerifierRewardRate(
        uint256 _verifierRewardRate
    ) external onlyOwner {
        require(
            _verifierRewardRate <= 1000,
            "Verifier reward rate must be <= 1000 (100%)"
        );
        verifierRewardRate = _verifierRewardRate;
    }

    /**
     * @dev Creates a new application with specified resource requirements and payment configurations.
     * The application is registered under the caller's ownership.
     *
     * @param name The name of the application.
     * @param symbol A unique symbol representing the application.
     * @param peerId A unique identifier for the application's network peer.
     * @param budget The total budget allocated for the application.
     * @param pricePerCpu The payment per unit of CPU used.
     * @param pricePerGpu The payment per unit of GPU used.
     * @param pricePerMemoryGB The payment per GB of memory used.
     * @param pricePerStorageGB The payment per GB of storage used.
     * @param pricePerBandwidthGB The payment per GB of bandwidth used.
     * @param metadata Metadata
     * @param operator The operator of the application.
     * @param verifier The verifier of the application.
     * @param paymentToken The ERC20 token address for payment.
     */
    function createApp(
        string memory name,
        string memory symbol,
        string memory peerId,
        uint256 budget,
        uint256 pricePerCpu,
        uint256 pricePerGpu,
        uint256 pricePerMemoryGB,
        uint256 pricePerStorageGB,
        uint256 pricePerBandwidthGB,
        string memory metadata,
        address operator,
        address verifier,
        address paymentToken
    ) public returns (uint256) {
        require(symbolToAppId[symbol] == 0, "Symbol already exists");

        appCount++;

        App storage app = apps[appCount];
        app.peerId = peerId;
        app.owner = msg.sender;
        app.operator = operator;
        app.verifier = verifier;
        app.name = name;
        app.symbol = symbol;
        app.budget = budget;
        app.pricePerCpu = pricePerCpu;
        app.pricePerGpu = pricePerGpu;
        app.pricePerMemoryGB = pricePerMemoryGB;
        app.pricePerStorageGB = pricePerStorageGB;
        app.pricePerBandwidthGB = pricePerBandwidthGB;
        app.metadata = metadata;
        app.paymentToken = paymentToken;

        symbolToAppId[symbol] = appCount;

        // Transfer the budget in ERC20 tokens from the caller to the contract
        IERC20(paymentToken).safeTransferFrom(
            msg.sender,
            address(this),
            budget
        );

        emit AppCreated(appCount, name, symbol, msg.sender, budget);
        return appCount;
    }

    /**
     * @dev Deposits additional budget to an existing application.
     * @param appId The ID of the application to deposit budget to.
     * @param amount The amount of budget to deposit.
     */
    function deposit(uint256 appId, uint256 amount) external {
        App storage app = apps[appId];

        require(app.owner == msg.sender, "Only the owner can deposit budget");
        require(appId > 0 && appId <= appCount, "Application ID is invalid");

        // Transfer the additional budget in ERC20 tokens from the caller to the contract
        IERC20(app.paymentToken).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );

        // Update the app's budget
        app.budget += amount;

        emit BudgetDeposited(appId, amount);
    }

    /**
     * @dev Updates an existing application with new resource requirements and payment configurations.
     * Only the owner of the application can perform the update.
     *
     * @param appId The ID of the application to update.
     * @param pricePerCpu The new payment per unit of CPU used.
     * @param pricePerGpu The new payment per unit of GPU used.
     * @param pricePerMemoryGB The new payment per GB of memory used.
     * @param pricePerStorageGB The new payment per GB of storage used.
     * @param pricePerBandwidthGB The new payment per GB of bandwidth used.
     */
    function updateApp(
        uint256 appId,
        uint256 pricePerCpu,
        uint256 pricePerGpu,
        uint256 pricePerMemoryGB,
        uint256 pricePerStorageGB,
        uint256 pricePerBandwidthGB
    ) public {
        App storage app = apps[appId];

        require(
            app.owner == msg.sender,
            "Only the owner can update the application"
        );
        require(appId > 0 && appId <= appCount, "Application ID is invalid");

        app.pricePerCpu = pricePerCpu;
        app.pricePerGpu = pricePerGpu;
        app.pricePerMemoryGB = pricePerMemoryGB;
        app.pricePerStorageGB = pricePerStorageGB;
        app.pricePerBandwidthGB = pricePerBandwidthGB;

        emit AppUpdated(appId);
    }

    /**
     * @dev Updates the metadata of an existing application.
     * Only the owner of the application can perform the update.
     *
     * @param appId The ID of the application to update.
     * @param metadata The new metadata.
     */
    function updateMetadata(uint256 appId, string memory metadata) public {
        App storage app = apps[appId];

        require(
            app.owner == msg.sender,
            "Only the owner can update the metadata"
        );
        require(appId > 0 && appId <= appCount, "Application ID is invalid");

        app.metadata = metadata;

        emit AppUpdated(appId);
    }

    /**
     * @dev Updates the name of an existing application.
     * Only the owner of the application can perform the update.
     *
     * @param appId The ID of the application to update.
     * @param name The new name.
     */
    function updateName(uint256 appId, string memory name) public {
        App storage app = apps[appId];

        require(app.owner == msg.sender, "Only the owner can update the name");
        require(appId > 0 && appId <= appCount, "Application ID is invalid");

        app.name = name;

        emit AppUpdated(appId);
    }

    /**
     * @dev Updates the operator of an existing application.
     * Only the owner of the application can perform the update.
     *
     * @param appId The ID of the application to update.
     * @param operator The new operator.
     */
    function updateOperator(uint256 appId, address operator) public {
        App storage app = apps[appId];

        require(
            app.owner == msg.sender,
            "Only the owner can update the operator"
        );
        require(appId > 0 && appId <= appCount, "Application ID is invalid");

        app.operator = operator;

        emit AppUpdated(appId);
    }

    /**
     * @dev Updates the verifier of an existing application.
     * Only the owner of the application can perform the update.
     *
     * @param appId The ID of the application to update.
     * @param verifier The new verifier.
     */
    function updateVerifier(uint256 appId, address verifier) public {
        App storage app = apps[appId];

        require(
            app.owner == msg.sender,
            "Only the owner can update the verifier"
        );
        require(appId > 0 && appId <= appCount, "Application ID is invalid");

        app.verifier = verifier;

        emit AppUpdated(appId);
    }

    /**
     * @dev Updates the peerId of an existing application.
     * Only the owner or operator of the application can perform the update.
     *
     * @param appId The ID of the application to update.
     * @param peerId The new peerId.
     */
    function updatePeerId(uint256 appId, string memory peerId) public {
        App storage app = apps[appId];

        require(
            app.owner == msg.sender || app.operator == msg.sender,
            "Only the owner or operator can update the peerId"
        );
        require(appId > 0 && appId <= appCount, "Application ID is invalid");

        app.peerId = peerId;

        emit AppUpdated(appId);
    }

    /**
     * @dev Reports usage for node resources based on usage data.
     * This function calculates rewards for a node by validating its reported resource usage,
     * ensuring it's within the application's budget, and storing the pending rewards.
     *
     * @param appId The ID of the application the node is working on.
     * @param providerId The ID of the provider where the node is registered.
     * @param peerId The ID of the peer node.
     * @param usedCpu The total CPU usage (in units) reported by the node.
     * @param usedGpu The total GPU usage (in units) reported by the node.
     * @param usedMemory The total memory usage (in GB) reported by the node.
     * @param usedStorage The total storage usage (in GB) reported by the node.
     * @param usedUploadBytes The total uploaded data (in bytes) reported by the node.
     * @param usedDownloadBytes The total downloaded data (in bytes) reported by the node.
     * @param duration The duration (in seconds) the node worked.
     * @param timestamp The timestamp of the usage report.
     * @param signature The EIP-712 signature from the application owner or operator validating the usage data.
     */
    function reportUsage(
        uint256 appId,
        uint256 providerId,
        string memory peerId,
        uint256 usedCpu,
        uint256 usedGpu,
        uint256 usedMemory,
        uint256 usedStorage,
        uint256 usedUploadBytes,
        uint256 usedDownloadBytes,
        uint256 duration,
        uint256 timestamp,
        bytes memory signature
    ) external {
        // Validate the application ID and other inputs
        require(appId > 0 && appId <= appCount, "Invalid App ID");
        App storage app = apps[appId];
        require(app.budget > app.spentBudget, "App budget exhausted");

        // Verify provider details and node registration
        SubnetProvider.Provider memory provider = subnetProvider.getProvider(
            providerId
        );
        require(provider.tokenId != 0, "Provider inactive");
        require(subnetProvider.getPeerNode(providerId, peerId).isRegistered, "Peer node not registered");

        // Hash and verify usage data
        Usage memory data = Usage({
            appId: appId,
            providerId: providerId,
            peerId: peerId,
            usedCpu: usedCpu,
            usedGpu: usedGpu,
            usedMemory: usedMemory,
            usedStorage: usedStorage,
            usedUploadBytes: usedUploadBytes,
            usedDownloadBytes: usedDownloadBytes,
            duration: duration,
            timestamp: timestamp
        });
        bytes32 structHash = _hashTypedDataV4(_hashUpdateUsageData(data));
        require(!usedMessageHashes[structHash], "Replay attack detected");
        usedMessageHashes[structHash] = true;

        address signer = ECDSA.recover(structHash, signature);
        require(
            signer == app.owner || signer == app.operator || signer == app.verifier,
            "Invalid app owner or operator signature"
        );

        // Retrieve and calculate new usage
        Deployment storage deployment = deployments[appId][providerId];
        // Increment node count if the deployment is new
        if (!deployment.isRegistered) {
            deployment.isRegistered = true;
            deployment.lastClaimTime = block.timestamp;
        }

        // Calculate reward
        uint256 reward = calculateReward(appId, usedCpu, usedGpu, usedMemory, usedStorage, usedUploadBytes, usedDownloadBytes, duration);

        // Ensure sufficient budget
        require(app.budget >= app.spentBudget + reward, "Insufficient budget");

        // Calculate verifier reward if signer is the operator and not the owner
        uint256 verifierReward = 0;
        if (signer == app.verifier && verifierRewardRate > 0) {
            verifierReward = (reward * verifierRewardRate) / 1000;
            if (verifierReward > 0) {
                // Transfer verifier reward to the operator
                IERC20(app.paymentToken).safeTransfer(
                    app.verifier,
                    verifierReward
                );
                emit VerifierRewardClaimed(app.verifier, verifierReward);
            }
        }

        // Update pending reward for deployment
        deployment.pendingReward += (reward - verifierReward);

        // Update the app's spent budget
        app.spentBudget += reward;

        emit UsageReported(
            appId,
            providerId,
            peerId,
            usedCpu,
            usedGpu,
            usedMemory,
            usedStorage,
            usedUploadBytes,
            usedDownloadBytes,
            duration,
            timestamp,
            reward
        );
    }

    /**
     * @dev Claims a reward for node resources based on usage data.
     * This function distributes the pending rewards to the node.
     *
     * @param providerId The ID of the provider where the node is registered.
     * @param appId The ID of the application the node is working on.
     */
    function claimReward(uint256 providerId, uint256 appId) external {
        // Validate the application ID and other inputs
        require(appId > 0 && appId <= appCount, "Invalid App ID");

        // Verify provider details and node registration
        SubnetProvider.Provider memory provider = subnetProvider.getProvider(
            providerId
        );
        require(provider.tokenId != 0, "Provider inactive");
        require(!provider.isJailed, "Provider is jailed");

        // Retrieve the node's pending reward
        Deployment storage deployment = deployments[appId][providerId];
        uint256 reward = deployment.pendingReward;

        // Ensure 30 days have passed since the last claim
        require(
            block.timestamp >= deployment.lastClaimTime + 30 days,
            "Claim not yet unlocked"
        );

        address owner = subnetProvider.ownerOf(providerId);
        // Ensure the caller is the owner of the NFT
        require(owner == msg.sender, "Caller is not the owner of the NFT");

        // Update the last claim time
        deployment.lastClaimTime = block.timestamp;

        // Update budget and transfer rewards
        uint256 fee = (reward * feeRate) / 1000;
        uint256 netReward = reward - fee;

        IERC20(apps[appId].paymentToken).safeTransfer(treasury, fee);
        IERC20(apps[appId].paymentToken).safeTransfer(owner, netReward);

        // Reset pending reward
        deployment.pendingReward = 0;

        emit RewardClaimed(appId, providerId, reward);
    }

    /**
     * @dev Refunds the remaining budget to the app owner.
     * @param appId The ID of the application to refund.
     */
    function refund(uint256 appId) external {
        App storage app = apps[appId];

        require(app.owner == msg.sender, "Only the owner can request a refund");
        require(appId > 0 && appId <= appCount, "Application ID is invalid");

        uint256 remainingBudget = app.budget - app.spentBudget;
        require(remainingBudget > 0, "No remaining budget to refund");

        // Transfer the remaining budget in ERC20 tokens from the contract to the owner
        IERC20(app.paymentToken).safeTransfer(app.owner, remainingBudget);

        // Update the app's budget
        app.budget = 0;
        app.spentBudget = 0;

        emit BudgetRefunded(appId, remainingBudget);
    }

    /**
     * @dev Refunds the remaining budget to a specific provider.
     * @param appId The ID of the application to refund.
     * @param providerId The ID of the provider to refund.
     */
    function refundProvider(uint256 appId, uint256 providerId) external {
        App storage app = apps[appId];
        require(appId > 0 && appId <= appCount, "Application ID is invalid");

        SubnetProvider.Provider memory provider = subnetProvider.getProvider(providerId);
        require(provider.isJailed, "Provider is not jailed");

        Deployment storage deployment = deployments[appId][providerId];
        uint256 pendingReward = deployment.pendingReward;
        require(pendingReward > 0, "No pending reward to refund");

        // Transfer the pending reward in ERC20 tokens from the contract to the provider owner
        IERC20(app.paymentToken).safeTransfer(app.owner, pendingReward);

        // Reset pending reward
        deployment.pendingReward = 0;

        emit ProviderRefunded(appId, providerId, pendingReward);
    }

    /**
     * @dev Fetches a range of applications (apps) from the registry.
     * Supports pagination by allowing the caller to specify the range of apps.
     * This function prevents gas overflow by fetching a limited subset of apps.
     *
     * @param start The starting index of the apps to fetch (inclusive).
     * @param end The ending index of the apps to fetch (inclusive).
     * @return appList An array of `App` structs representing the requested apps.
     */
    function listApps(
        uint256 start,
        uint256 end
    ) external view returns (App[] memory) {
        // Validate the input range
        // 1. 'start' must be greater than or equal to 1 (valid app ID).
        // 2. 'end' must not exceed the total number of apps (`appCount`).
        // 3. 'start' must be less than or equal to 'end'.
        require(start >= 1 && end <= appCount && start <= end, "Invalid range");

        // Initialize a new array to store the requested apps.
        // The size of the array is determined by the range: (end - start + 1).
        App[] memory appList = new App[](end - start + 1);

        // Iterate over the specified range and populate the array with apps.
        for (uint256 i = start; i <= end; i++) {
            // Add the app at index `i` to the array at the corresponding position.
            appList[i - start] = apps[i];
        }

        // Return the array of apps to the caller.
        return appList;
    }

    /**
     * @dev Hashes the usage data as per EIP-712.
     */
    function _hashUpdateUsageData(
        Usage memory data
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    keccak256(
                        "Usage(uint256 appId,uint256 providerId,string peerId,uint256 usedCpu,uint256 usedGpu,uint256 usedMemory,uint256 usedStorage,uint256 usedUploadBytes,uint256 usedDownloadBytes,uint256 duration,uint256 timestamp)"
                    ),
                    data.appId,
                    data.providerId,
                    keccak256(bytes(data.peerId)),
                    data.usedCpu,
                    data.usedGpu,
                    data.usedMemory,
                    data.usedStorage,
                    data.usedUploadBytes,
                    data.usedDownloadBytes,
                    data.duration,
                    data.timestamp
                )
            );
    }

    /**
     * @dev Retrieves the details of a specific application.
     * @param appId The ID of the application to fetch details for.
     * @return app The App struct containing all the application details.
     */
    function getApp(uint256 appId) external view returns (App memory app) {
        // Ensure the app exists
        require(apps[appId].owner != address(0), "App does not exist");

        // Return the App struct
        return apps[appId];
    }

    /**
     * @dev Retrieves the usage details of a node for a specific application.
     * @param appId The ID of the application.
     * @param providerId The ID of the provider (node) to fetch details for.
     * @return deployment The Deployment struct containing the node's usage details.
     */
    function getDeployment(
        uint256 appId,
        uint256 providerId
    ) external view returns (Deployment memory deployment) {
        // Return the Deployment struct
        return deployments[appId][providerId];
    }

    function version() public pure returns (string memory) {
        return "1.0.0";
    }

    /**
     * @dev Calculates the reward based on resource usage.
     * @param appId The application ID.
     * @param usedCpu The total CPU usage (in units) reported by the node.
     * @param usedGpu The total GPU usage (in units) reported by the node.
     * @param usedMemory The total memory usage (in GB) reported by the node.
     * @param usedStorage The total storage usage (in GB) reported by the node.
     * @param usedUploadBytes The total uploaded data (in bytes) reported by the node.
     * @param usedDownloadBytes The total downloaded data (in bytes) reported by the node.
     * @param duration The duration (in seconds) the node worked.
     * @return reward The calculated reward.
     */
    function calculateReward(
        uint256 appId,
        uint256 usedCpu,
        uint256 usedGpu,
        uint256 usedMemory,
        uint256 usedStorage,
        uint256 usedUploadBytes,
        uint256 usedDownloadBytes,
        uint256 duration
    ) public view returns (uint256 reward) {
        App memory app = apps[appId];
        // Bandwidth usage (independent of duration)
        uint256 bandwidthGB = (usedUploadBytes + usedDownloadBytes) / 1e9;
        reward += bandwidthGB * app.pricePerBandwidthGB;

        // CPU (independent of duration)
        reward += usedCpu * app.pricePerCpu;

        // Memory and Storage usage (dependent on duration)
        reward += (usedMemory / 1e9) * duration * app.pricePerMemoryGB;
        reward += (usedStorage / 1e9) * duration * app.pricePerStorageGB;
        reward += (usedGpu / 1e9) * duration * app.pricePerGpu;

        return reward;
    }
}

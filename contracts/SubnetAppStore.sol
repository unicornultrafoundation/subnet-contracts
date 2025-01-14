// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./SubnetProvider.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
/**
 * @title SubnetAppStore
 * @dev Registry to manage applications running on subnets and reward nodes based on resource usage.
 * Implements EIP-712 for structured data signing and Ownable for admin functionalities.
 */
contract SubnetAppStore is EIP712, Ownable {
    using SafeERC20 for IERC20;

    // EIP-712 Domain Separator constants
    string private constant SIGNING_DOMAIN = "SubnetAppRegistry";
    string private constant SIGNATURE_VERSION = "1";

    // Struct representing an application
    struct App {
        string peerId;
        address owner; // Application owner
        address operator; // Application operator
        string name; // Application name
        string symbol; // Unique symbol
        uint256 budget; // Total budget for the app
        uint256 spentBudget; // Spent budget
        uint256 maxNodes; // Maximum allowed nodes
        uint256 minCpu; // Minimum CPU required
        uint256 minGpu; // Minimum GPU required
        uint256 minMemory; // Minimum memory required
        uint256 minUploadBandwidth; // Minimum upload bandwidth required
        uint256 minDownloadBandwidth; // Minimum download bandwidth required
        uint256 nodeCount; // Current active nodes
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
        uint256 duration; // Duration the node has been running (in seconds)
        uint256 usedCpu;
        uint256 usedGpu;
        uint256 usedMemory;
        uint256 usedStorage;
        uint256 usedDownloadBytes;
        uint256 usedUploadBytes;
        bool isRegistered;
        uint256 lastClaimTime; // Last time reward was claimed
        uint256 pendingReward; // Pending reward to be claimed
    }

    // Struct representing resource usage for a claim
    struct Usage {
        uint256 providerId;
        uint256 appId;
        uint256 usedCpu;
        uint256 usedGpu;
        uint256 usedMemory;
        uint256 usedStorage;
        uint256 usedUploadBytes;
        uint256 usedDownloadBytes;
        uint256 duration;
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
        uint256 reward
    );
    event BudgetDeposited(
        uint256 indexed appId,
        uint256 amount
    );

    /**
     * @dev Emitted when an application is updated.
     */
    event AppUpdated(uint256 appId);

    /**
     * @dev Constructor for initializing the contract.
     * @param _subnetProvider Address of the Subnet Provider.
     * @param initialOwner Address of the initial owner of the contract.
     * @param _treasury Address of the treasury to collect fees.
     * @param _feeRate Fee rate as parts per thousand.
     */
    constructor(
        address _subnetProvider,
        address initialOwner,
        address _treasury,
        uint256 _feeRate
    ) EIP712(SIGNING_DOMAIN, SIGNATURE_VERSION) Ownable(initialOwner) {
        require(
            _subnetProvider != address(0),
            "Invalid SubnetProvider address"
        );
        subnetProvider = SubnetProvider(_subnetProvider);
        treasury = _treasury;
        feeRate = _feeRate;
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
     * @dev Creates a new application with specified resource requirements and payment configurations.
     * The application is registered under the caller's ownership.
     *
     * @param name The name of the application.
     * @param symbol A unique symbol representing the application.
     * @param peerId A unique identifier for the application's network peer.
     * @param budget The total budget allocated for the application.
     * @param maxNodes The maximum number of nodes that can participate in the application.
     * @param minCpu The minimum CPU requirement for participating nodes.
     * @param minGpu The minimum GPU requirement for participating nodes.
     * @param minMemory The minimum memory requirement (in GB) for participating nodes.
     * @param minUploadBandwidth The minimum upload bandwidth requirement (in Mbps) for participating nodes.
     * @param minDownloadBandwidth The minimum download bandwidth requirement (in Mbps) for participating nodes.
     * @param pricePerCpu The payment per unit of CPU used.
     * @param pricePerGpu The payment per unit of GPU used.
     * @param pricePerMemoryGB The payment per GB of memory used.
     * @param pricePerStorageGB The payment per GB of storage used.
     * @param pricePerBandwidthGB The payment per GB of bandwidth used.
     * @param metadata Metadata
     * @param operator The operator of the application.
     * @param paymentToken The ERC20 token address for payment.
     */
    function createApp(
        string memory name,
        string memory symbol,
        string memory peerId,
        uint256 budget,
        uint256 maxNodes,
        uint256 minCpu,
        uint256 minGpu,
        uint256 minMemory,
        uint256 minUploadBandwidth,
        uint256 minDownloadBandwidth,
        uint256 pricePerCpu,
        uint256 pricePerGpu,
        uint256 pricePerMemoryGB,
        uint256 pricePerStorageGB,
        uint256 pricePerBandwidthGB,
        string memory metadata,
        address operator,
        address paymentToken
    ) public {
        require(maxNodes > 0, "Max nodes must be greater than zero");
        require(symbolToAppId[symbol] == 0, "Symbol already exists");

        appCount++;

        App storage app = apps[appCount];
        app.peerId = peerId;
        app.owner = msg.sender;
        app.operator = operator;
        app.name = name;
        app.symbol = symbol;
        app.budget = budget;
        app.maxNodes = maxNodes;
        app.minCpu = minCpu;
        app.minGpu = minGpu;
        app.minMemory = minMemory;
        app.minUploadBandwidth = minUploadBandwidth;
        app.minDownloadBandwidth = minDownloadBandwidth;
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
        IERC20(app.paymentToken).safeTransferFrom(msg.sender, address(this), amount);

        // Update the app's budget
        app.budget += amount;

        emit BudgetDeposited(appId, amount);
    }

    /**
     * @dev Updates an existing application with new resource requirements and payment configurations.
     * Only the owner of the application can perform the update.
     *
     * @param appId The ID of the application to update.
     * @param peerId The new unique identifier for the application's network peer.
     * @param maxNodes The new maximum number of nodes that can participate in the application.
     * @param minCpu The new minimum CPU requirement for participating nodes.
     * @param minGpu The new minimum GPU requirement for participating nodes.
     * @param minMemory The new minimum memory requirement (in GB) for participating nodes.
     * @param minUploadBandwidth The new minimum upload bandwidth requirement (in Mbps) for participating nodes.
     * @param minDownloadBandwidth The new minimum download bandwidth requirement (in Mbps) for participating nodes.
     * @param pricePerCpu The new payment per unit of CPU used.
     * @param pricePerGpu The new payment per unit of GPU used.
     * @param pricePerMemoryGB The new payment per GB of memory used.
     * @param pricePerStorageGB The new payment per GB of storage used.
     * @param pricePerBandwidthGB The new payment per GB of bandwidth used.
     */
    function updateApp(
        uint256 appId,
        string memory peerId,
        uint256 maxNodes,
        uint256 minCpu,
        uint256 minGpu,
        uint256 minMemory,
        uint256 minUploadBandwidth,
        uint256 minDownloadBandwidth,
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
        require(maxNodes > 0, "Max nodes must be greater than zero");

        app.peerId = peerId;
        app.maxNodes = maxNodes;
        app.minCpu = minCpu;
        app.minGpu = minGpu;
        app.minMemory = minMemory;
        app.minUploadBandwidth = minUploadBandwidth;
        app.minDownloadBandwidth = minDownloadBandwidth;
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
     * @dev Reports usage for node resources based on usage data.
     * This function calculates rewards for a node by validating its reported resource usage,
     * ensuring it's within the application's budget, and storing the pending rewards.
     *
     * @param providerId The ID of the provider where the node is registered.
     * @param appId The ID of the application the node is working on.
     * @param usedCpu The total CPU usage (in units) reported by the node.
     * @param usedGpu The total GPU usage (in units) reported by the node.
     * @param usedMemory The total memory usage (in GB) reported by the node.
     * @param usedStorage The total storage usage (in GB) reported by the node.
     * @param usedUploadBytes The total uploaded data (in bytes) reported by the node.
     * @param usedDownloadBytes The total downloaded data (in bytes) reported by the node.
     * @param duration The duration (in seconds) the node worked.
     * @param signature The EIP-712 signature from the application owner or operator validating the usage data.
     */
    function reportUsage(
        uint256 providerId,
        uint256 appId,
        uint256 usedCpu,
        uint256 usedGpu,
        uint256 usedMemory,
        uint256 usedStorage,
        uint256 usedUploadBytes,
        uint256 usedDownloadBytes,
        uint256 duration,
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
        // Hash and verify usage data
        Usage memory data = Usage({
            providerId: providerId,
            appId: appId,
            usedCpu: usedCpu,
            usedGpu: usedGpu,
            usedMemory: usedMemory,
            usedStorage: usedStorage,
            usedUploadBytes: usedUploadBytes,
            usedDownloadBytes: usedDownloadBytes,
            duration: duration
        });
        bytes32 structHash = _hashTypedDataV4(_hashUpdateUsageData(data));
        require(!usedMessageHashes[structHash], "Replay attack detected");
        usedMessageHashes[structHash] = true;

        address signer = ECDSA.recover(structHash, signature);
        require(
            signer == app.owner || signer == app.operator,
            "Invalid app owner or operator signature"
        );

        // Retrieve and calculate new usage
        Deployment storage deployment = deployments[appId][providerId];
        uint256 newCpu = usedCpu - deployment.usedCpu;
        uint256 newGpu = usedGpu - deployment.usedGpu;
        uint256 newUploadBytes = usedUploadBytes - deployment.usedUploadBytes;
        uint256 newDownloadBytes = usedDownloadBytes -
            deployment.usedDownloadBytes;
        uint256 newDuration = duration - deployment.duration;

        // Update the node's usage
        deployment.usedCpu = usedCpu;
        deployment.usedGpu = usedGpu;
        deployment.usedMemory = usedMemory; // Memory updates directly
        deployment.usedStorage = usedStorage;
        deployment.usedUploadBytes = usedUploadBytes;
        deployment.usedDownloadBytes = usedDownloadBytes;
        deployment.duration += newDuration;

        // Increment node count if the deployment is new
        if (!deployment.isRegistered) {
            deployment.isRegistered = true;
            app.nodeCount++;
        }

        // Calculate reward
        uint256 reward = 0;

        // Bandwidth usage (independent of duration)
        uint256 newBandwidthGB = (newUploadBytes + newDownloadBytes) / 1e9;
        reward += newBandwidthGB * app.pricePerBandwidthGB;

        // CPU and GPU usage (independent of duration)
        reward += newCpu * app.pricePerCpu;
        reward += newGpu * app.pricePerGpu;

        // Memory and Storage usage (dependent on duration)
        reward += (usedMemory / 1e9) * duration * app.pricePerMemoryGB;
        reward += (usedStorage / 1e9) * duration * app.pricePerStorageGB;

        // Ensure sufficient budget
        require(app.budget >= app.spentBudget + reward, "Insufficient budget");

        // Update pending reward
        deployment.pendingReward += reward;

        // Update the app's spent budget
        app.spentBudget += reward;

        emit UsageReported(appId, providerId, reward);
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
                        "Usage(uint256 providerId,uint256 appId,uint256 usedCpu,uint256 usedGpu,uint256 usedMemory,uint256 usedStorage,uint256 usedUploadBytes,uint256 usedDownloadBytes,uint256 duration)"
                    ),
                    data.providerId,
                    data.appId,
                    data.usedCpu,
                    data.usedGpu,
                    data.usedMemory,
                    data.usedStorage,
                    data.usedUploadBytes,
                    data.usedDownloadBytes,
                    data.duration
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
}

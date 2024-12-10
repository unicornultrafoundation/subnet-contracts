// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ISubnetRegistry.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title SubnetAppRegistry
 * @dev Registry to manage applications running on subnets and reward nodes based on resource usage.
 * Implements EIP-712 for structured data signing and Ownable for admin functionalities.
 */
contract SubnetAppRegistry is EIP712, Ownable {
    // EIP-712 Domain Separator constants
    string private constant SIGNING_DOMAIN = "SubnetAppRegistry";
    string private constant SIGNATURE_VERSION = "1";

    // Struct representing an application
    struct App {
        string peerId;
        address owner;                // Application owner
        string name;                  // Application name
        string symbol;                // Unique symbol
        uint256 budget;               // Total budget for the app
        uint256 spentBudget;          // Spent budget
        uint256 maxNodes;             // Maximum allowed nodes
        uint256 minCpu;               // Minimum CPU required
        uint256 minGpu;               // Minimum GPU required
        uint256 minMemory;            // Minimum memory required
        uint256 minUploadBandwidth;   // Minimum upload bandwidth required
        uint256 minDownloadBandwidth; // Minimum download bandwidth required
        uint256 nodeCount;            // Current active nodes
        uint256 pricePerCpu;          // Price per CPU unit
        uint256 pricePerGpu;          // Price per GPU unit
        uint256 pricePerMemoryGB;     // Price per GB of memory
        uint256 pricePerStorageGB;    // Price per GB of storage
        uint256 pricePerBandwidthGB;  // Price per GB of bandwidth
        string metadata;               // Metadata
    }

    // Struct for tracking node-specific resource usage
    struct AppNode {
        uint256 duration;             // Duration the node has been running (in seconds)
        uint256 usedCpu;
        uint256 usedGpu;
        uint256 usedMemory;
        uint256 usedStorage;
        uint256 usedDownloadBytes;
        uint256 usedUploadBytes;
        bool isRegistered;
    }

    // Struct representing resource usage for a claim
    struct Usage {
        uint256 subnetId;
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
    uint256 public appCount;                                     // Counter for applications
    mapping(uint256 => App) public apps;                        // Map app ID to App struct
    mapping(string => uint256) public symbolToAppId;            // Map symbol to app ID
    ISubnetRegistry public subnetRegistry;                      // Reference to the Subnet Registry contract
    mapping(uint256 => uint256) public nodeToAppId;             // Map node to app ID
    mapping(uint256 => mapping(uint256 => AppNode)) public appNodes; // Map app ID and subnet ID to node-specific data
    mapping(bytes32 => bool) public usedMessageHashes;          // Track used message hashes to prevent replay attacks
    address public treasury;                                    // Treasury address
    uint256 public feeRate;                                     // Fee rate in parts per thousand (e.g., 50 = 5%)

    // Events
    event AppCreated(uint256 indexed appId, string name, string symbol, address indexed owner, uint256 budget);
    event RewardClaimed(uint256 indexed appId, uint256 indexed subnetId, address indexed node, uint256 reward);
    event NodeRegistered(uint256 indexed subnetId, uint256 indexed appId, address indexed owner);

    /**
    * @dev Emitted when an application is updated.
    */
    event AppUpdated(
        uint256 appId
    );

    /**
     * @dev Constructor for initializing the contract.
     * @param _subnetRegistry Address of the Subnet Registry.
     * @param initialOwner Address of the initial owner of the contract.
     * @param _treasury Address of the treasury to collect fees.
     * @param _feeRate Fee rate as parts per thousand.
     */
    constructor(
        address _subnetRegistry,
        address initialOwner,
        address _treasury,
        uint256 _feeRate
    ) EIP712(SIGNING_DOMAIN, SIGNATURE_VERSION) Ownable(initialOwner) {
        require(_subnetRegistry != address(0), "Invalid SubnetRegistry address");
        subnetRegistry = ISubnetRegistry(_subnetRegistry);
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
    * @param budget The total budget allocated for the application (must be sent in wei).
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
        string memory metadata
    ) public payable {
        require(msg.value >= budget, "Insufficient funds for the job");
        require(maxNodes > 0, "Max nodes must be greater than zero");
        require(symbolToAppId[symbol] == 0, "Symbol already exists");

        appCount++;

        App storage app = apps[appCount];
        app.peerId = peerId;
        app.owner = msg.sender;
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

        symbolToAppId[symbol] = appCount;

        emit AppCreated(appCount, name, symbol, msg.sender, budget);
    }

    /**
    * @dev Updates an existing application with new resource requirements and payment configurations.
    * Only the owner of the application can perform the update.
    *
    * @param appId The ID of the application to update.
    * @param name The new name of the application.
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
    * @param metadata The new metadata.
    */
    function updateApp(
        uint256 appId,
        string memory name,
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
        uint256 pricePerBandwidthGB,
        string memory metadata
    ) public {
        App storage app = apps[appId];

        require(app.owner == msg.sender, "Only the owner can update the application");
        require(appId > 0 && appId <= appCount, "Application ID is invalid");
        require(maxNodes > 0, "Max nodes must be greater than zero");

        app.name = name;
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
        app.metadata = metadata;

        emit AppUpdated(
            appId
        );
    }

    /**
    * @dev Registers a node to a specific application.
    * Ensures the node meets the application's resource requirements and doesn't exceed the maximum node limit.
    *
    * @param subnetId The ID of the subnet where the node is registered.
    * @param appId The ID of the application the node wants to register for.
    */
    function registerNode(uint256 subnetId, uint256 appId) external {
        // Validate application ID
        require(appId > 0 && appId <= appCount, "Invalid App ID");

        // Fetch the application
        App storage app = apps[appId];

        // Ensure the node does not exceed the maximum node count
        require(app.nodeCount < app.maxNodes, "App has reached maximum node limit");

        // Fetch the subnet details from the SubnetRegistry
        ISubnetRegistry.Subnet memory subnet = subnetRegistry.getSubnet(subnetId);

        // Validate the subnet is active
        require(subnet.active, "Subnet is inactive");

        // Register the node to the app
        appNodes[appId][subnetId].isRegistered = true;

        // Increment the app's node count
        app.nodeCount++;

        // Emit the NodeRegistered event
        emit NodeRegistered(subnetId, appId, subnet.owner);
    }


   /**
    * @dev Claims a reward for node resources based on usage data.
    * This function calculates rewards for a node by validating its reported resource usage,
    * ensuring it's within the application's budget, and distributing rewards with fees deducted.
    *
    * @param subnetId The ID of the subnet where the node is registered.
    * @param appId The ID of the application the node is working on.
    * @param usedCpu The total CPU usage (in units) reported by the node.
    * @param usedGpu The total GPU usage (in units) reported by the node.
    * @param usedMemory The total memory usage (in GB) reported by the node.
    * @param usedStorage The total storage usage (in GB) reported by the node.
    * @param usedUploadBytes The total uploaded data (in bytes) reported by the node.
    * @param usedDownloadBytes The total downloaded data (in bytes) reported by the node.
    * @param duration The duration (in seconds) the node worked.
    * @param signature The EIP-712 signature from the application owner validating the usage data.
    */
    function claimReward(
        uint256 subnetId,
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

        // Verify subnet details and node registration
        ISubnetRegistry.Subnet memory subnet = subnetRegistry.getSubnet(subnetId);
        require(subnet.active, "Subnet inactive");
        require(subnet.owner == msg.sender, "Unauthorized node");
        require(appNodes[appId][subnetId].isRegistered, "Node not registered");

        // Hash and verify usage data
        Usage memory data = Usage({
            subnetId: subnetId,
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
        require(signer == app.owner, "Invalid app owner signature");

        // Retrieve and calculate new usage
        AppNode storage appNode = appNodes[appId][subnetId];
        uint256 newCpu = usedCpu - appNode.usedCpu;
        uint256 newGpu = usedGpu - appNode.usedGpu;
        uint256 newUploadBytes = usedUploadBytes - appNode.usedUploadBytes;
        uint256 newDownloadBytes = usedDownloadBytes - appNode.usedDownloadBytes;
        uint256 newDuration = duration - appNode.duration;

        // Update the node's usage
        appNode.usedCpu = usedCpu;
        appNode.usedGpu = usedGpu;
        appNode.usedMemory = usedMemory; // Memory updates directly
        appNode.usedStorage = usedStorage; // Storage updates directly
        appNode.usedUploadBytes = usedUploadBytes;
        appNode.usedDownloadBytes = usedDownloadBytes;
        appNode.duration += newDuration;

        // Calculate reward
        uint256 reward = 0;

        // Bandwidth usage (independent of duration)
        uint256 newBandwidthGB = (newUploadBytes + newDownloadBytes) / 1e9;
        reward += newBandwidthGB * app.pricePerBandwidthGB;

        // CPU and GPU usage (independent of duration)
        reward += newCpu * app.pricePerCpu;
        reward += newGpu * app.pricePerGpu;

        // Memory and Storage usage (dependent on duration)
        reward += usedMemory / 1e9 * duration * app.pricePerMemoryGB;
        reward += usedStorage/ 1e9 * duration * app.pricePerStorageGB;

        // Ensure sufficient budget
        require(app.budget >= app.spentBudget + reward, "Insufficient budget");

        // Update budget and transfer rewards
        app.spentBudget += reward;
        uint256 fee = (reward * feeRate) / 1000;
        uint256 netReward = reward - fee;

        payable(treasury).transfer(fee);
        payable(msg.sender).transfer(netReward);

        emit RewardClaimed(appId, subnetId, msg.sender, reward);
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
    function listApps(uint256 start, uint256 end) external view returns (App[] memory) {
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
    function _hashUpdateUsageData(Usage memory data) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256(
                    "Usage(uint256 subnetId,uint256 appId,uint256 usedCpu,uint256 usedGpu,uint256 usedMemory,uint256 usedStorage,uint256 usedUploadBytes,uint256 usedDownloadBytes,uint256 duration)"
                ),
                data.subnetId,
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
    * @param subnetId The ID of the subnet (node) to fetch details for.
    * @return appNode The AppNode struct containing the node's usage details.
    */
    function getAppNode(uint256 appId, uint256 subnetId) external view returns (AppNode memory appNode) {
        // Ensure the application exists
        require(apps[appId].owner != address(0), "App does not exist");

        // Ensure the node is registered to the app
        require(appNodes[appId][subnetId].isRegistered, "Node not registered to this app");

        // Return the AppNode struct
        return appNodes[appId][subnetId];
    }

    function version() public pure returns (string memory) {
        return "1.0.0";
    }
}

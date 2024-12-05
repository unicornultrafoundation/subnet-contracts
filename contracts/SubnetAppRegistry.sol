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

    // Enum for payment methods
    enum PaymentMethod {
        DURATION,          // Payment based on duration
        PAY_AS_YOU_USE     // Payment based on actual resource usage
    }

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
        PaymentMethod paymentMethod;  // Payment method
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
    * @param paymentMethod The payment method (DURATION or PAY_AS_YOU_USE).
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
        PaymentMethod paymentMethod
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
        app.paymentMethod = paymentMethod;

        symbolToAppId[symbol] = appCount;

        emit AppCreated(appCount, name, symbol, msg.sender, budget);
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
        // Validate the application ID
        require(appId > 0 && appId <= appCount, "Invalid App ID");
        App storage app = apps[appId];
        
        // Ensure the application's budget is not exhausted
        require(app.budget > app.spentBudget, "App budget exhausted");

        // Retrieve subnet details from the Subnet Registry
        ISubnetRegistry.Subnet memory subnet = subnetRegistry.subnets(subnetId);
        require(subnet.active, "Node in SubnetRegistry is inactive");
        require(subnet.owner == msg.sender, "Unauthorized node");

        // Validate that the node is registered with the application
        require(nodeToAppId[subnetId] == appId, "Node not registered with this app");

        // Create a `Usage` struct containing the reported resource usage
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

        // Generate the EIP-712 typed data hash
        bytes32 structHash = _hashTypedDataV4(_hashUpdateUsageData(data));
        
        // Check if the hash has already been used
        require(!usedMessageHashes[structHash], "Replay attack detected: hash already used");

         // Mark the hash as used
        usedMessageHashes[structHash] = true;
        
        // Recover the address of the signer (App Owner) from the provided signature
        address signer = ECDSA.recover(structHash, signature);
        require(signer == app.owner, "Invalid app owner signature");

        // Retrieve the node-specific resource usage data
        AppNode storage appNode = appNodes[appId][subnetId];

        // Calculate the new resource usage (difference between reported and previous usage)
        uint256 newCpu = usedCpu > appNode.usedCpu ? usedCpu - appNode.usedCpu : 0;
        uint256 newGpu = usedGpu > appNode.usedGpu ? usedGpu - appNode.usedGpu : 0;
        uint256 newMemory = usedMemory > appNode.usedMemory ? usedMemory - appNode.usedMemory : 0;
        uint256 newStorage = usedStorage > appNode.usedStorage ? usedStorage - appNode.usedStorage : 0;
        uint256 newUploadBytes = usedUploadBytes > appNode.usedUploadBytes ? usedUploadBytes - appNode.usedUploadBytes : 0;
        uint256 newDownloadBytes = usedDownloadBytes > appNode.usedDownloadBytes ? usedDownloadBytes - appNode.usedDownloadBytes : 0;
        uint256 newDuration = duration > appNode.duration ? duration - appNode.duration : 0;

        // Update the node's resource usage data
        appNode.usedCpu += newCpu;
        appNode.usedGpu += newGpu;
        appNode.usedMemory += newMemory;
        appNode.usedStorage += newStorage;
        appNode.usedUploadBytes += newUploadBytes;
        appNode.usedDownloadBytes += newDownloadBytes;
        appNode.duration += newDuration;

        // Calculate the reward
        uint256 reward = 0;

        // Reward for bandwidth usage (convert bytes to GB)
        uint256 newBandwidthGB = (newUploadBytes + newDownloadBytes) / (1e9);
        reward += newBandwidthGB * app.pricePerBandwidthGB;

        // Reward for CPU, GPU, memory, and storage usage
        reward += newCpu * app.pricePerCpu;
        reward += newGpu * app.pricePerGpu;
        reward += newMemory * app.pricePerMemoryGB;
        reward += newStorage * app.pricePerStorageGB;

        // Adjust reward for duration-based payment
        if (app.paymentMethod == PaymentMethod.DURATION) {
            reward = newDuration * reward;
        }

        // Ensure the application has enough budget for this reward
        require(app.budget >= app.spentBudget + reward, "Insufficient budget for reward");

        // Update the application's spent budget
        app.spentBudget += reward;

        // Calculate the fee to be sent to the treasury
        uint256 fee = (reward * feeRate) / 1000;
        uint256 netReward = reward - fee;

        // Transfer the fee to the treasury
        payable(treasury).transfer(fee);

        // Transfer the remaining reward to the node
        payable(msg.sender).transfer(netReward);

        // Emit an event for the reward claim
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
     * @dev Overrides the domain separator function for EIP-712.
     */
    function _domainSeparatorV4() internal view override returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256(bytes(SIGNING_DOMAIN)),
                keccak256(bytes(SIGNATURE_VERSION)),
                block.chainid,
                address(this)
            )
        );
    }
}

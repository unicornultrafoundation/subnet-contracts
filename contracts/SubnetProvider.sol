// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title SubnetProvider
 * @dev Contract for subnet providers to register themselves and their machines
 * Also functions as an ERC721 contract for provider NFTs
 */
contract SubnetProvider is Initializable, OwnableUpgradeable, ERC721URIStorageUpgradeable {
    using SafeERC20 for IERC20;

    // Constants become state variable that can be updated by owner
    uint256 public lockPeriod;  // Lock period in seconds (default: 3 weeks)

    // Structures
    struct Provider {
        address operator; // Address of the provider's operator
        bool registered;
        uint256 reputation;
        uint256 machineCount;
        uint256 createdAt;
        uint256 updatedAt;
        uint256 totalStaked;      // Total amount staked by provider
        uint256 pendingWithdrawals; // Amount scheduled for withdrawal
        uint256 slashedAmount;    // Total amount slashed from provider
        uint256 tokenId;          // NFT token ID for this provider
        string metadata;       // Additional metadata URI
        bool isSlashed;         // Whether the provider has been slashed
        bool isActive;          // Whether the provider is currently active
    }

    struct Machine {
        bool active;             // Whether the machine is currently active
        uint256 machineType;
        uint256 region;
        // Detailed resource specifications
        uint256 cpuCores;    // Number of CPU cores
        uint256 cpuSpeed;    // CPU speed in MHz
        uint256 gpuCores;    // GPU cores (0 if no GPU)
        uint256 gpuMemory;   // GPU memory in MB
        uint256 memoryMB;    // RAM in MB
        uint256 diskGB;      // Storage in GB
        uint256 uploadSpeed; // Upload speed in Mbps (optional)
        uint256 downloadSpeed; // Download speed in Mbps (optional)
        uint256 publicIp;     // Public IP address
        uint256 overlayIp;    // Overlay network IP address
        uint256 createdAt;
        uint256 updatedAt;
        uint256 stakeAmount; // Amount staked for this machine
        uint256 removedAt;   // When machine was removed (0 if still active)
        uint256 unlockTime;  // When stake can be withdrawn after removal
        bool withdrawalProcessed; // Whether withdrawal has been processed
        string metadata;     // Additional metadata for the machine
    }

    // State variables
    mapping(uint256 => Provider) public providers;
    mapping(uint256 => Machine[]) public providerMachines;

    // Staking related variables
    address public stakingToken;
    uint256 public baseStakeAmount;      // Base amount for any machine
    uint256 public totalSlashed;         // Total amount slashed
    
    // Resource stake rates
    uint256 public cpuStakeRate;         // Tokens per CPU core
    uint256 public gpuStakeRate;         // Tokens per GPU core
    uint256 public memoryStakeRate;      // Tokens per GB of memory
    uint256 public diskStakeRate;        // Tokens per GB of disk
    uint256 public uploadSpeedStakeRate;  // Tokens per Mbps of upload speed
    uint256 public downloadSpeedStakeRate; // Tokens per Mbps of download speed

    // Counter for NFT token IDs
    uint256 private _nextTokenId;

    // Events
    event ProviderUpdated(uint256 indexed providerId);
    event MachineAdded(uint256 indexed providerId, uint256 machineId, uint256 stakedAmount);
    event MachineUpdated(uint256 indexed providerId, uint256 machineId, uint256 additionalStake);
    event MachineRemoved(uint256 indexed providerId, uint256 machineId, uint256 unlocktime);
    event StakeSlashed(uint256 indexed providerId, uint256 machineId, uint256 amount, string reason);
    event StakeWithdrawn(uint256 indexed providerId, uint256 machineId, uint256 amount);
    event LockPeriodUpdated(uint256 oldPeriod, uint256 newPeriod);
    event StakeParametersUpdated(
        uint256 baseAmount, 
        uint256 cpuRate, 
        uint256 gpuRate, 
        uint256 memoryRate, 
        uint256 diskRate,
        uint256 uploadSpeedRate,
        uint256 downloadSpeedRate
    );

    /**
     * @dev Initialize the contract
     */
    function initialize(address owner, address _stakingToken, string memory nftName, string memory nftSymbol) external initializer {
        __Ownable_init(owner);
        __ERC721_init(nftName, nftSymbol);
        __ERC721URIStorage_init();
        
        stakingToken = _stakingToken;
        _nextTokenId = 1; // Start token IDs from 1
        
        // Set default stake parameters with more accurate resource pricing
        baseStakeAmount = 500 * 10**18;  // Base stake for participating (500 tokens)
        cpuStakeRate = 100 * 10**18;     // 100 tokens per CPU core
        gpuStakeRate = 1000 * 10**18;    // 1000 tokens per GPU core (premium resource)
        memoryStakeRate = 20 * 10**18;   // 20 tokens per GB of RAM
        diskStakeRate = 2 * 10**18;      // 2 tokens per GB of disk
        uploadSpeedStakeRate = 10 * 10**18;  // 10 tokens per Mbps upload (premium for good upload)
        downloadSpeedStakeRate = 5 * 10**18; // 5 tokens per Mbps download
        
        lockPeriod = 3 weeks; // Default 3 weeks lock period
    }

    /**
     * @dev Update stake parameters (owner only)
     * @param newBaseStakeAmount New base stake amount
     * @param newCpuStakeRate New CPU stake rate (tokens per core)
     * @param newGpuStakeRate New GPU stake rate (tokens per core)
     * @param newMemoryStakeRate New memory stake rate (tokens per GB)
     * @param newDiskStakeRate New disk stake rate (tokens per GB)
     * @param newUploadSpeedStakeRate New upload speed stake rate (tokens per Mbps)
     * @param newDownloadSpeedStakeRate New download speed stake rate (tokens per Mbps)
     */
    function setStakeParameters(
        uint256 newBaseStakeAmount,
        uint256 newCpuStakeRate,
        uint256 newGpuStakeRate,
        uint256 newMemoryStakeRate,
        uint256 newDiskStakeRate,
        uint256 newUploadSpeedStakeRate,
        uint256 newDownloadSpeedStakeRate
    ) external onlyOwner {
        baseStakeAmount = newBaseStakeAmount;
        cpuStakeRate = newCpuStakeRate;
        gpuStakeRate = newGpuStakeRate;
        memoryStakeRate = newMemoryStakeRate;
        diskStakeRate = newDiskStakeRate;
        uploadSpeedStakeRate = newUploadSpeedStakeRate;
        downloadSpeedStakeRate = newDownloadSpeedStakeRate;
        
        emit StakeParametersUpdated(
            newBaseStakeAmount,
            newCpuStakeRate,
            newGpuStakeRate,
            newMemoryStakeRate,
            newDiskStakeRate,
            newUploadSpeedStakeRate,
            newDownloadSpeedStakeRate
        );
    }

    /**
     * @dev Update the lock period (owner only)
     * @param newLockPeriod New lock period in seconds
     */
    function setLockPeriod(uint256 newLockPeriod) external onlyOwner {
        require(newLockPeriod > 0, "Lock period must be positive");
        uint256 oldPeriod = lockPeriod;
        lockPeriod = newLockPeriod;
        emit LockPeriodUpdated(oldPeriod, newLockPeriod);
    }

    /**
     * @dev Calculate required stake based on machine resources
     * @param cpuCores Number of CPU cores
     * @param gpuCores Number of GPU cores
     * @param memoryMB Memory in MB
     * @param diskGB Storage in GB
     * @param uploadSpeed Upload speed in Mbps
     * @param downloadSpeed Download speed in Mbps
     */
    function calculateRequiredStake(
        uint256 cpuCores, 
        uint256 gpuCores, 
        uint256 memoryMB, 
        uint256 diskGB,
        uint256 uploadSpeed,
        uint256 downloadSpeed
    ) public view returns (uint256) {
        // Calculate stake using configurable rates
        uint256 cpuStake = cpuCores * cpuStakeRate;
        uint256 gpuStake = gpuCores * gpuStakeRate;
        uint256 memoryStake = (memoryMB * memoryStakeRate) / 1024; // Convert MB to GB
        uint256 diskStake = diskGB * diskStakeRate;
        uint256 uploadSpeedStake = uploadSpeed * uploadSpeedStakeRate;
        uint256 downloadSpeedStake = downloadSpeed * downloadSpeedStakeRate;
        
        uint256 resourceStake = cpuStake + gpuStake + memoryStake + diskStake + uploadSpeedStake + downloadSpeedStake;
        return baseStakeAmount + resourceStake;
    }

    /**
     * @dev Register a new provider and mint NFT
     * @param metadata Provider metadata
     * @return The token ID of the minted NFT
     */
    function registerProvider(
        address operator,
        string memory metadata
    ) external returns (uint256) {        
        // Mint NFT for the provider
        uint256 tokenId = _nextTokenId++;
        _mint(msg.sender, tokenId);

        providers[tokenId] = Provider({
            operator: operator,
            registered: true,
            metadata: metadata,
            reputation: 0,
            machineCount: 0,
            createdAt: block.timestamp,
            updatedAt: block.timestamp,
            totalStaked: 0,
            pendingWithdrawals: 0,
            slashedAmount: 0,
            tokenId: tokenId,
            isSlashed: false,
            isActive: true
            
        });

        return tokenId;
    }

    /**
     * @dev Update provider information
     * @param metadata Updated provider metadata
     */
    function updateProviderInfo(
        uint256 providerId,
        string memory metadata
    ) external {
        require(providers[providerId].registered, "Provider not registered");
        require(ownerOf(providerId) == msg.sender, "Only token owner can update provider info");

        Provider storage provider = providers[providerId];
        provider.metadata = metadata;
        provider.updatedAt = block.timestamp;

        emit ProviderUpdated(providerId);
    }

    /**
     * @dev Add a new machine for the provider with staking
     * @param providerId Provider ID
     * @param machineType Type of virtualization
     * @param region Location information
     * @param cpuCores Number of CPU cores
     * @param cpuSpeed CPU speed in MHz
     * @param gpuCores Number of GPU cores
     * @param gpuMemory GPU memory in MB
     * @param memoryMB RAM in MB
     * @param diskGB Storage in GB
     * @param publicIp Public IP address
     * @param overlayIp Overlay network IP address
     * @param metadata Additional metadata for the machine
     * @return machineId ID of the newly added machine
     */
    function addMachine(
        uint256 providerId,
        uint256 machineType, 
        uint256 region,
        uint256 cpuCores,
        uint256 cpuSpeed,
        uint256 gpuCores,
        uint256 gpuMemory,
        uint256 memoryMB,
        uint256 diskGB,
        uint256 publicIp,
        uint256 overlayIp,
        uint256 uploadSpeed,
        uint256 downloadSpeed,
        string memory metadata
    ) external returns (uint256) {
        require(providers[providerId].registered, "Provider not registered");
        require(!providers[providerId].isSlashed, "Provider is slashed");
        require(ownerOf(providerId) == msg.sender, "Only token owner can add machine");

        // Calculate required stake amount based on resources
        uint256 requiredStake = calculateRequiredStake(
            cpuCores,
            gpuCores,
            memoryMB,
            diskGB,
            uploadSpeed,
            downloadSpeed
        );
        
        // Transfer stake from provider to contract
        IERC20(stakingToken).safeTransferFrom(msg.sender, address(this), requiredStake);

        Provider storage provider = providers[providerId];
        uint256 machineId = provider.machineCount;

        Machine memory machine = Machine({
            active: true,
            machineType: machineType,
            region: region,
            cpuCores: cpuCores,
            cpuSpeed: cpuSpeed,
            gpuCores: gpuCores,
            gpuMemory: gpuMemory,
            memoryMB: memoryMB,
            diskGB: diskGB,
            publicIp: publicIp,
            overlayIp: overlayIp,
            createdAt: block.timestamp,
            updatedAt: block.timestamp,
            stakeAmount: requiredStake,
            removedAt: 0,
            unlockTime: 0,
            withdrawalProcessed: false,
            metadata: metadata,
            uploadSpeed: uploadSpeed,
            downloadSpeed: downloadSpeed
        });

        providerMachines[providerId].push(machine);
        provider.machineCount++;
        provider.updatedAt = block.timestamp;
        provider.totalStaked += requiredStake;

        emit MachineAdded(providerId, machineId, requiredStake);
        return machineId;
    }

    /**
     * @dev Update machine details with potential restaking
     */
    function updateMachine(
        uint256 providerId,
        uint256 machineId,
        uint256 cpuCores,
        uint256 cpuSpeed,
        uint256 gpuCores,
        uint256 gpuMemory,
        uint256 memoryMB,
        uint256 diskGB,
        uint256 publicIp,
        uint256 overlayIp,
        uint256 uploadSpeed,
        uint256 downloadSpeed,
        string memory metadata
    ) external {
        require(providers[providerId].registered, "Provider not registered");
        require(!providers[providerId].isSlashed, "Provider is slashed");
        require(ownerOf(providerId) == msg.sender, "Only token owner can update machine");
        require(machineId < providers[providerId].machineCount, "Invalid machine ID");

        Machine storage machine = providerMachines[providerId][machineId];
        Provider storage provider = providers[providerId];

        // Calculate new required stake
        uint256 newRequiredStake = calculateRequiredStake(
            cpuCores,
            gpuCores, 
            memoryMB,
            diskGB,
            uploadSpeed,
            downloadSpeed
        );
        uint256 currentStake = machine.stakeAmount;
        
        // Only allow updates that maintain or increase resources/stake
        require(newRequiredStake >= currentStake, "Cannot downgrade machine resources");
        
        uint256 additionalStake = newRequiredStake - currentStake;
        IERC20(stakingToken).safeTransferFrom(msg.sender, address(this), additionalStake);
        provider.totalStaked += additionalStake;
        
        // Update machine details
        machine.cpuCores = cpuCores;
        machine.cpuSpeed = cpuSpeed;
        machine.gpuCores = gpuCores;
        machine.gpuMemory = gpuMemory;
        machine.memoryMB = memoryMB;
        machine.diskGB = diskGB;
        machine.publicIp = publicIp;
        machine.overlayIp = overlayIp;
        machine.metadata = metadata;
        machine.updatedAt = block.timestamp;
        machine.stakeAmount = newRequiredStake;
        machine.uploadSpeed = uploadSpeed;
        machine.downloadSpeed = downloadSpeed;
        
        provider.updatedAt = block.timestamp;

        emit MachineUpdated(providerId, machineId, additionalStake);
    }

    /**
     * @dev Remove a machine and set unlock time for stake withdrawal
     * @param machineId ID of the machine to remove
     */
    function removeMachine(uint256 providerId, uint256 machineId) external {
        require(providers[providerId].registered, "Provider not registered");
        require(ownerOf(providerId) == msg.sender, "Only token owner can remove machine");
        require(machineId < providers[providerId].machineCount, "Invalid machine ID");

        Machine storage machine = providerMachines[providerId][machineId];
        Provider storage provider = providers[providerId];

        // Set unlock time with current lock period
        uint256 stakedAmount = machine.stakeAmount;
        uint256 unlockTime = block.timestamp + lockPeriod;
        
        provider.pendingWithdrawals += stakedAmount;
        provider.totalStaked -= stakedAmount;
        
        // Mark machine as removed and set unlock time
        machine.active = false;
        machine.removedAt = block.timestamp;
        machine.unlockTime = unlockTime;
        machine.withdrawalProcessed = false;
        machine.updatedAt = block.timestamp;
        
        provider.updatedAt = block.timestamp;

        emit MachineRemoved(providerId, machineId, unlockTime);
    }

    /**
     * @dev Claim withdrawable stake after lock period
     * @param machineId ID of the machine whose stake to withdraw
     */
    function claimWithdrawal(uint256 providerId, uint256 machineId) external {
        require(providers[providerId].registered, "Provider not registered");
        require(!providers[providerId].isSlashed, "Provider is slashed");
        require(machineId < providerMachines[providerId].length, "Invalid machine ID");

        Machine storage machine = providerMachines[providerId][machineId];
        require(!machine.active, "Machine still active");
        require(!machine.withdrawalProcessed, "Already processed");
        require(block.timestamp >= machine.unlockTime, "Still locked");
        
        uint256 amount = machine.stakeAmount;
        machine.withdrawalProcessed = true;

        providers[providerId].pendingWithdrawals -= amount;
        providers[providerId].machineCount--;

        IERC20(stakingToken).safeTransfer(msg.sender, amount);
        emit StakeWithdrawn(providerId, machineId, amount);
    }

    /**
     * @dev Admin function to slash stake from a machine (penalize bad behavior)
     * @param providerId ID of the provider
     * @param machineId ID of the machine
     * @param amount Amount to slash
     * @param reason Reason for slashing
     */
    function slashStake(
        uint256 providerId,
        uint256 machineId,
        uint256 amount,
        string memory reason
    ) external onlyOwner {
        require(providers[providerId].registered, "Provider not registered");
        require(machineId < providers[providerId].machineCount, "Invalid machine ID");

        Machine storage machine = providerMachines[providerId][machineId];
        require(machine.stakeAmount >= amount, "Cannot slash more than staked");

        Provider storage provider = providers[providerId];

        // Reduce stake and record slashing
        machine.stakeAmount -= amount;
        provider.totalStaked -= amount;
        provider.slashedAmount += amount;
        provider.isSlashed = true;
        provider.isActive = false;
        totalSlashed += amount;

        emit StakeSlashed(providerId, machineId, amount, reason);
    }
    
    /**
     * @dev Admin function to withdraw slashed funds
     * @param recipient Address to receive slashed funds
     * @param amount Amount to withdraw
     */
    function withdrawSlashedFunds(address recipient, uint256 amount) external onlyOwner {
        require(amount <= totalSlashed, "Amount exceeds slashed funds");
        
        totalSlashed -= amount;
        IERC20(stakingToken).safeTransfer(recipient, amount);
    }

    /**
     * @dev Get provider's slashed amount
     * @param providerId ID of the provider
     * @return Total slashed from provider
     */
    function getProviderSlashedAmount(uint256 providerId) external view returns (uint256) {
        return providers[providerId].slashedAmount;
    }
    
    /**
     * @dev Get all machines for a provider
     * @param providerId ID of the provider
     * @return Array of Machine structs
     */
    function getMachines(uint256 providerId) external view returns (Machine[] memory) {
        return providerMachines[providerId];
    }
    
    /**
     * @dev Get machines for a provider with pagination
     * @param providerId ID of the provider
     * @param start Starting index
     * @param end Ending index (exclusive)
     * @return Array of Machine structs within the specified range
     */
    function getMachinesPaginated(uint256 providerId, uint256 start, uint256 end) external view returns (Machine[] memory) {
        require(providers[providerId].registered, "Provider not registered");
        require(!providers[providerId].isSlashed, "Provider is slashed");
        require(start <= end, "Invalid range: start must be <= end");
        require(end <= providerMachines[providerId].length, "End index out of bounds");
        
        uint256 length = end - start;
        Machine[] memory result = new Machine[](length);
        
        for (uint256 i = 0; i < length; i++) {
            result[i] = providerMachines[providerId][start + i];
        }
        
        return result;
    }
    
    /**
     * @dev Get active machines for a provider with pagination
     * @param providerId ID of the provider
     * @param start Starting index
     * @param limit Maximum number of active machines to return
     * @return Array of active Machine structs
     */
    function getActiveMachinesPaginated(uint256 providerId, uint256 start, uint256 limit) external view returns (Machine[] memory) {
        require(providers[providerId].registered, "Provider not registered");
        require(!providers[providerId].isSlashed, "Provider is slashed");
        require(start < providerMachines[providerId].length, "Start index out of bounds");
        
        // Count active machines first to allocate properly sized array
        uint256 activeCount = 0;
        for (uint256 i = 0; i < providerMachines[providerId].length; i++) {
            if (providerMachines[providerId][i].active) {
                activeCount++;
            }
        }
        
        uint256 resultSize = activeCount < limit ? activeCount : limit;
        Machine[] memory result = new Machine[](resultSize);
        
        // Fill result array with active machines
        uint256 resultIndex = 0;
        uint256 skipped = 0;
        for (uint256 i = 0; i < providerMachines[providerId].length && resultIndex < resultSize; i++) {
            if (providerMachines[providerId][i].active) {
                if (skipped >= start) {
                    result[resultIndex] = providerMachines[providerId][i];
                    resultIndex++;
                } else {
                    skipped++;
                }
            }
        }
        
        return result;
    }
    
    /**
     * @dev Check if address is provider owner or operator
     * @param providerId ID of the provider
     * @param account Address to check
     * @return True if address is provider owner or operator
     */
    function isProviderOperatorOrOwner(uint256 providerId, address account) public view returns (bool) {
        require(providers[providerId].registered, "Provider not registered");
        
        // Check if the account is the owner of the token
        bool isOwner = ownerOf(providerId) == account;
        
        // Check if the account is the designated operator
        bool isOperator = providers[providerId].operator == account;
        
        return isOwner || isOperator;
    }
    
    /**
     * @dev Modifier to restrict function to provider owner or operator
     */
    modifier onlyProviderOperatorOrOwner(uint256 providerId) {
        require(isProviderOperatorOrOwner(providerId, msg.sender), "Not provider owner or operator");
        _;
    }

    /**
     * @dev Update provider operator address
     * @param providerId Provider ID
     * @param newOperator New operator address
     */
    function setProviderOperator(uint256 providerId, address newOperator) external {
        require(ownerOf(providerId) == msg.sender, "Only token owner can set operator");
        require(!providers[providerId].isSlashed, "Provider is slashed");
        providers[providerId].operator = newOperator;
        providers[providerId].updatedAt = block.timestamp;
    }

    /**
     * @dev Check if a machine is currently active
     * @param providerId ID of the provider
     * @param machineId ID of the machine
     * @return True if the machine is active, false otherwise
     */
    function isMachineActive(uint256 providerId, uint256 machineId) external view returns (bool) {
        return providers[providerId].registered && 
            !providers[providerId].isSlashed && 
            machineId < providerMachines[providerId].length && 
            providerMachines[providerId][machineId].active;
    }
    
    /**
     * @dev Validate if a machine meets minimum requirements
     * @param providerId ID of the provider
     * @param machineId ID of the machine
     * @param minCpuCores Minimum CPU cores required
     * @param minMemoryMB Minimum memory required
     * @param minDiskGB Minimum disk space required
     * @param minGpuCores Minimum GPU cores required
     * @return True if machine meets requirements
     */
    function validateMachineRequirements(
        uint256 providerId,
        uint256 machineId,
        uint256 minCpuCores,
        uint256 minMemoryMB,
        uint256 minDiskGB,
        uint256 minGpuCores,
        uint256 minUploadSpeed,
        uint256 minDownloadSpeed
    ) external view returns (bool) {
        // Check if provider and machine exist
        if (!providers[providerId].registered || providers[providerId].isSlashed || machineId >= providerMachines[providerId].length) {
            return false;
        }
        
        Machine memory machine = providerMachines[providerId][machineId];
        
        // Machine must be active and meet all requirements
        return machine.active &&
               machine.cpuCores >= minCpuCores &&
               machine.memoryMB >= minMemoryMB &&
               machine.diskGB >= minDiskGB &&
               machine.gpuCores >= minGpuCores &&
               machine.uploadSpeed >= minUploadSpeed &&
               machine.downloadSpeed >= minDownloadSpeed;
    }
    
    /**
     * @dev Get provider details
     * @param providerId ID of the provider
     * @return provider Provider struct with details
     */
    function getProvider(uint256 providerId) external view returns (Provider memory provider ) {
        return providers[providerId];
    }

    /**
     * @dev Get provider owner address
     * @param providerId ID of the provider
     * @return Address of the provider's NFT owner
     */
    function getProviderOwner(uint256 providerId) external view returns (address) {
        return ownerOf(providerId);
    }
}




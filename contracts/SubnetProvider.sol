// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title SubnetProvider
 * @dev Contract for subnet providers to register themselves and their machines
 * Also functions as an ERC721 contract for provider NFTs
 */
contract SubnetProvider is Initializable, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    // Constants become state variable that can be updated by owner
    uint256 public lockPeriod;  // Lock period in seconds (default: 3 weeks)

    // Structures
    struct Provider {
        address operator; // Address of the provider's operator
        address owner;    // Provider owner address (identifier)
        bool registered;
        uint256 reputation; // Reputation score (0-100)
        uint256 createdAt;
        uint256 updatedAt;
        uint256 totalStaked;      // Total amount staked by provider (current active stake)
        uint256 pendingWithdrawals; // Amount scheduled for withdrawal (once deactivated)
        uint256 slashedAmount;    // Total amount slashed from provider over time
        string metadata;          // Additional metadata URI
        bool isSlashed;           // Whether the provider has been slashed (at least once)
        bool isActive;            // Whether the provider is currently active
        bool verified;            // Verification status (renamed from isProviderVerified)
        // Unified "machine" specifications for this provider
        uint256 machineType;
        uint256 region;
        uint256 cpuCores;
        uint256 gpuCores;
        uint256 gpuMemory;
        uint256 memoryMB;
        uint256 diskGB;
        // Pricing (per second)
        uint256 cpuPricePerSecond;
        uint256 gpuPricePerSecond;
        uint256 memoryPricePerSecond;
        uint256 diskPricePerSecond;
        // Lifecycle of the active stake
        uint256 stakeAmount;      // Stake backing the active provider specs
        uint256 removedAt;        // Timestamp when deactivated (0 if active)
        uint256 unlockTime;       // When stake becomes withdrawable
        bool withdrawalProcessed; // Whether withdrawal has been processed
    }

    // State variables
    mapping(address => Provider) public providers;

    // Staking related variables
    address public stakingToken;
    uint256 public baseStakeAmount;      // Base amount for any machine
    uint256 public totalSlashed;         // Total amount slashed
    
    // Resource stake rates
    uint256 public cpuStakeRate;         // Tokens per CPU core
    uint256 public gpuStakeRate;         // Tokens per GPU core
    uint256 public memoryStakeRate;      // Tokens per GB of memory
    uint256 public diskStakeRate;        // Tokens per GB of disk

    // Resource locking for orders
    struct LockedResources {
        uint256 cpuCores;
        uint256 gpuCores;
        uint256 memoryMB;
        uint256 diskGB;
    }
    mapping(address => LockedResources) public lockedResources; // provider => locked resources
    mapping(address => bool) public authorizedLockers; // locker address => authorized (global for all providers)

    // Events
    event ProviderUpdated(address indexed provider);
    event ProviderRegistered(address indexed provider, uint256 stakedAmount);
    event ProviderSpecsUpdated(address indexed provider, uint256 additionalStake);
    event ProviderDeactivated(address indexed provider, uint256 unlocktime);
    event StakeSlashed(address indexed provider, uint256 amount, string reason);
    event StakeWithdrawn(address indexed provider, uint256 amount);
    event LockPeriodUpdated(uint256 oldPeriod, uint256 newPeriod);
    event StakeParametersUpdated(
        uint256 baseAmount, 
        uint256 cpuRate, 
        uint256 gpuRate, 
        uint256 memoryRate, 
        uint256 diskRate
    );
    event ResourcePriceUpdated(
        address indexed provider,
        uint256 cpuPricePerSecond,
        uint256 gpuPricePerSecond,
        uint256 memoryPricePerSecond,
        uint256 diskPricePerSecond
    );
    event ProviderVerified(address indexed providerId, bool verified);
    event ProviderReputationUpdated(address indexed providerId, uint256 newReputation);
    event ResourcesLocked(address indexed provider, uint256 cpuCores, uint256 gpuCores, uint256 memoryMB, uint256 diskGB);
    event ResourcesUnlocked(address indexed provider, uint256 cpuCores, uint256 gpuCores, uint256 memoryMB, uint256 diskGB);

    /**
     * @dev Initialize the contract
     */
    function initialize(address owner, address _stakingToken) external initializer {
        __Ownable_init(owner);
        
        stakingToken = _stakingToken;
        
        // Set default stake parameters with more accurate resource pricing
        baseStakeAmount = 500 * 10**18;  // Base stake for participating (500 tokens)
        cpuStakeRate = 100 * 10**18;     // 100 tokens per CPU core
        gpuStakeRate = 1000 * 10**18;    // 1000 tokens per GPU core (premium resource)
        memoryStakeRate = 20 * 10**18;   // 20 tokens per GB of RAM
        diskStakeRate = 2 * 10**18;      // 2 tokens per GB of disk
        
        lockPeriod = 3 weeks; // Default 3 weeks lock period
    }

    /**
     * @dev Update stake parameters (owner only)
     * @param newBaseStakeAmount New base stake amount
     * @param newCpuStakeRate New CPU stake rate (tokens per core)
     * @param newGpuStakeRate New GPU stake rate (tokens per core)
     * @param newMemoryStakeRate New memory stake rate (tokens per GB)
     * @param newDiskStakeRate New disk stake rate (tokens per GB)
     */
    function setStakeParameters(
        uint256 newBaseStakeAmount,
        uint256 newCpuStakeRate,
        uint256 newGpuStakeRate,
        uint256 newMemoryStakeRate,
        uint256 newDiskStakeRate
    ) external onlyOwner {
        baseStakeAmount = newBaseStakeAmount;
        cpuStakeRate = newCpuStakeRate;
        gpuStakeRate = newGpuStakeRate;
        memoryStakeRate = newMemoryStakeRate;
        diskStakeRate = newDiskStakeRate;
        
        emit StakeParametersUpdated(
            newBaseStakeAmount,
            newCpuStakeRate,
            newGpuStakeRate,
            newMemoryStakeRate,
            newDiskStakeRate
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
     * @dev Calculate required stake based on resources and pricing.
     *      Requirement: at least stake the estimated 1-month revenue.
     * @param cpuCores Number of CPU cores
     * @param gpuCores Number of GPU cores
     * @param memoryMB Memory in MB
     * @param diskGB Storage in GB
     * @param cpuPricePerSecond CPU price per second
     * @param gpuPricePerSecond GPU price per second
     * @param memoryPricePerSecond Memory price per second
     * @param diskPricePerSecond Disk price per second
     */
    function calculateRequiredStake(
        uint256 cpuCores, 
        uint256 gpuCores, 
        uint256 memoryMB, 
        uint256 diskGB,
        uint256 cpuPricePerSecond,
        uint256 gpuPricePerSecond,
        uint256 memoryPricePerSecond,
        uint256 diskPricePerSecond
    ) public view returns (uint256) {
        // Stake floor from resource configuration
        uint256 cpuStake = cpuCores * cpuStakeRate;
        uint256 gpuStake = gpuCores * gpuStakeRate;
        uint256 memoryStake = (memoryMB * memoryStakeRate) / 1024; // Convert MB to GB
        uint256 diskStake = diskGB * diskStakeRate;
        uint256 resourceStake = cpuStake + gpuStake + memoryStake + diskStake;

        // Estimated revenue per second from pricing
        uint256 memoryGB = memoryMB / 1024;
        uint256 revenuePerSecond = (cpuCores * cpuPricePerSecond)
            + (gpuCores * gpuPricePerSecond)
            + (memoryGB * memoryPricePerSecond)
            + (diskGB * diskPricePerSecond);
        
        // Require at least one month of revenue as stake
        uint256 monthlyRevenueStake = revenuePerSecond * 30 days;

        return baseStakeAmount + resourceStake + monthlyRevenueStake;
    }

    /**
     * @dev Register a new provider (1 provider = 1 machine) and mint NFT
     *      This call transfers the required stake based on specs.
     * @param operator Operator address
     * @param metadata Provider metadata
     * @param machineType Type of virtualization
     * @param region Location information
     * @param cpuCores Number of CPU cores
     * @param gpuCores Number of GPU cores
     * @param gpuMemory GPU memory in MB
     * @param memoryMB RAM in MB
     * @param diskGB Storage in GB
     * @param cpuPricePerSecond CPU price per second
     * @param gpuPricePerSecond GPU price per second
     * @param memoryPricePerSecond Memory price per second
     * @param diskPricePerSecond Disk price per second
     * @return The provider owner address
     */
    function registerProvider(
        address operator,
        string memory metadata,
        uint256 machineType, 
        uint256 region,
        uint256 cpuCores,
        uint256 gpuCores,
        uint256 gpuMemory,
        uint256 memoryMB,
        uint256 diskGB,
        uint256 cpuPricePerSecond,
        uint256 gpuPricePerSecond,
        uint256 memoryPricePerSecond,
        uint256 diskPricePerSecond
    ) external returns (address) {
        // Calculate and collect stake
        uint256 requiredStake = calculateRequiredStake(
            cpuCores,
            gpuCores,
            memoryMB,
            diskGB,
            cpuPricePerSecond,
            gpuPricePerSecond,
            memoryPricePerSecond,
            diskPricePerSecond
        );
        IERC20(stakingToken).safeTransferFrom(msg.sender, address(this), requiredStake);

        providers[msg.sender] = Provider({
            operator: operator,
            owner: msg.sender,
            registered: true,
            metadata: metadata,
            reputation: 100, // Default max reputation
            createdAt: block.timestamp,
            updatedAt: block.timestamp,
            totalStaked: requiredStake,
            pendingWithdrawals: 0, // 0 while active
            slashedAmount: 0,
            isSlashed: false,
            isActive: true,
            verified: false,
            machineType: machineType,
            region: region,
            cpuCores: cpuCores,
            gpuCores: gpuCores,
            gpuMemory: gpuMemory,
            memoryMB: memoryMB,
            diskGB: diskGB,
            cpuPricePerSecond: cpuPricePerSecond,
            gpuPricePerSecond: gpuPricePerSecond,
            memoryPricePerSecond: memoryPricePerSecond,
            diskPricePerSecond: diskPricePerSecond,
            stakeAmount: requiredStake,
            removedAt: 0,
            unlockTime: 0,
            withdrawalProcessed: false
        });

        emit ProviderRegistered(msg.sender, requiredStake);
        return msg.sender;
    }

    /**
     * @dev Update provider metadata only
     */
    function updateProviderInfo(
        address provider,
        string memory metadata
    ) external {
        require(providers[provider].registered, "Provider not registered");
        require(provider == msg.sender, "Only owner can update provider info");

        Provider storage p = providers[provider];
        p.metadata = metadata;
        p.updatedAt = block.timestamp;

        emit ProviderUpdated(provider);
    }

    /**
     * @dev Update provider specs (may require additional stake; disallow downgrades)
     */
    function updateProviderSpecs(
        address provider,
        uint256 machineType,
        uint256 region,
        uint256 cpuCores,
        uint256 gpuCores,
        uint256 gpuMemory,
        uint256 memoryMB,
        uint256 diskGB,
        string memory metadata,
        uint256 cpuPricePerSecond,
        uint256 gpuPricePerSecond,
        uint256 memoryPricePerSecond,
        uint256 diskPricePerSecond
    ) external {
        require(providers[provider].registered, "Provider not registered");
        require(!providers[provider].isSlashed, "Provider is slashed");
        Provider storage p = providers[provider];
        require(provider == msg.sender, "Only owner can update specs");
        require(p.isActive, "Provider not active");

        // Calculate new required stake
        uint256 newRequiredStake = calculateRequiredStake(
            cpuCores,
            gpuCores, 
            memoryMB,
            diskGB,
            cpuPricePerSecond,
            gpuPricePerSecond,
            memoryPricePerSecond,
            diskPricePerSecond
        );
        uint256 currentStake = p.stakeAmount;
        
        // Only allow updates that maintain or increase resources/stake
        require(newRequiredStake >= currentStake, "Cannot downgrade machine resources");
        
        uint256 additionalStake = newRequiredStake - currentStake;
        if (additionalStake > 0) {
            IERC20(stakingToken).safeTransferFrom(msg.sender, address(this), additionalStake);
            p.totalStaked += additionalStake;
        }
        
        // Update specs and pricing
        p.machineType = machineType;
        p.region = region;
        p.cpuCores = cpuCores;
        p.gpuCores = gpuCores;
        p.gpuMemory = gpuMemory;
        p.memoryMB = memoryMB;
        p.diskGB = diskGB;
        p.metadata = metadata;
        p.cpuPricePerSecond = cpuPricePerSecond;
        p.gpuPricePerSecond = gpuPricePerSecond;
        p.memoryPricePerSecond = memoryPricePerSecond;
        p.diskPricePerSecond = diskPricePerSecond;
        p.updatedAt = block.timestamp;
        p.stakeAmount = newRequiredStake;
        
        emit ProviderSpecsUpdated(provider, additionalStake);
    }

    /**
     * @dev Deactivate provider and set unlock time for stake withdrawal
     */
    function deactivateProvider(address provider) external {
        require(providers[provider].registered, "Provider not registered");
        require(provider == msg.sender, "Only owner can deactivate");
        Provider storage p = providers[provider];
        require(p.isActive, "Already deactivated");

        // Set unlock time with current lock period
        uint256 stakedAmount = p.stakeAmount;
        uint256 unlockTime = block.timestamp + lockPeriod;
        
        p.pendingWithdrawals += stakedAmount;
        p.totalStaked -= stakedAmount;
        p.isActive = false;
        
        // Mark as removed and set unlock time
        p.removedAt = block.timestamp;
        p.unlockTime = unlockTime;
        p.withdrawalProcessed = false;
        
        p.updatedAt = block.timestamp;

        emit ProviderDeactivated(provider, unlockTime);
    }

    /**
     * @dev Claim withdrawable stake after lock period
     */
    function claimWithdrawal(address provider) external {
        require(providers[provider].registered, "Provider not registered");
        require(!providers[provider].isSlashed, "Provider is slashed");
        Provider storage p = providers[provider];
        require(provider == msg.sender, "Only owner can claim");
        require(!p.isActive, "Still active");
        require(!p.withdrawalProcessed, "Already processed");
        require(block.timestamp >= p.unlockTime, "Still locked");
        
        uint256 amount = p.stakeAmount;
        p.withdrawalProcessed = true;
        p.pendingWithdrawals -= amount;

        IERC20(stakingToken).safeTransfer(msg.sender, amount);
        emit StakeWithdrawn(provider, amount);
    }

    /**
     * @dev Admin function to slash stake from a provider (penalize bad behavior)
     * @param providerId ID of the provider
     * @param amount Amount to slash
     * @param reason Reason for slashing
     */
    function slashStake(
        address providerId,
        uint256 amount,
        string memory reason
    ) external onlyOwner {
        require(providers[providerId].registered, "Provider not registered");
        Provider storage p = providers[providerId];
        require(p.stakeAmount >= amount, "Cannot slash more than staked");

        // Reduce stake and record slashing
        p.stakeAmount -= amount;
        p.totalStaked -= amount;
        p.slashedAmount += amount;
        p.isSlashed = true;
        p.isActive = false;
        totalSlashed += amount;

        emit StakeSlashed(providerId, amount, reason);
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
    function getProviderSlashedAmount(address providerId) external view returns (uint256) {
        return providers[providerId].slashedAmount;
    }
    
    /**
     * @dev Check if a provider is currently active
     */
    function isProviderActive(address providerId) external view returns (bool) {
        Provider storage p = providers[providerId];
        return p.registered && !p.isSlashed && p.isActive;
    }
    
    /**
     * @dev Check if address is provider owner or operator
     * @param provider Address of the provider owner
     * @param account Address to check
     * @return True if address is provider owner or operator
     */
    function isProviderOperatorOrOwner(address provider, address account) public view returns (bool) {
        require(providers[provider].registered, "Provider not registered");
        
        // Check owner
        bool isOwner = provider == account;
        
        // Check if the account is the designated operator
        bool isOperator = providers[provider].operator == account;
        
        return isOwner || isOperator;
    }
    
    /**
     * @dev Modifier to restrict function to provider owner or operator
     */
    modifier onlyProviderOperatorOrOwner(address providerId) {
        require(isProviderOperatorOrOwner(providerId, msg.sender), "Not provider owner or operator");
        _;
    }

    /**
     * @dev Update provider operator address
     * @param provider Provider owner address
     * @param newOperator New operator address
     */
    function setProviderOperator(address provider, address newOperator) external {
        require(provider == msg.sender, "Only owner can set operator");
        require(!providers[provider].isSlashed, "Provider is slashed");
        providers[provider].operator = newOperator;
        providers[provider].updatedAt = block.timestamp;
    }

    /**
     * @dev Validate if a provider meets minimum requirements (checking available resources)
     * @param machineType Type of the machine
     * @param providerId ID of the provider
     * @param minCpuCores Minimum CPU cores required
     * @param minMemoryMB Minimum memory required
     * @param minDiskGB Minimum disk space required
     * @param minGpuCores Minimum GPU cores required
     * @return True if machine meets requirements
     */
    function validateProviderRequirements(
        uint256 machineType,
        address providerId,
        uint256 minCpuCores,
        uint256 minMemoryMB,
        uint256 minDiskGB,
        uint256 minGpuCores
    ) external view returns (bool) {
        // Check if provider and machine exist
        if (!providers[providerId].registered || providers[providerId].isSlashed) {
            return false;
        }
        
        Provider memory p = providers[providerId];
        LockedResources memory locked = lockedResources[providerId];
        
        // Check available resources (total - locked)
        uint256 availableCpu = p.cpuCores >= locked.cpuCores ? p.cpuCores - locked.cpuCores : 0;
        uint256 availableGpu = p.gpuCores >= locked.gpuCores ? p.gpuCores - locked.gpuCores : 0;
        uint256 availableMemory = p.memoryMB >= locked.memoryMB ? p.memoryMB - locked.memoryMB : 0;
        uint256 availableDisk = p.diskGB >= locked.diskGB ? p.diskGB - locked.diskGB : 0;
        
        // Provider must be active and meet all requirements with available resources
        return p.isActive &&
               availableCpu >= minCpuCores &&
               availableMemory >= minMemoryMB &&
               availableDisk >= minDiskGB &&
               availableGpu >= minGpuCores &&
               p.machineType == machineType;
    }
    
    /**
     * @dev Get provider details
     * @param providerId Address of the provider
     * @return provider Provider struct with details
     */
    function getProvider(address providerId) external view returns (Provider memory provider ) {
        return providers[providerId];
    }

    /**
     * @dev Get provider owner address (equals providerId)
     * @param providerId Address of the provider
     * @return Address of the provider's owner
     */
    function getProviderOwner(address providerId) external pure returns (address) {
        return providerId;
    }

    /**
     * @dev Update price per resource (provider owner or operator only)
     */
    function setResourcePrice(
        address providerId,
        uint256 cpuPricePerSecond,
        uint256 gpuPricePerSecond,
        uint256 memoryPricePerSecond,
        uint256 diskPricePerSecond
    ) external onlyProviderOperatorOrOwner(providerId) {
        Provider storage provider = providers[providerId];
        provider.cpuPricePerSecond = cpuPricePerSecond;
        provider.gpuPricePerSecond = gpuPricePerSecond;
        provider.memoryPricePerSecond = memoryPricePerSecond;
        provider.diskPricePerSecond = diskPricePerSecond;
        provider.updatedAt = block.timestamp;
        emit ResourcePriceUpdated(
            providerId,
            cpuPricePerSecond,
            gpuPricePerSecond,
            memoryPricePerSecond,
            diskPricePerSecond
        );
    }

    /**
     * @dev Get price per resource
     */
    function getResourcePrice(address providerId) external view returns (
        uint256 cpuPricePerSecond,
        uint256 gpuPricePerSecond,
        uint256 memoryPricePerSecond,
        uint256 diskPricePerSecond
    ) {
        return (
            providers[providerId].cpuPricePerSecond,
            providers[providerId].gpuPricePerSecond,
            providers[providerId].memoryPricePerSecond,
            providers[providerId].diskPricePerSecond
        );
    }

    /**
     * @dev Set provider verification status (admin only)
     * @param providerId Provider ID
     * @param verified_ Verification status
     */
    function setProviderVerified(address providerId, bool verified_) external onlyOwner {
        require(providers[providerId].registered, "Provider not registered");
        providers[providerId].verified = verified_;
        emit ProviderVerified(providerId, verified_);
    }

    function isVerified(address providerId) external view returns (bool) {
        return providers[providerId].verified;
    }

    /**
     * @dev Update provider reputation (admin only or via reputation system)
     * @param providerId Provider ID
     * @param newReputation New reputation score
     */
    function setProviderReputation(address providerId, uint256 newReputation) external onlyOwner {
        require(providers[providerId].registered, "Provider not registered");
        require(newReputation <= 100, "Reputation cannot exceed 100");
        providers[providerId].reputation = newReputation;
        emit ProviderReputationUpdated(providerId, newReputation);
    }

    function getProviderReputation(address providerId) external view returns (uint256) {
        return providers[providerId].reputation;
    }

    /**
     * @dev Authorize a locker (e.g., marketplace contract) to lock/unlock resources for all providers
     * @param locker Address of the locker contract
     * @param authorized Whether to authorize or revoke authorization
     */
    function setAuthorizedLocker(address locker, bool authorized) external onlyOwner {
        require(locker != address(0), "Invalid locker address");
        authorizedLockers[locker] = authorized;
    }

    /**
     * @dev Lock resources for a provider (only authorized lockers can call)
     * @param provider Provider address
     * @param cpuCores CPU cores to lock
     * @param gpuCores GPU cores to lock
     * @param memoryMB Memory in MB to lock
     * @param diskGB Disk in GB to lock
     */
    function lockResources(
        address provider,
        uint256 cpuCores,
        uint256 gpuCores,
        uint256 memoryMB,
        uint256 diskGB
    ) external {
        require(authorizedLockers[msg.sender], "Not authorized to lock resources");
        require(providers[provider].registered, "Provider not registered");
        require(providers[provider].isActive, "Provider not active");
        
        Provider memory p = providers[provider];
        LockedResources storage locked = lockedResources[provider];
        
        // Check that provider has enough available resources
        uint256 availableCpu = p.cpuCores >= locked.cpuCores ? p.cpuCores - locked.cpuCores : 0;
        uint256 availableGpu = p.gpuCores >= locked.gpuCores ? p.gpuCores - locked.gpuCores : 0;
        uint256 availableMemory = p.memoryMB >= locked.memoryMB ? p.memoryMB - locked.memoryMB : 0;
        uint256 availableDisk = p.diskGB >= locked.diskGB ? p.diskGB - locked.diskGB : 0;
        
        require(availableCpu >= cpuCores, "Insufficient available CPU");
        require(availableGpu >= gpuCores, "Insufficient available GPU");
        require(availableMemory >= memoryMB, "Insufficient available memory");
        require(availableDisk >= diskGB, "Insufficient available disk");
        
        // Lock the resources
        locked.cpuCores += cpuCores;
        locked.gpuCores += gpuCores;
        locked.memoryMB += memoryMB;
        locked.diskGB += diskGB;
        
        emit ResourcesLocked(provider, cpuCores, gpuCores, memoryMB, diskGB);
    }

    /**
     * @dev Unlock resources for a provider (only authorized lockers can call)
     * @param provider Provider address
     * @param cpuCores CPU cores to unlock
     * @param gpuCores GPU cores to unlock
     * @param memoryMB Memory in MB to unlock
     * @param diskGB Disk in GB to unlock
     */
    function unlockResources(
        address provider,
        uint256 cpuCores,
        uint256 gpuCores,
        uint256 memoryMB,
        uint256 diskGB
    ) external {
        require(authorizedLockers[msg.sender], "Not authorized to unlock resources");
        
        LockedResources storage locked = lockedResources[provider];
        
        // Ensure we don't unlock more than what's locked
        require(locked.cpuCores >= cpuCores, "Cannot unlock more CPU than locked");
        require(locked.gpuCores >= gpuCores, "Cannot unlock more GPU than locked");
        require(locked.memoryMB >= memoryMB, "Cannot unlock more memory than locked");
        require(locked.diskGB >= diskGB, "Cannot unlock more disk than locked");
        
        // Unlock the resources
        locked.cpuCores -= cpuCores;
        locked.gpuCores -= gpuCores;
        locked.memoryMB -= memoryMB;
        locked.diskGB -= diskGB;
        
        emit ResourcesUnlocked(provider, cpuCores, gpuCores, memoryMB, diskGB);
    }

    /**
     * @dev Get locked resources for a provider
     * @param provider Provider address
     * @return LockedResources struct with locked amounts
     */
    function getLockedResources(address provider) external view returns (LockedResources memory) {
        return lockedResources[provider];
    }

}




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
        uint256 cpuCores; // mCPU (milliCPU): 1000 mCPU = 1 CPU
        uint256 gpuCores;
        uint256 memoryMB;
        uint256 diskGB;
        // Pricing (per second)
        uint256 cpuPricePerSecond; // Price per 1 CPU (not mCPU)
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
    uint256 public totalSlashed;         // Total amount slashed
    uint256 public stakeRevenueRatioBps; // Ratio of revenue to stake (basis points)
    uint256 public stakeRevenueDays;     // Number of days of revenue to stake against
    uint256 private constant BPS_DENOMINATOR = 10_000;

    // Resource locking for orders
    struct LockedResources {
        uint256 cpuCores; // mCPU (milliCPU): 1000 mCPU = 1 CPU
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
    event StakeConfigurationUpdated(
        uint256 revenueRatioBps,
        uint256 revenueDays
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
    event ResourcesLocked(address indexed provider, uint256 cpuCores, uint256 gpuCores, uint256 memoryMB, uint256 diskGB); // cpuCores is mCPU
    event ResourcesUnlocked(address indexed provider, uint256 cpuCores, uint256 gpuCores, uint256 memoryMB, uint256 diskGB); // cpuCores is mCPU

    /**
     * @dev Initialize the contract
     */
    function initialize(address owner, address _stakingToken) external initializer {
        __Ownable_init(owner);
        
        stakingToken = _stakingToken;
        
        // Set default stake parameters
        stakeRevenueRatioBps = BPS_DENOMINATOR; // 100% of revenue
        stakeRevenueDays = 30; // 30 days of revenue
        
        lockPeriod = 3 weeks; // Default 3 weeks lock period
    }

    /**
     * @dev Update stake configuration (owner only)
     * @param newRevenueRatioBps Ratio (in basis points) of revenue to require as stake
     * @param newRevenueDays Number of days of revenue to include in stake calculation
     */
    function setStakeConfiguration(uint256 newRevenueRatioBps, uint256 newRevenueDays) external onlyOwner {
        require(newRevenueRatioBps > 0, "Stake ratio must be positive");
        require(newRevenueDays > 0, "Stake revenue days must be positive");
        stakeRevenueRatioBps = newRevenueRatioBps;
        stakeRevenueDays = newRevenueDays;
        emit StakeConfigurationUpdated(newRevenueRatioBps, newRevenueDays);
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
     * @dev Calculate required stake based on resources and pricing configuration.
     * @param cpuCores Number of mCPU (milliCPU): 1000 mCPU = 1 CPU
     * @param gpuCores Number of GPU cores
     * @param memoryMB Memory in MB
     * @param diskGB Storage in GB
     * @param cpuPricePerSecond Price per 1 CPU per second (not per mCPU)
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
        // Estimated revenue per second from pricing
        // Calculate CPU revenue: (mCPU * price per CPU) / 1000 to avoid precision loss
        // Example: 500 mCPU * 10 tokens/CPU = 5000 / 1000 = 5 tokens (correct for half CPU)
        // Calculate Memory revenue: (MB * price per GB) / 1024 to avoid precision loss
        // Example: 500 MB * 20 tokens/GB = 10000 / 1024 = 9.76... tokens (correct for 500MB)
        uint256 revenuePerSecond = (cpuCores * cpuPricePerSecond) / 1000
            + (gpuCores * gpuPricePerSecond)
            + (memoryMB * memoryPricePerSecond) / 1024
            + (diskGB * diskPricePerSecond);
        
        uint256 secondsInPeriod = stakeRevenueDays * 1 days;
        uint256 revenueStake = revenuePerSecond * secondsInPeriod;

        return (revenueStake * stakeRevenueRatioBps) / BPS_DENOMINATOR;
    }

    /**
     * @dev Register a new provider (1 provider = 1 machine) and mint NFT
     *      This call transfers the required stake based on specs.
     * @param operator Operator address
     * @param metadata Provider metadata
     * @param machineType Type of virtualization
     * @param region Location information
     * @param cpuCores Number of mCPU (milliCPU): 1000 mCPU = 1 CPU
     * @param gpuCores Number of GPU cores
     * @param memoryMB RAM in MB
     * @param diskGB Storage in GB
     * @param cpuPricePerSecond Price per 1 CPU per second (not per mCPU)
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
     * @param provider Provider address
     * @param machineType Machine type (immutable)
     * @param region Region (immutable)
     * @param cpuCores Number of mCPU (milliCPU): 1000 mCPU = 1 CPU
     * @param gpuCores Number of GPU cores
     * @param memoryMB RAM in MB
     * @param diskGB Storage in GB
     */
    function updateProviderSpecs(
        address provider,
        uint256 machineType,
        uint256 region,
        uint256 cpuCores,
        uint256 gpuCores,
        uint256 memoryMB,
        uint256 diskGB
    ) external {
        require(providers[provider].registered, "Provider not registered");
        require(!providers[provider].isSlashed, "Provider is slashed");
        Provider storage p = providers[provider];
        require(provider == msg.sender, "Only owner can update specs");
        require(p.isActive, "Provider not active");
        require(machineType == p.machineType, "Machine type immutable");
        require(region == p.region, "Region immutable");
        require(cpuCores >= p.cpuCores, "Cannot decrease mCPU");
        require(gpuCores >= p.gpuCores, "Cannot decrease GPU cores");
        require(memoryMB >= p.memoryMB, "Cannot decrease memory");
        require(diskGB >= p.diskGB, "Cannot decrease disk size");

        // Calculate new required stake
        uint256 newRequiredStake = calculateRequiredStake(
            cpuCores,
            gpuCores, 
            memoryMB,
            diskGB,
            p.cpuPricePerSecond,
            p.gpuPricePerSecond,
            p.memoryPricePerSecond,
            p.diskPricePerSecond
        );
        uint256 currentStake = p.stakeAmount;
        
        uint256 additionalStake = 0;
        if (newRequiredStake > currentStake) {
            additionalStake = newRequiredStake - currentStake;
            IERC20(stakingToken).safeTransferFrom(msg.sender, address(this), additionalStake);
            p.totalStaked += additionalStake;
            p.stakeAmount = newRequiredStake;
        } else {
            additionalStake = 0;
        }
        
        // Update specs
        p.cpuCores = cpuCores;
        p.gpuCores = gpuCores;
        p.memoryMB = memoryMB;
        p.diskGB = diskGB;
        p.updatedAt = block.timestamp;
        
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
     * @param minCpuCores Minimum mCPU (milliCPU) required: 1000 mCPU = 1 CPU
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
     * @param providerId Provider address
     * @param cpuPricePerSecond Price per 1 CPU per second (not per mCPU)
     * @param gpuPricePerSecond GPU price per second
     * @param memoryPricePerSecond Memory price per second
     * @param diskPricePerSecond Disk price per second
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
     * @param providerId Provider address
     * @return cpuPricePerSecond Price per 1 CPU per second (not per mCPU)
     * @return gpuPricePerSecond GPU price per second
     * @return memoryPricePerSecond Memory price per second
     * @return diskPricePerSecond Disk price per second
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
     * @param cpuCores mCPU (milliCPU) to lock: 1000 mCPU = 1 CPU
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
        
        require(availableCpu >= cpuCores, "Insufficient available mCPU");
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
     * @param cpuCores mCPU (milliCPU) to unlock: 1000 mCPU = 1 CPU
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
        require(locked.cpuCores >= cpuCores, "Cannot unlock more mCPU than locked");
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




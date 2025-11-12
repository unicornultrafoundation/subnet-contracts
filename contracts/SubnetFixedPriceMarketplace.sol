// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./BaseMarketplace.sol";
import "./ISubnetProvider.sol";

/**
 * @title SubnetFixedPriceMarketplace
 * @dev Marketplace for fixed price orders (any provider can accept)
 */
contract SubnetFixedPriceMarketplace is BaseMarketplace {
    using SafeERC20 for IERC20;

    struct Order {
        uint256 machineType;
        address owner;
        OrderStatus status;
        uint256 createdAt;
        uint256 duration;
        uint256 fixedPrice;
        address paymentToken;
        uint256 cpuCores;
        uint256 gpuCores;
        uint256 memoryMB;
        uint256 diskGB;
        uint256 region;
        string specs;
    }

    struct ProviderAcceptance {
        address provider;
        uint256 startAt;
        uint256 expiredAt;
        uint256 lastPaidAt;
        bool isActive;
    }

    uint256 public orderCount;
    mapping(uint256 => Order) public orders;
    mapping(uint256 => ProviderAcceptance[]) public orderProviderAcceptances;
    mapping(uint256 => mapping(address => bool)) public orderBlacklistedProviders; // orderId => provider => isBlacklisted
    mapping(uint256 => mapping(address => bool)) public orderWhitelistedProviders; // orderId => provider => isWhitelisted
    mapping(uint256 => uint256) public orderWhitelistCount; // orderId => count of whitelisted providers

    event OrderCreated(uint256 indexed orderId, address owner, uint256 duration, uint256 fixedPrice);
    event FixedPriceOrderAccepted(uint256 indexed orderId, address indexed provider, uint256 acceptanceIndex);
    event FixedPricePaymentClaimed(uint256 indexed orderId, address indexed provider, uint256 acceptanceIndex, uint256 amount);
    event ProviderAcceptanceClosed(uint256 indexed orderId, address indexed provider, uint256 acceptanceIndex);
    event OrderCancelled(uint256 indexed orderId, address owner);
    event OrderBlacklistUpdated(uint256 indexed orderId, address[] providers);
    event OrderWhitelistUpdated(uint256 indexed orderId, address[] providers);

    function initialize(
        address owner,
        address _paymentToken,
        address _subnetProviderContract
    ) external initializer {
        __BaseMarketplace_init(owner, _paymentToken, _subnetProviderContract);
    }

    function createOrder(
        uint256 machineType,
        uint256 duration,
        uint256 fixedPricePerSecond,
        uint256 region,
        uint256 cpuCores,
        uint256 gpuCores,
        uint256 memoryMB,
        uint256 diskGB,
        string memory specs,
        address[] memory blacklistedProviders,
        address[] memory whitelistedProviders
    ) external returns (uint256) {
        require(paymentToken != address(0), "Payment token not set");
        require(duration > 0, "Duration must be positive");
        require(fixedPricePerSecond > 0, "Fixed price must be positive");

        orderCount++;
        uint256 orderId = orderCount;
        
        orders[orderId] = Order({
            machineType: machineType,
            owner: msg.sender,
            status: OrderStatus.Open,
            createdAt: block.timestamp,
            duration: duration,
            fixedPrice: fixedPricePerSecond,
            paymentToken: paymentToken,
            specs: specs,
            cpuCores: cpuCores,
            gpuCores: gpuCores,
            memoryMB: memoryMB,
            diskGB: diskGB,
            region: region
        });

        // Set blacklisted providers
        for (uint256 i = 0; i < blacklistedProviders.length; i++) {
            orderBlacklistedProviders[orderId][blacklistedProviders[i]] = true;
        }

        // Set whitelisted providers
        for (uint256 i = 0; i < whitelistedProviders.length; i++) {
            orderWhitelistedProviders[orderId][whitelistedProviders[i]] = true;
        }
        orderWhitelistCount[orderId] = whitelistedProviders.length;

        emit OrderCreated(orderId, msg.sender, duration, fixedPricePerSecond);
        if (blacklistedProviders.length > 0) {
            emit OrderBlacklistUpdated(orderId, blacklistedProviders);
        }
        if (whitelistedProviders.length > 0) {
            emit OrderWhitelistUpdated(orderId, whitelistedProviders);
        }
        return orderId;
    }

    function acceptOrderByProvider(uint256 orderId) external {
        Order storage order = orders[orderId];
        require(order.status == OrderStatus.Open, "Order not open");
        
        address provider = msg.sender;
        ISubnetProvider providerContract = ISubnetProvider(subnetProviderContract);
        
        // Check if provider already accepted this order
        ProviderAcceptance[] storage acceptances = orderProviderAcceptances[orderId];
        for (uint256 i = 0; i < acceptances.length; i++) {
            require(acceptances[i].provider != provider || !acceptances[i].isActive, "Provider already accepted this order");
        }
        
        require(providerContract.isProviderActive(provider), "Provider is not active");
        require(!orderBlacklistedProviders[orderId][provider], "Provider is blacklisted");
        
        // If order has whitelist, only whitelisted providers can accept
        if (orderWhitelistCount[orderId] > 0) {
            require(orderWhitelistedProviders[orderId][provider], "Provider is not whitelisted");
        }
        
        require(
            providerContract.validateProviderRequirements(
                order.machineType,
                provider,
                order.cpuCores,
                order.memoryMB,
                order.diskGB,
                order.gpuCores
            ),
            "Provider does not meet requirements"
        );

        // Lock resources (no upfront payment - provider will claim payment based on actual usage)
        providerContract.lockResources(
            provider,
            order.cpuCores,
            order.gpuCores,
            order.memoryMB,
            order.diskGB
        );

        uint256 acceptanceIndex = acceptances.length;
        acceptances.push(ProviderAcceptance({
            provider: provider,
            startAt: block.timestamp,
            expiredAt: block.timestamp + order.duration,
            lastPaidAt: block.timestamp,
            isActive: true
        }));

        emit FixedPriceOrderAccepted(orderId, provider, acceptanceIndex);
    }

    function claimPaymentForFixedPrice(uint256 orderId, uint256 acceptanceIndex) external {
        Order storage order = orders[orderId];
        
        ProviderAcceptance[] storage acceptances = orderProviderAcceptances[orderId];
        require(acceptanceIndex < acceptances.length, "Invalid acceptance index");
        ProviderAcceptance storage acceptance = acceptances[acceptanceIndex];
        require(acceptance.provider == msg.sender, "Not your acceptance");
        require(acceptance.isActive, "Acceptance not active");
        require(!orderBlacklistedProviders[orderId][acceptance.provider], "Provider is blacklisted");
        
        ISubnetProvider providerContract = ISubnetProvider(subnetProviderContract);
        require(providerContract.isProviderActive(acceptance.provider), "Provider is not active");
        
        uint256 endTime = block.timestamp < acceptance.expiredAt ? block.timestamp : acceptance.expiredAt;
        require(endTime > acceptance.lastPaidAt, "No new time to pay for");
        
        uint256 actualTimeUsed = endTime - acceptance.lastPaidAt;
        uint256 totalPayment = actualTimeUsed * order.fixedPrice;
        require(totalPayment > 0, "Nothing to claim");
        
        uint256 platformFee = calculateFee(totalPayment);
        uint256 providerPayment = totalPayment - platformFee;
        totalAccumulatedFees += platformFee;
        
        acceptance.lastPaidAt = endTime;
        
        require(order.paymentToken != address(0), "Payment token not set");
        IERC20(order.paymentToken).safeTransferFrom(order.owner, acceptance.provider, providerPayment);
        
        emit FixedPricePaymentClaimed(orderId, acceptance.provider, acceptanceIndex, providerPayment);
    }

    function closeProviderAcceptance(uint256 orderId, uint256 acceptanceIndex) external {
        Order storage order = orders[orderId];
        
        ProviderAcceptance[] storage acceptances = orderProviderAcceptances[orderId];
        require(acceptanceIndex < acceptances.length, "Invalid acceptance index");
        ProviderAcceptance storage acceptance = acceptances[acceptanceIndex];
        
        require(
            acceptance.provider == msg.sender || order.owner == msg.sender,
            "Not authorized to close"
        );
        require(acceptance.isActive, "Acceptance already closed");
        
        uint256 endTime = block.timestamp < acceptance.expiredAt ? block.timestamp : acceptance.expiredAt;
        uint256 timeUsed = endTime > acceptance.lastPaidAt ? endTime - acceptance.lastPaidAt : 0;
        uint256 finalPayment = timeUsed * order.fixedPrice;
        
        ISubnetProvider providerContract = ISubnetProvider(subnetProviderContract);
        providerContract.unlockResources(
            acceptance.provider,
            order.cpuCores,
            order.gpuCores,
            order.memoryMB,
            order.diskGB
        );
        
        acceptance.isActive = false;
        acceptance.lastPaidAt = endTime;
        
        // Only pay if provider is not blacklisted and is active
        if (finalPayment > 0 && 
            providerContract.isProviderActive(acceptance.provider) &&
            !orderBlacklistedProviders[orderId][acceptance.provider]) {
            uint256 platformFee = calculateFee(finalPayment);
            uint256 providerPayment = finalPayment - platformFee;
            totalAccumulatedFees += platformFee;
            
            IERC20(order.paymentToken).safeTransferFrom(order.owner, acceptance.provider, providerPayment);
        }
        
        emit ProviderAcceptanceClosed(orderId, acceptance.provider, acceptanceIndex);
    }

    function cancelOrder(uint256 orderId) external {
        Order storage order = orders[orderId];
        require(order.owner == msg.sender, "Only order owner can cancel");
        require(order.status == OrderStatus.Open, "Order not open");
        order.status = OrderStatus.Closed;
        emit OrderCancelled(orderId, msg.sender);
    }

    function getProviderAcceptances(uint256 orderId) external view returns (ProviderAcceptance[] memory) {
        return orderProviderAcceptances[orderId];
    }

    /**
     * @dev Update blacklisted providers for an order (only order owner can update)
     * @param orderId Order ID
     * @param providers Array of provider addresses to blacklist/unblacklist
     * @param blacklisted Array of boolean values indicating if provider should be blacklisted
     */
    function updateOrderBlacklist(
        uint256 orderId,
        address[] memory providers,
        bool[] memory blacklisted
    ) external {
        Order storage order = orders[orderId];
        require(order.owner == msg.sender, "Only order owner can update blacklist");
        require(order.status == OrderStatus.Open, "Order not open");
        require(providers.length == blacklisted.length, "Arrays length mismatch");
        
        // Update blacklist status for each provider
        for (uint256 i = 0; i < providers.length; i++) {
            orderBlacklistedProviders[orderId][providers[i]] = blacklisted[i];
        }
        
        emit OrderBlacklistUpdated(orderId, providers);
    }

    /**
     * @dev Update whitelisted providers for an order (only order owner can update)
     * @param orderId Order ID
     * @param providers Array of provider addresses to whitelist/unwhitelist
     * @param whitelisted Array of boolean values indicating if provider should be whitelisted
     */
    function updateOrderWhitelist(
        uint256 orderId,
        address[] memory providers,
        bool[] memory whitelisted
    ) external {
        Order storage order = orders[orderId];
        require(order.owner == msg.sender, "Only order owner can update whitelist");
        require(order.status == OrderStatus.Open, "Order not open");
        require(providers.length == whitelisted.length, "Arrays length mismatch");
        
        uint256 currentCount = orderWhitelistCount[orderId];
        
        // Update whitelist status for each provider
        for (uint256 i = 0; i < providers.length; i++) {
            bool wasWhitelisted = orderWhitelistedProviders[orderId][providers[i]];
            orderWhitelistedProviders[orderId][providers[i]] = whitelisted[i];
            
            // Update count
            if (whitelisted[i] && !wasWhitelisted) {
                currentCount++;
            } else if (!whitelisted[i] && wasWhitelisted) {
                currentCount--;
            }
        }
        
        orderWhitelistCount[orderId] = currentCount;
        emit OrderWhitelistUpdated(orderId, providers);
    }

    /**
     * @dev Check if a provider is blacklisted for an order
     * @param orderId Order ID
     * @param provider Provider address to check
     * @return True if provider is blacklisted
     */
    function isProviderBlacklisted(uint256 orderId, address provider) external view returns (bool) {
        return orderBlacklistedProviders[orderId][provider];
    }

    /**
     * @dev Check if a provider is whitelisted for an order
     * @param orderId Order ID
     * @param provider Provider address to check
     * @return True if provider is whitelisted
     */
    function isProviderWhitelisted(uint256 orderId, address provider) external view returns (bool) {
        return orderWhitelistedProviders[orderId][provider];
    }
}


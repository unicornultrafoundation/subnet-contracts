// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./BaseMarketplace.sol";
import "./ISubnetProvider.sol";

/**
 * @title SubnetDirectProviderMarketplace
 * @dev Marketplace for direct provider orders (specific provider, auto-accept if price matches)
 */
contract SubnetDirectProviderMarketplace is BaseMarketplace {
    using SafeERC20 for IERC20;

    struct Order {
        uint256 machineType;
        address owner;
        OrderStatus status;
        uint256 createdAt;
        uint256 duration;
        uint256 maxPrice;
        uint256 acceptedBidPricePerSecond;
        address paymentToken;
        uint256 cpuCores;
        uint256 gpuCores;
        uint256 gpuMemory;
        uint256 memoryMB;
        uint256 diskGB;
        uint256 region;
        string specs;
        address targetProvider;
        address acceptedProvider;
        uint256 startAt;
        uint256 expiredAt;
        uint256 lastPaidAt;
    }

    uint256 public orderCount;
    mapping(uint256 => Order) public orders;

    event OrderCreated(uint256 indexed orderId, address owner, address provider, uint256 pricePerSecond);
    event OrderExtended(uint256 indexed orderId, uint256 additionalDuration, uint256 newExpiry);
    event OrderClosed(uint256 indexed orderId, uint256 refundAmount, string reason);

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
        uint256 maxPrice,
        uint256 region,
        uint256 cpuCores,
        uint256 gpuCores,
        uint256 gpuMemory,
        uint256 memoryMB,
        uint256 diskGB,
        string memory specs,
        address targetProvider
    ) external returns (uint256) {
        require(paymentToken != address(0), "Payment token not set");
        require(duration > 0, "Duration must be positive");
        require(maxPrice > 0, "Max price must be positive");
        require(targetProvider != address(0), "Invalid provider address");

        ISubnetProvider providerContract = ISubnetProvider(subnetProviderContract);
        require(providerContract.isProviderActive(targetProvider), "Provider is not active");
        require(
            providerContract.validateProviderRequirements(
                machineType,
                targetProvider,
                cpuCores,
                memoryMB,
                diskGB,
                gpuCores
            ),
            "Provider does not meet requirements"
        );

        // Get provider's resource prices
        (uint256 cpuPrice, uint256 gpuPrice, uint256 memPrice, uint256 diskPrice) = 
            providerContract.getResourcePrice(targetProvider);
        
        // Calculate total price per second
        uint256 memoryGB = memoryMB / 1024;
        uint256 totalPricePerSecond = (cpuCores * cpuPrice) + 
                                     (gpuCores * gpuPrice) + 
                                     (memoryGB * memPrice) + 
                                     (diskGB * diskPrice);
        
        require(totalPricePerSecond <= maxPrice, "Provider price exceeds maximum");

        orderCount++;
        uint256 orderId = orderCount;
        
        // Payment logic: renter pays upfront
        uint256 totalCost = totalPricePerSecond * duration;
        IERC20(paymentToken).safeTransferFrom(msg.sender, address(this), totalCost);

        // Lock resources
        providerContract.lockResources(targetProvider, cpuCores, gpuCores, memoryMB, diskGB);

        orders[orderId] = Order({
            machineType: machineType,
            owner: msg.sender,
            status: OrderStatus.Matched,
            createdAt: block.timestamp,
            duration: duration,
            maxPrice: maxPrice,
            acceptedBidPricePerSecond: totalPricePerSecond,
            paymentToken: paymentToken,
            specs: specs,
            targetProvider: targetProvider,
            acceptedProvider: targetProvider,
            startAt: block.timestamp,
            expiredAt: block.timestamp + duration,
            lastPaidAt: block.timestamp,
            cpuCores: cpuCores,
            gpuCores: gpuCores,
            gpuMemory: gpuMemory,
            memoryMB: memoryMB,
            diskGB: diskGB,
            region: region
        });

        emit OrderCreated(orderId, msg.sender, targetProvider, totalPricePerSecond);
        return orderId;
    }

    function extend(uint256 orderId, uint256 amount) external {
        Order storage order = orders[orderId];
        require(order.owner == msg.sender, "Only order owner can extend");
        require(order.status == OrderStatus.Matched, "Order not matched");
        require(block.timestamp <= order.expiredAt + orderGracePeriod, "Order expired beyond grace period");

        uint256 pricePerSecond = order.acceptedBidPricePerSecond;
        require(pricePerSecond > 0, "Price not set");
        uint256 duration = amount / pricePerSecond;
        IERC20(order.paymentToken).safeTransferFrom(msg.sender, address(this), amount);
        order.expiredAt += duration;
        emit OrderExtended(orderId, duration, order.expiredAt);
    }

    function closeOrder(uint256 orderId, string memory reason) external {
        Order storage order = orders[orderId];
        require(order.status == OrderStatus.Matched, "Order not active");
        
        bool isExpiredBeyondGracePeriod = block.timestamp >= order.expiredAt + orderGracePeriod;
        if (!isExpiredBeyondGracePeriod) {
            require(order.owner == msg.sender, "Only order owner can close orders within grace period");
        }
        
        uint256 endTime = block.timestamp < order.expiredAt ? block.timestamp : order.expiredAt;
        uint256 timeUsed = endTime > order.lastPaidAt ? endTime - order.lastPaidAt : 0;
        uint256 remainingTime = order.expiredAt > block.timestamp ? order.expiredAt - block.timestamp : 0;
            
        uint256 paymentForProvider = timeUsed * order.acceptedBidPricePerSecond;
        uint256 refundAmount = remainingTime * order.acceptedBidPricePerSecond;

        order.status = OrderStatus.Closed;
        order.lastPaidAt = endTime;

        ISubnetProvider providerContract = ISubnetProvider(subnetProviderContract);
        bool isProviderActive = providerContract.isProviderActive(order.acceptedProvider);
        
        providerContract.unlockResources(
            order.acceptedProvider,
            order.cpuCores,
            order.gpuCores,
            order.memoryMB,
            order.diskGB
        );
        
        if (paymentForProvider > 0 && isProviderActive) {
            uint256 platformFee = calculateFee(paymentForProvider);
            paymentForProvider -= platformFee;
            totalAccumulatedFees += platformFee;
            IERC20(order.paymentToken).safeTransfer(order.acceptedProvider, paymentForProvider);
        } else {
           refundAmount += paymentForProvider;
        }
        
        if (refundAmount > 0) {
            IERC20(order.paymentToken).safeTransfer(order.owner, refundAmount);
        }
        emit OrderClosed(orderId, refundAmount, reason);
    }

    function claimPayment(uint256 orderId) external {
        Order storage order = orders[orderId];
        require(order.status == OrderStatus.Matched, "Order not matched");
        ISubnetProvider providerContract = ISubnetProvider(subnetProviderContract);
        require(providerContract.isProviderActive(order.acceptedProvider), "Provider is not active");
        
        uint256 endTime = block.timestamp < order.expiredAt ? block.timestamp : order.expiredAt;
        require(endTime > order.lastPaidAt, "No new time to pay for");
        
        uint256 actualTimeUsed = endTime - order.lastPaidAt;
        uint256 totalPayment = actualTimeUsed * order.acceptedBidPricePerSecond;
        require(totalPayment > 0, "Nothing to claim");
        
        uint256 platformFee = calculateFee(totalPayment);
        uint256 providerPayment = totalPayment - platformFee;
        totalAccumulatedFees += platformFee;
        
        order.lastPaidAt = endTime;
        IERC20(order.paymentToken).safeTransfer(order.acceptedProvider, providerPayment);
    }
}


// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "./BaseMarketplace.sol";
import "./ISubnetProvider.sol";

/**
 * @title SubnetBidMarketplace
 * @dev Marketplace for bidding-based orders
 */
contract SubnetBidMarketplace is BaseMarketplace {
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    enum BidStatus { Pending, Accepted, Cancelled }

    struct Order {
        uint256 machineType;
        address owner;
        OrderStatus status;
        uint256 createdAt;
        uint256 duration;
        uint256 minBidPrice;
        uint256 maxBidPrice;
        uint256 acceptedBidPricePerSecond;
        address paymentToken;
        uint256 cpuCores;
        uint256 gpuCores;
        uint256 memoryMB;
        uint256 diskGB;
        uint256 region;
        string specs;
        address acceptedProvider;
        uint256 startAt;
        uint256 expiredAt;
        uint256 lastPaidAt;
    }

    struct Bid {
        address provider;
        uint256 pricePerSecond;
        BidStatus status;
        uint256 createdAt;
    }

    uint256 public bidTimeLimit;
    uint256 public orderCount;
    mapping(uint256 => Order) public orders;
    mapping(uint256 => Bid[]) public orderBids;
    mapping(bytes32 => bool) public usedSignatures; // Track used signatures to prevent replay attacks
    mapping(bytes32 => bool) public cancelledSignatures; // Track cancelled signature hashes

    event OrderCreated(uint256 indexed orderId, address owner, uint256 duration);
    event BidSubmitted(uint256 indexed orderId, address indexed provider, uint256 bidIndex);
    event BidAccepted(uint256 indexed orderId, address indexed provider, uint256 bidIndex, uint256 pricePerSecond);
    event OrderCancelled(uint256 indexed orderId, address owner);
    event BidCancelled(uint256 indexed orderId, address indexed provider, uint256 bidIndex);
    event OrderExtended(uint256 indexed orderId, uint256 additionalDuration, uint256 newExpiry);
    event OrderClosed(uint256 indexed orderId, uint256 refundAmount, string reason);
    event BidTimeLimitUpdated(uint256 oldLimit, uint256 newLimit);
    event BidAcceptedWithSignature(uint256 indexed orderId, address indexed provider, uint256 bidIndex, uint256 pricePerSecond, bytes32 signatureHash);
    event BidCancelledWithSignature(bytes32 indexed signatureHash, address indexed provider);

    function initialize(
        address owner,
        address _paymentToken,
        address _subnetProviderContract
    ) external initializer {
        __BaseMarketplace_init(owner, _paymentToken, _subnetProviderContract);
        bidTimeLimit = 5 minutes;
    }

    function setBidTimeLimit(uint256 newBidTimeLimit) external onlyOwner {
        require(newBidTimeLimit > 0, "Time limit must be positive");
        uint256 oldLimit = bidTimeLimit;
        bidTimeLimit = newBidTimeLimit;
        emit BidTimeLimitUpdated(oldLimit, newBidTimeLimit);
    }

    function createOrder(
        uint256 machineType,
        uint256 duration,
        uint256 minBidPrice,
        uint256 maxBidPrice,
        uint256 region,
        uint256 cpuCores,
        uint256 gpuCores,
        uint256 memoryMB,
        uint256 diskGB,
        string memory specs
    ) external returns (uint256) {
        require(paymentToken != address(0), "Payment token not set");
        require(duration > 0, "Duration must be positive");
        require(minBidPrice <= maxBidPrice, "minBidPrice must be <= maxBidPrice");

        orderCount++;
        orders[orderCount] = Order({
            machineType: machineType,
            owner: msg.sender,
            status: OrderStatus.Open,
            createdAt: block.timestamp,
            duration: duration,
            minBidPrice: minBidPrice,
            maxBidPrice: maxBidPrice,
            acceptedBidPricePerSecond: 0,
            paymentToken: paymentToken,
            specs: specs,
            acceptedProvider: address(0),
            startAt: 0,
            expiredAt: 0,
            lastPaidAt: 0,
            cpuCores: cpuCores,
            gpuCores: gpuCores,
            memoryMB: memoryMB,
            diskGB: diskGB,
            region: region
        });
        emit OrderCreated(orderCount, msg.sender, duration);
        return orderCount;
    }

    function submitBid(
        uint256 orderId,
        uint256 pricePerSecond,
        address provider
    ) external {
        Order storage order = orders[orderId];
        require(order.status == OrderStatus.Open, "Order not open");
        require(block.timestamp <= order.createdAt + bidTimeLimit, "Bidding time expired");
        require(pricePerSecond >= order.minBidPrice, "Bid price below minimum");
        require(pricePerSecond <= order.maxBidPrice, "Bid price above maximum");
        
        ISubnetProvider providerContract = ISubnetProvider(subnetProviderContract);
        require(providerContract.isProviderOperatorOrOwner(provider, msg.sender),
            "Not authorized to bid for this provider"
        );
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

        orderBids[orderId].push(Bid({
            provider: provider,
            pricePerSecond: pricePerSecond,
            status: BidStatus.Pending,
            createdAt: block.timestamp
        }));
        uint256 bidIndex = orderBids[orderId].length - 1;
        emit BidSubmitted(orderId, provider, bidIndex);
    }

    function acceptBid(uint256 orderId, uint256 bidIndex) external {
        Order storage order = orders[orderId];
        require(order.owner == msg.sender, "Only order owner can accept");
        require(order.status == OrderStatus.Open, "Order not open");
        require(bidIndex < orderBids[orderId].length, "Invalid bid index");
        Bid storage bid = orderBids[orderId][bidIndex];
        require(bid.status == BidStatus.Pending, "Bid not pending");

        ISubnetProvider providerContract = ISubnetProvider(subnetProviderContract);
        require(providerContract.isProviderActive(bid.provider), "Provider is not active");

        require(order.paymentToken != address(0), "Payment token not set");
        uint256 totalCost = bid.pricePerSecond * order.duration;
        IERC20(order.paymentToken).safeTransferFrom(msg.sender, address(this), totalCost);

        providerContract.lockResources(
            bid.provider,
            order.cpuCores,
            order.gpuCores,
            order.memoryMB,
            order.diskGB
        );

        bid.status = BidStatus.Accepted;
        order.status = OrderStatus.Matched;
        order.acceptedBidPricePerSecond = bid.pricePerSecond;
        order.acceptedProvider = bid.provider;
        order.startAt = block.timestamp;
        order.expiredAt = block.timestamp + order.duration;
        order.lastPaidAt = block.timestamp;

        emit BidAccepted(orderId, bid.provider, bidIndex, bid.pricePerSecond);
    }

    /**
     * @dev Accept a bid using an off-chain signature from the provider
     * @param orderId The order ID
     * @param provider The provider address that signed the bid
     * @param pricePerSecond The price per second for the bid
     * @param signature The signature from the provider
     */
    function acceptBidWithSignature(
        uint256 orderId,
        address provider,
        uint256 pricePerSecond,
        bytes memory signature
    ) external {
        Order storage order = orders[orderId];
        require(order.owner == msg.sender, "Only order owner can accept");
        require(order.status == OrderStatus.Open, "Order not open");
        require(block.timestamp <= order.createdAt + bidTimeLimit, "Bidding time expired");
        require(pricePerSecond >= order.minBidPrice, "Bid price below minimum");
        require(pricePerSecond <= order.maxBidPrice, "Bid price above maximum");

        ISubnetProvider providerContract = ISubnetProvider(subnetProviderContract);
        require(providerContract.isProviderActive(provider), "Provider is not active");
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

        // Create the message hash
        bytes32 dataHash = keccak256(
            abi.encodePacked(
                orderId,
                provider,
                pricePerSecond,
                address(this),
                block.chainid
            )
        );

        // Add Ethereum message prefix and verify signature
        bytes32 ethSignedMessageHash = dataHash.toEthSignedMessageHash();
        address signer = ethSignedMessageHash.recover(signature);
        require(signer == provider, "Invalid signature");

        // Check for replay attack and cancellation
        bytes32 signatureHash = keccak256(signature);
        require(!usedSignatures[signatureHash], "Signature already used");
        require(!cancelledSignatures[signatureHash], "Signature has been cancelled");
        usedSignatures[signatureHash] = true;

        // Process payment
        require(order.paymentToken != address(0), "Payment token not set");
        uint256 totalCost = pricePerSecond * order.duration;
        IERC20(order.paymentToken).safeTransferFrom(msg.sender, address(this), totalCost);

        // Lock resources
        providerContract.lockResources(
            provider,
            order.cpuCores,
            order.gpuCores,
            order.memoryMB,
            order.diskGB
        );

        // Create bid entry
        orderBids[orderId].push(Bid({
            provider: provider,
            pricePerSecond: pricePerSecond,
            status: BidStatus.Accepted,
            createdAt: block.timestamp
        }));
        uint256 bidIndex = orderBids[orderId].length - 1;

        // Update order
        order.status = OrderStatus.Matched;
        order.acceptedBidPricePerSecond = pricePerSecond;
        order.acceptedProvider = provider;
        order.startAt = block.timestamp;
        order.expiredAt = block.timestamp + order.duration;
        order.lastPaidAt = block.timestamp;

        emit BidAcceptedWithSignature(orderId, provider, bidIndex, pricePerSecond, signatureHash);
    }

    function isBiddingOpen(uint256 orderId) public view returns (bool) {
        Order storage order = orders[orderId];
        return (order.status == OrderStatus.Open && 
                block.timestamp <= order.createdAt + bidTimeLimit);
    }

    function getRemainingBidTime(uint256 orderId) public view returns (uint256) {
        Order storage order = orders[orderId];
        uint256 endTime = order.createdAt + bidTimeLimit;
        if (block.timestamp >= endTime) {
            return 0;
        }
        return endTime - block.timestamp;
    }

    function getBids(uint256 orderId) external view returns (Bid[] memory) {
        return orderBids[orderId];
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

    function cancelOrder(uint256 orderId) external {
        Order storage order = orders[orderId];
        require(order.owner == msg.sender, "Only order owner can cancel");
        require(order.status == OrderStatus.Open, "Order not open");
        order.status = OrderStatus.Closed;
        emit OrderCancelled(orderId, msg.sender);
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

    function cancelBid(uint256 orderId, uint256 bidIndex) external {
        Order storage order = orders[orderId];
        require(order.status == OrderStatus.Open, "Order not open");
        require(bidIndex < orderBids[orderId].length, "Invalid bid index");
        Bid storage bid = orderBids[orderId][bidIndex];
        require(bid.provider == msg.sender, "Only bid provider can cancel");
        require(bid.status == BidStatus.Pending, "Cannot cancel non-pending bid");

        bid.status = BidStatus.Cancelled;
        emit BidCancelled(orderId, bid.provider, bidIndex);
    }

    /**
     * @dev Cancel a bid signature to prevent it from being accepted
     * @param signature The signature to cancel
     * @param orderId The order ID that the signature is for
     * @param pricePerSecond The price per second in the signature
     */
    function cancelBidWithSignature(
        bytes memory signature,
        uint256 orderId,
        uint256 pricePerSecond
    ) external {
        address provider = msg.sender;
        
        // Verify the signature belongs to the caller
        bytes32 dataHash = keccak256(
            abi.encodePacked(
                orderId,
                provider,
                pricePerSecond,
                address(this),
                block.chainid
            )
        );
        
        bytes32 ethSignedMessageHash = dataHash.toEthSignedMessageHash();
        address signer = ethSignedMessageHash.recover(signature);
        require(signer == provider, "Invalid signature or not the signer");
        
        // Mark signature hash as cancelled
        bytes32 signatureHash = keccak256(signature);
        require(!usedSignatures[signatureHash], "Signature already used");
        require(!cancelledSignatures[signatureHash], "Signature already cancelled");
        
        cancelledSignatures[signatureHash] = true;
        emit BidCancelledWithSignature(signatureHash, provider);
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

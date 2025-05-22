// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract SubnetClusterMarket is Initializable, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    struct Cluster {
        address owner;
        uint256 orderId;
        uint256[] nodeIps;
        bool active;
        uint256 expiration; // timestamp when the cluster expires
        address renter;     // address of the renter
        uint256 renterIp;   // renter's IP

        // Resource info
        uint256 ip;
        uint256 gpu;
        uint256 cpu;
        uint256 memoryBytes;
        uint256 disk;
        uint256 network;
    }

    // Events
    event OrderCreated(uint256 indexed orderId, address indexed user, uint256 price, uint256 discountPrice);
    event ResourcePriceUpdated(uint256 gpu, uint256 cpu, uint256 memoryBytes, uint256 disk, uint256 network);
    event DiscountAdded(uint256 minDuration, uint256 percent);
    event OrderExtended(uint256 indexed orderId, uint256 additionalDuration, uint256 additionalPrice, uint256 discountPrice);
    event OrderScaled(
        uint256 indexed orderId,
        uint256 gpu,
        uint256 cpu,
        uint256 memoryBytes,
        uint256 disk,
        uint256 network,
        uint256 totalPrice,
        uint256 discountPrice
    );
    event OrderConfirmed(uint256 indexed orderId);
    event ClusterNodesAdded(uint256 indexed clusterId, uint256[] newNodeIps);
    event ClusterNodeRemoved(uint256 indexed clusterId, uint256 indexed nodeIp);
    event OrderCanceled(uint256 indexed orderId, address indexed user);
    event ClusterInactive(uint256 indexed clusterId); // <--- add this line

    enum OrderStatus { Pending, Confirmed, Canceled, Refunded }
    enum OrderType { New, Extend, Scale }

    struct Order {
        address user;
        OrderStatus status;
        uint256 ip;
        // Resource requirements
        uint256 gpu;
        uint256 cpu;
        uint256 memoryBytes;
        uint256 disk;
        uint256 network;
        uint256 rentalDuration; // in seconds or desired time unit
        address paymentToken;   // Token used for payment
        uint256 clusterId;      // 0 for initial order, >0 for scale/extend orders
        uint256 paidAmount;     // Amount actually paid after discount
        uint256 discountAmount; // Discount amount applied
        OrderType orderType;    // Type of the order: New, Extend, Scale
    }

    uint256 public nextOrderId;
    mapping(uint256 => Order) public orders;

    // Resource pricing (per unit)
    struct ResourcePrice {
        uint256 gpu;
        uint256 cpu;
        uint256 memoryBytes;
        uint256 disk;
        uint256 network;
    }

    ResourcePrice public resourcePrice;

    uint256 public nextClusterId;
    mapping(uint256 => Cluster) public clusters;

    // Mapping from nodeIp to list of clusterIds containing that nodeIp
    mapping(uint256 => uint256[]) public nodeIpToClusterIds;

    address public operator;

    event OperatorUpdated(address indexed newOperator);

    function initialize(
        address _initialOwner,
        address _operator,
        uint256 _gpuPrice,
        uint256 _cpuPrice,
        uint256 _memoryBytesPrice,
        uint256 _diskPrice,
        uint256 _networkPrice
    ) public initializer {
        __Ownable_init(_initialOwner);
        operator = _operator;
        nextOrderId = 1;
        nextClusterId = 1;
        resourcePrice = ResourcePrice({
            gpu: _gpuPrice,
            cpu: _cpuPrice,
            memoryBytes: _memoryBytesPrice,
            disk: _diskPrice,
            network: _networkPrice
        });
    }

    /// @notice Set the operator address.
    /// @param _operator The address to set as operator.
    function setOperator(address _operator) external onlyOwner {
        operator = _operator;
        emit OperatorUpdated(_operator);
    }

    /// @notice Allows the owner to set the price for each resource type.
    /// @param gpu Price per GPU unit.
    /// @param cpu Price per CPU unit.
    /// @param memoryBytes Price per memory byte.
    /// @param disk Price per disk unit.
    /// @param network Price per network unit.
    function setResourcePrice(
        uint256 gpu,
        uint256 cpu,
        uint256 memoryBytes,
        uint256 disk,
        uint256 network
    ) external onlyOwner {
        resourcePrice = ResourcePrice({
            gpu: gpu,
            cpu: cpu,
            memoryBytes: memoryBytes,
            disk: disk,
            network: network
        });
        emit ResourcePriceUpdated(gpu, cpu, memoryBytes, disk, network);
    }

    address public paymentToken;

    function setPaymentToken(address token) external onlyOwner {
        paymentToken = token;
    }

    // Discount thresholds and rates
    struct Discount {
        uint256 minDuration; // minimum rental duration to get discount
        uint256 percent;     // discount percent (e.g. 10 for 10%)
    }

    Discount[] public discounts;

    /// @notice Allows the owner to add a discount rule.
    /// @param minDuration Minimum rental duration to qualify for discount.
    /// @param percent Discount percent (e.g. 10 for 10%).
    function addDiscount(uint256 minDuration, uint256 percent) external onlyOwner {
        require(percent < 100, "Discount too high");
        discounts.push(Discount({minDuration: minDuration, percent: percent}));
        emit DiscountAdded(minDuration, percent);
    }

    /// @notice Allows the owner to update a discount rule by index.
    /// @param index The index of the discount to update.
    /// @param minDuration Minimum rental duration to qualify for discount.
    /// @param percent Discount percent (e.g. 10 for 10%).
    function updateDiscount(uint256 index, uint256 minDuration, uint256 percent) external onlyOwner {
        require(index < discounts.length, "Invalid discount index");
        require(percent < 100, "Discount too high");
        discounts[index].minDuration = minDuration;
        discounts[index].percent = percent;
        emit DiscountAdded(minDuration, percent);
    }

    /// @dev Internal function to get discount percent for a given duration.
    function getDiscountPercent(uint256 rentalDuration) public view returns (uint256) {
        uint256 best = 0;
        for (uint i = 0; i < discounts.length; i++) {
            if (rentalDuration >= discounts[i].minDuration && discounts[i].percent > best) {
                best = discounts[i].percent;
            }
        }
        return best;
    }

    function _createOrder(
        address user,
        uint256 ip,
        uint256 gpu,
        uint256 cpu,
        uint256 memoryBytes,
        uint256 disk,
        uint256 network,
        uint256 rentalDuration,
        uint256 clusterId,
        OrderType orderType
    ) internal {
        // Calculate total price
        uint256 totalPrice =
            gpu * resourcePrice.gpu +
            cpu * resourcePrice.cpu +
            memoryBytes * resourcePrice.memoryBytes +
            disk * resourcePrice.disk +
            network * resourcePrice.network;

        totalPrice = totalPrice * rentalDuration;

        // Apply discount if eligible
        uint256 discountPercent = getDiscountPercent(rentalDuration);
        uint256 discountAmount = 0;
        if (discountPercent > 0) {
            discountAmount = (totalPrice * discountPercent) / 100;
            totalPrice = totalPrice - discountAmount;
        }

        require(totalPrice > 0, "Total price must be greater than 0");
        require(paymentToken != address(0), "Payment token not set");
        IERC20(paymentToken).safeTransferFrom(user, address(this), totalPrice);

        orders[nextOrderId] = Order({
            user: user,
            status: OrderStatus.Pending,
            ip: ip,
            gpu: gpu,
            cpu: cpu,
            memoryBytes: memoryBytes,
            disk: disk,
            network: network,
            rentalDuration: rentalDuration,
            paymentToken: paymentToken,
            clusterId: clusterId,
            paidAmount: totalPrice,
            discountAmount: discountAmount,
            orderType: orderType
        });

        emit OrderCreated(nextOrderId, user, totalPrice + discountAmount, totalPrice);
        nextOrderId++;
    }

    function createOrder(
        uint256 ip,
        uint256 gpu,
        uint256 cpu,
        uint256 memoryBytes,
        uint256 disk,
        uint256 network,
        uint256 rentalDuration
    ) external {
        _createOrder(
            msg.sender,
            ip,
            gpu,
            cpu,
            memoryBytes,
            disk,
            network,
            rentalDuration,
            0,
            OrderType.New
        );
    }

    /// @notice Allows the user to extend the rental duration of their cluster.
    /// @param clusterId The ID of the cluster to extend.
    /// @param additionalDuration The additional rental duration to add.
    function extend(
        uint256 clusterId,
        uint256 additionalDuration
    ) external {
        Cluster storage cluster = clusters[clusterId];
        require(cluster.renter == msg.sender, "Not cluster owner");
        require(cluster.expiration > block.timestamp, "Cluster expired");

        _createOrder(
            msg.sender,
            0,
            cluster.cpu,
            cluster.gpu,
            cluster.memoryBytes,
            cluster.disk,
            cluster.network,
            additionalDuration,
            clusterId,
            OrderType.Extend
        );


        Order storage order = orders[nextOrderId - 1];
        order.status = OrderStatus.Confirmed; // Mark order as confirmed
        cluster.expiration += order.rentalDuration;
        emit OrderConfirmed(nextOrderId - 1);
    }

    /// @notice Allows the user to scale up/down the resources of their cluster.
    /// @param clusterId The ID of the cluster to scale.
    /// @param gpu New GPU amount.
    /// @param cpu New CPU amount.
    /// @param memoryBytes New memory amount.
    /// @param disk New disk amount.
    /// @param network New network amount.
    function scale(
        uint256 clusterId,
        uint256 gpu,
        uint256 cpu,
        uint256 memoryBytes,
        uint256 disk,
        uint256 network
    ) external {
        // clusterId is used to find the main order
        Cluster storage cluster = clusters[clusterId];
        require(cluster.renter == msg.sender, "Not cluster owner");
        require(cluster.expiration > block.timestamp, "Cluster expired");

        _createOrder(
            msg.sender,
            0,
            gpu,
            cpu,
            memoryBytes,
            disk,
            network,
            cluster.expiration -  block.timestamp,
            clusterId,
            OrderType.Scale
        );
    }

    /// @notice Owner can withdraw funds from contract to a renter.
    /// @param token The ERC20 token address.
    /// @param to The address to withdraw to.
    /// @param amount The amount to withdraw.
    function withdrawFund(address token, address to, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(to, amount);
    }

    /// @notice Owner or operator confirms an order and creates a Ray cluster with the given node IPs.
    /// @param orderId The ID of the order to confirm.
    /// @param nodeIps The list of node IPs for the Ray cluster.
    /// @param renterIp The renter's IP.
    function confirmOrder(uint256 orderId, uint256[] memory nodeIps, uint256 renterIp) external {
        require(msg.sender == owner() || msg.sender == operator, "Not authorized");
        Order storage order = orders[orderId];
        require(order.status == OrderStatus.Pending, "Order is not pending");
        require(order.orderType == OrderType.New, "Order type must be New");
        require(nodeIps.length > 0, "Node IPs required");

        // Mark order as confirmed
        order.status = OrderStatus.Confirmed;

        // Calculate expiration time
        uint256 expiration = block.timestamp + order.rentalDuration;

        // Create cluster with unique clusterId
        uint256 clusterId = nextClusterId++;
        clusters[clusterId] = Cluster({
            owner: msg.sender,
            orderId: orderId,
            nodeIps: nodeIps,
            active: true,
            expiration: expiration,
            renter: order.user,
            renterIp: renterIp,
            ip: order.ip,
            gpu: order.gpu,
            cpu: order.cpu,
            memoryBytes: order.memoryBytes,
            disk: order.disk,
            network: order.network
        });

        nodeIpToClusterIds[order.ip].push(clusterId);

        // Index nodeIps to clusterId
        for (uint i = 0; i < nodeIps.length; i++) {
            nodeIpToClusterIds[nodeIps[i]].push(clusterId);
        }

        order.clusterId = clusterId;

        emit OrderConfirmed(clusterId);
    }

    /// @notice Allows the owner or operator to confirm a scale order and update cluster resources.
    /// @param orderId The ID of the scale order to confirm.
    function confirmScaleOrder(uint256 orderId) external {
        require(msg.sender == owner() || msg.sender == operator, "Not authorized");
        Order storage order = orders[orderId];
        require(order.status == OrderStatus.Pending, "Order is not pending");
        require(order.orderType == OrderType.Scale, "Order type must be Scale");
        require(order.clusterId != 0, "Invalid clusterId");

        // Mark order as confirmed
        order.status = OrderStatus.Confirmed;

        // Update cluster resources
        Cluster storage cluster = clusters[order.clusterId];
        cluster.gpu += order.gpu;
        cluster.cpu += order.cpu;
        cluster.memoryBytes += order.memoryBytes;
        cluster.disk += order.disk;
        cluster.network += order.network;

        emit OrderConfirmed(orderId);
    }

    /// @notice Allows the owner to add more node IPs to an existing cluster (e.g., after scaling an order).
    /// @param clusterId The ID of the cluster to add nodes to.
    /// @param newNodeIps The array of new node IPs to add.
    function addNodesToCluster(uint256 clusterId, uint256[] memory newNodeIps) external onlyOwner {
        require(clusters[clusterId].active, "Cluster is not active");
        require(newNodeIps.length > 0, "No node IPs provided");
        for (uint i = 0; i < newNodeIps.length; i++) {
            clusters[clusterId].nodeIps.push(newNodeIps[i]);
            nodeIpToClusterIds[newNodeIps[i]].push(clusterId);
        }
        emit ClusterNodesAdded(clusterId, newNodeIps);
    }

    // Private helper to remove a node from a cluster's nodeIps array
    function _removeNodeFromCluster(uint256 clusterId, uint256 nodeIp) private {
        uint256[] storage nodeIps = clusters[clusterId].nodeIps;
        for (uint i = 0; i < nodeIps.length; i++) {
            if (nodeIps[i] == nodeIp) {
                nodeIps[i] = nodeIps[nodeIps.length - 1];
                nodeIps.pop();
                emit ClusterNodeRemoved(clusterId, nodeIp);
                break;
            }
        }
        // Remove clusterId from nodeIpToClusterIds[nodeIp]
        uint256[] storage clusterIds = nodeIpToClusterIds[nodeIp];
        for (uint i = 0; i < clusterIds.length; i++) {
            if (clusterIds[i] == clusterId) {
                clusterIds[i] = clusterIds[clusterIds.length - 1];
                clusterIds.pop();
                break;
            }
        }
    }

    /// @notice Allows the owner to remove a node IP from a cluster.
    /// @param clusterId The ID of the cluster.
    /// @param nodeIp The node IP to remove.
    function removeNodeFromCluster(uint256 clusterId, uint256 nodeIp) external onlyOwner {
        require(clusters[clusterId].active, "Cluster is not active");
        _removeNodeFromCluster(clusterId, nodeIp);
    }

    /// @notice Allows the owner to remove multiple node IPs from a cluster.
    /// @param clusterId The ID of the cluster.
    /// @param nodeIps The array of node IPs to remove.
    function removeNodesFromCluster(uint256 clusterId, uint256[] memory nodeIps) external onlyOwner {
        require(clusters[clusterId].active, "Cluster is not active");
        for (uint k = 0; k < nodeIps.length; k++) {
            _removeNodeFromCluster(clusterId, nodeIps[k]);
        }
    }

    /// @notice Allows the user to cancel their order if it is still pending.
    /// @param orderId The ID of the order to cancel.
    function cancelOrder(uint256 orderId) external {
        Order storage order = orders[orderId];
        require(order.status == OrderStatus.Pending, "Order is not pending");
        require(order.user == msg.sender, "Not order owner");
        order.status = OrderStatus.Canceled;
        emit OrderCanceled(orderId, msg.sender);

        // Refund payment to user
        uint256 refundAmount = order.paidAmount;
        require(refundAmount > 0, "Refund amount must be greater than 0");
        IERC20 token = IERC20(order.paymentToken);
        token.safeTransfer(order.user, refundAmount);
    }

    /// @notice Checks if two node IPs belong to any same cluster.
    /// @param nodeIp1 The first node IP.
    /// @param nodeIp2 The second node IP.
    /// @return sameCluster True if both nodeIp1 and nodeIp2 are in any same cluster, false otherwise.
    function areNodesInAnySameCluster(uint256 nodeIp1, uint256 nodeIp2) public view returns (bool sameCluster) {
        uint256[] memory clusters1 = nodeIpToClusterIds[nodeIp1];
        uint256[] memory clusters2 = nodeIpToClusterIds[nodeIp2];
        for (uint i = 0; i < clusters1.length; i++) {
            for (uint j = 0; j < clusters2.length; j++) {
                if (clusters1[i] == clusters2[j]) {
                    // Check if the cluster is not expired
                    if (clusters[clusters1[i]].expiration > block.timestamp) {
                        return true;
                    }
                }
            }
        }
        return false;
    }

    /// @notice Returns the list of clusterIds that contain the given nodeIp.
    /// @param nodeIp The node IP to search for.
    /// @return clusterIds The list of cluster IDs containing the node IP.
    function getClustersOfNode(uint256 nodeIp) public view returns (uint256[] memory clusterIds) {
        return nodeIpToClusterIds[nodeIp];
    }

    /// @notice Allows the owner or operator to update the main IP of a cluster.
    /// @param clusterId The ID of the cluster.
    /// @param newIp The new main IP to set.
    function updateClusterIp(uint256 clusterId, uint256 newIp) external {
        Cluster storage cluster = clusters[clusterId];
        require(cluster.owner == msg.sender, "Not cluster owner");
        require(cluster.expiration > block.timestamp, "Cluster expired");
        uint256 oldIp = cluster.ip;
        if (oldIp != 0) {
            // Remove clusterId from oldIp index
            uint256[] storage clusterIds = nodeIpToClusterIds[oldIp];
            for (uint i = 0; i < clusterIds.length; i++) {
                if (clusterIds[i] == clusterId) {
                    clusterIds[i] = clusterIds[clusterIds.length - 1];
                    clusterIds.pop();
                    break;
                }
            }
        }
        cluster.ip = newIp;
        if (newIp != 0) {
            nodeIpToClusterIds[newIp].push(clusterId);
        }
    }

    /// @notice Mark expired clusters as inactive.
    /// @dev Anyone can call this to mark clusters as inactive if they are expired.
    /// @param clusterIds The array of cluster IDs to check and inactivate if expired.
    function inactiveExpiredClusters(uint256[] calldata clusterIds) external {
        for (uint i = 0; i < clusterIds.length; i++) {
            uint256 clusterId = clusterIds[i];
            Cluster storage cluster = clusters[clusterId];
            if (cluster.active && cluster.expiration <= block.timestamp) {
                cluster.active = false;
                // Remove clusterId from nodeIpToClusterIds for all nodeIps
                for (uint j = 0; j < cluster.nodeIps.length; j++) {
                    _removeNodeFromCluster(clusterId, cluster.nodeIps[j]);
                }
                // Remove clusterId from nodeIpToClusterIds for main ip if not already handled
                if (cluster.ip != 0) {
                    _removeNodeFromCluster(clusterId, cluster.ip);
                }
                emit ClusterInactive(clusterId); // <--- emit event here
            }
        }
    }

    /// @notice Allows the owner or operator to recreate an expired cluster with new nodes and expiration.
    /// @param clusterId The ID of the cluster to recreate.
    /// @param nodeIps The new list of node IPs for the cluster.
    function recreateCluster(
        uint256 clusterId,
        uint256[] calldata nodeIps
    ) external {
        require(msg.sender == owner() || msg.sender == operator, "Not authorized");
        Cluster storage cluster = clusters[clusterId];
        require(cluster.expiration <= block.timestamp, "Cluster not expired");
        require(nodeIps.length > 0, "Node IPs required");

        // Remove clusterId from all old nodeIpToClusterIds
        for (uint i = 0; i < cluster.nodeIps.length; i++) {
            _removeNodeFromCluster(clusterId, cluster.nodeIps[i]);
        }

        for (uint i = 0; i < nodeIps.length; i++) {
            cluster.nodeIps.push(nodeIps[i]);
            nodeIpToClusterIds[nodeIps[i]].push(clusterId);
        }

        emit ClusterNodesAdded(clusterId, nodeIps);
    }

    /// @notice Returns the cluster info for a given clusterId.
    /// @param clusterId The ID of the cluster.
    /// @return cluster The Cluster struct.
    function getCluster(uint256 clusterId) external view returns (Cluster memory) {
        return clusters[clusterId];
    }
}

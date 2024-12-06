// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ISubnetRegistry.sol";

contract SubnetRental {
    ISubnetRegistry public registry; // Instance of SubnetRegistry

    struct ResourcePrice {
        uint256 cpuPrice; // Rental price per second for CPU
        uint256 memoryPrice; // Rental price per second for memory
        uint256 storagePrice; // Rental price per second for storage
        uint256 gpuPrice; // Rental price per second for GPU
    }

    struct Rental {
        uint256 subnetId; // ID of the rented subnet
        address renter; // Address of the renter
        uint256 startTime; // Start time of the rental
        uint256 endTime; // End time of the rental
        uint256 totalCost; // Total rental cost
        uint256 cpu; // Number of CPUs rented
        uint256 memoryAmount; // Amount of memory rented (in MB)
        uint256 storageCapacity; // Amount of storage rented (in GB)
        uint256 gpu; // Number of GPUs rented
        bool active; // Rental status
    }

    mapping(uint256 => ResourcePrice) public subnetPrices; // Resource prices for each subnet
    mapping(uint256 => Rental) public rentals; // Records of rental transactions
    uint256 public rentalCounter; // Counter for rental transactions

    event PriceSet(
        uint256 indexed subnetId,
        uint256 cpuPrice,
        uint256 memoryPrice,
        uint256 storagePrice,
        uint256 gpuPrice
    );
    event ResourceRented(
        uint256 indexed rentalId,
        uint256 indexed subnetId,
        address indexed renter,
        uint256 totalCost
    );
    event RentalCompleted(uint256 indexed rentalId, uint256 indexed subnetId);
    event ResourceRented(
        uint256 indexed rentalId, // ID of the rental transaction
        uint256 indexed subnetId, // ID of the rented subnet
        address indexed renter, // Address of the renter
        uint256 totalCost, // Total cost of the rental or extension
        uint256 startTime, // Start time of the rental or extension
        uint256 endTime // End time of the rental or extension
    );

    /**
     * @dev Constructor to link to SubnetRegistry
     * @param _registry Address of the SubnetRegistry contract
     */
    constructor(address _registry) {
        require(_registry != address(0), "Invalid registry address");
        registry = ISubnetRegistry(_registry);
    }

    /**
     * @dev Allows subnet owners to declare resource rental prices.
     * @param subnetId ID of the subnet
     * @param cpuPrice Rental price per second for CPU
     * @param memoryPrice Rental price per second for memory
     * @param storagePrice Rental price per second for storage
     * @param gpuPrice Rental price per second for GPU
     */
    function setPrice(
        uint256 subnetId,
        uint256 cpuPrice,
        uint256 memoryPrice,
        uint256 storagePrice,
        uint256 gpuPrice
    ) external {
        // Retrieve subnet information from SubnetRegistry
        ISubnetRegistry.Subnet memory subnet = registry.getSubnet(subnetId);
        require(
            subnet.owner == msg.sender,
            "Caller is not the owner of the subnet"
        );
        require(subnet.active, "Subnet is not active");
        require(
            cpuPrice > 0 && memoryPrice > 0 && storagePrice > 0,
            "Prices must be greater than zero"
        );

        subnetPrices[subnetId] = ResourcePrice({
            cpuPrice: cpuPrice,
            memoryPrice: memoryPrice,
            storagePrice: storagePrice,
            gpuPrice: gpuPrice
        });

        emit PriceSet(subnetId, cpuPrice, memoryPrice, storagePrice, gpuPrice);
    }

    /**
     * @dev Allows users to rent specific resources from a subnet.
     * @param subnetId ID of the subnet to rent
     * @param cpu Number of CPUs requested (set to 0 if not renting CPU)
     * @param memoryAmount Amount of memory (in MB) requested (set to 0 if not renting memory)
     * @param storageCapacity Amount of storage (in GB) requested (set to 0 if not renting storage)
     * @param gpu Number of GPUs requested (set to 0 if not renting GPUs)
     * @param duration Rental duration (in seconds)
     */
    function rentResource(
        uint256 subnetId,
        uint256 cpu,
        uint256 memoryAmount,
        uint256 storageCapacity,
        uint256 gpu,
        uint256 duration
    ) external payable {
        // Retrieve subnet information from SubnetRegistry
        ISubnetRegistry.Subnet memory subnet = registry.getSubnet(subnetId);

        // Check if the subnet is active
        require(subnet.active, "Subnet is not active");

        require(
            subnetPrices[subnetId].cpuPrice > 0 ||
                subnetPrices[subnetId].memoryPrice > 0 ||
                subnetPrices[subnetId].storagePrice > 0 ||
                subnetPrices[subnetId].gpuPrice > 0,
            "Subnet is not available for rent"
        );

        require(
            cpu > 0 || memoryAmount > 0 || storageCapacity > 0 || gpu > 0,
            "At least one resource must be rented"
        );
        require(duration > 0, "Duration must be greater than zero");

        ResourcePrice memory prices = subnetPrices[subnetId];

        uint256 totalCost = 0;

        if (cpu > 0) {
            require(prices.cpuPrice > 0, "CPU resource not available");
            totalCost += prices.cpuPrice * cpu * duration;
        }

        if (memoryAmount > 0) {
            require(prices.memoryPrice > 0, "Memory resource not available");
            totalCost += prices.memoryPrice * memoryAmount * duration;
        }

        if (storageCapacity > 0) {
            require(prices.storagePrice > 0, "Storage resource not available");
            totalCost += prices.storagePrice * storageCapacity * duration;
        }

        if (gpu > 0) {
            require(prices.gpuPrice > 0, "GPU resource not available");
            totalCost += prices.gpuPrice * gpu * duration;
        }

        require(msg.value >= totalCost, "Insufficient payment");

        rentalCounter++;
        rentals[rentalCounter] = Rental({
            subnetId: subnetId,
            renter: msg.sender,
            startTime: block.timestamp,
            endTime: block.timestamp + duration,
            totalCost: totalCost,
            cpu: cpu,
            memoryAmount: memoryAmount,
            storageCapacity: storageCapacity,
            gpu: gpu,
            active: true
        });

        // Refund excess payment if any
        if (msg.value > totalCost) {
            uint256 refundAmount = msg.value - totalCost;
            (bool success, ) = msg.sender.call{value: refundAmount}("");
            require(success, "Refund failed");
        }

        emit ResourceRented(rentalCounter, subnetId, msg.sender, totalCost);
    }

    /**
     * @dev Allows users to extend the rental period for an existing transaction.
     * @param rentalId ID of the rental transaction to extend
     * @param additionalDuration Additional rental duration (in seconds)
     */
    function extendRental(
        uint256 rentalId,
        uint256 additionalDuration
    ) external payable {
        Rental storage rental = rentals[rentalId];

        // Check if the rental is valid and active
        require(rental.active, "Rental is not active");
        require(rental.renter == msg.sender, "Caller is not the renter");
        require(
            additionalDuration > 0,
            "Additional duration must be greater than zero"
        );

        // Retrieve subnet information
        ISubnetRegistry.Subnet memory subnet = registry.getSubnet(
            rental.subnetId
        );
        require(subnet.active, "Subnet is not active");

        // Retrieve pricing
        ResourcePrice memory prices = subnetPrices[rental.subnetId];

        // Calculate the additional cost
        uint256 additionalCost = (prices.cpuPrice *
            rental.cpu +
            prices.memoryPrice *
            rental.memoryAmount +
            prices.storagePrice *
            rental.storageCapacity +
            prices.gpuPrice *
            rental.gpu) * additionalDuration;

        // Check payment
        require(
            msg.value >= additionalCost,
            "Insufficient payment for extension"
        );

        // Update the rental end time and total cost
        rental.endTime += additionalDuration;
        rental.totalCost += additionalCost;

        // Refund excess payment if any
        if (msg.value > additionalCost) {
            uint256 refundAmount = msg.value - additionalCost;
            (bool success, ) = msg.sender.call{value: refundAmount}("");
            require(success, "Refund failed");
        }

        emit ResourceRented(
            rentalId,
            rental.subnetId,
            msg.sender,
            additionalCost
        );
    }

    /**
     * @dev Completes a rental transaction.
     * @param rentalId ID of the rental transaction
     */
    function completeRental(uint256 rentalId) external {
        Rental storage rental = rentals[rentalId];
        require(rental.active, "Rental is not active");
        require(
            block.timestamp >= rental.endTime,
            "Rental period not yet ended"
        );

        ISubnetRegistry.Subnet memory subnet = registry.getSubnet(
            rental.subnetId
        );

        rental.active = false;

        // Transfer payment to the subnet owner
        (bool success, ) = subnet.owner.call{value: rental.totalCost}("");
        require(success, "Payment to subnet owner failed");

        emit RentalCompleted(rentalId, rental.subnetId);
    }

    /**
     * @dev Allows renters to cancel an active rental and get a refund for the unused time.
     * @param rentalId ID of the rental transaction to cancel
     */
    function cancelRental(uint256 rentalId) external {
        Rental storage rental = rentals[rentalId];

        // Ensure the rental is active
        require(rental.active, "Rental is not active");

        // Ensure the caller is the renter
        require(rental.renter == msg.sender, "Caller is not the renter");

        // Calculate the elapsed time and the remaining time
        uint256 elapsedTime = block.timestamp > rental.startTime
            ? block.timestamp - rental.startTime
            : 0;
        uint256 totalDuration = rental.endTime - rental.startTime;

        // Ensure the total duration is valid
        require(totalDuration > 0, "Invalid rental duration");

        // Calculate the unused time
        uint256 unusedTime = totalDuration > elapsedTime
            ? totalDuration - elapsedTime
            : 0;

        // Calculate the refund amount
        uint256 refundAmount = (rental.totalCost * unusedTime) / totalDuration;

        // Mark the rental as inactive
        rental.active = false;

        // Refund the unused amount
        if (refundAmount > 0) {
            (bool success, ) = msg.sender.call{value: refundAmount}("");
            require(success, "Refund failed");
        }

        emit RentalCompleted(rentalId, rental.subnetId);
    }

    /**
     * @dev Fetches the rental price of a subnet.
     * @param subnetId ID of the subnet
     * @return ResourcePrice Rental price information
     */
    function getPrice(
        uint256 subnetId
    ) external view returns (ResourcePrice memory) {
        return subnetPrices[subnetId];
    }

    /**
     * @dev Fetches information about a rental transaction.
     * @param rentalId ID of the rental transaction
     * @return Rental Rental information
     */
    function getRental(uint256 rentalId) external view returns (Rental memory) {
        return rentals[rentalId];
    }
}

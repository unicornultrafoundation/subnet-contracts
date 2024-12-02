// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ISubnetRegistry.sol";

contract SubnetRental {
    ISubnetRegistry public registry; // Instance of SubnetRegistry

    struct ResourcePrice {
        uint256 cpuPrice; // Rental price per second for CPU
        uint256 memoryPrice; // Rental price per second for memory
        uint256 storagePrice; // Rental price per second for storage
    }

    struct Rental {
        uint256 subnetId; // ID of the rented subnet
        address renter; // Address of the renter
        uint256 startTime; // Start time of the rental
        uint256 endTime; // End time of the rental
        uint256 totalCost; // Total rental cost
        bool active; // Rental status
    }

    mapping(uint256 => ResourcePrice) public subnetPrices; // Resource prices for each subnet
    mapping(uint256 => Rental) public rentals; // Records of rental transactions
    uint256 public rentalCounter; // Counter for rental transactions

    event PriceSet(
        uint256 indexed subnetId,
        uint256 cpuPrice,
        uint256 memoryPrice,
        uint256 storagePrice
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
     */
    function setPrice(
        uint256 subnetId,
        uint256 cpuPrice,
        uint256 memoryPrice,
        uint256 storagePrice
    ) external {
        // Retrieve subnet information from SubnetRegistry
        ISubnetRegistry.Subnet memory subnet = registry.subnets(subnetId);
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
            storagePrice: storagePrice
        });

        emit PriceSet(subnetId, cpuPrice, memoryPrice, storagePrice);
    }

    /**
     * @dev Allows users to rent resources from a subnet.
     * @param subnetId ID of the subnet to rent
     * @param cpu Number of CPUs requested
     * @param memoryAmount Amount of memory (in MB) requested
     * @param storageCapacity Amount of storage (in GB) requested
     * @param duration Rental duration (in seconds)
     */
    function rentResource(
        uint256 subnetId,
        uint256 cpu,
        uint256 memoryAmount,
        uint256 storageCapacity,
        uint256 duration
    ) external payable {
        // Retrieve subnet information from SubnetRegistry
        ISubnetRegistry.Subnet memory subnet = registry.subnets(subnetId);

        // Check if the subnet is active
        require(subnet.active, "Subnet is not active");

        require(
            subnetPrices[subnetId].cpuPrice > 0,
            "Subnet is not available for rent"
        );
        require(
            cpu > 0 && memoryAmount > 0 && storageCapacity > 0,
            "Resource amounts must be greater than zero"
        );
        require(duration > 0, "Duration must be greater than zero");

        ResourcePrice memory prices = subnetPrices[subnetId];

        uint256 totalCost = (prices.cpuPrice *
            cpu +
            prices.memoryPrice *
            memoryAmount +
            prices.storagePrice *
            memoryAmount) * duration;
        require(msg.value >= totalCost, "Insufficient payment");

        rentalCounter++;
        rentals[rentalCounter] = Rental({
            subnetId: subnetId,
            renter: msg.sender,
            startTime: block.timestamp,
            endTime: block.timestamp + duration,
            totalCost: totalCost,
            active: true
        });

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
        ISubnetRegistry.Subnet memory subnet = registry.subnets(
            rental.subnetId
        );
        require(subnet.active, "Subnet is not active");

        // Calculate the additional cost
        ResourcePrice memory prices = subnetPrices[rental.subnetId];
        uint256 additionalCost = (prices.cpuPrice +
            prices.memoryPrice +
            prices.storagePrice) * additionalDuration;

        // Check payment
        require(
            msg.value >= additionalCost,
            "Insufficient payment for extension"
        );

        // Update the rental end time and total cost
        rental.endTime += additionalDuration;
        rental.totalCost += additionalCost;

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

        ISubnetRegistry.Subnet memory subnet = registry.subnets(
            rental.subnetId
        );

        rental.active = false;

        // Transfer payment to the subnet owner
        (bool success, ) = subnet.owner.call{value: rental.totalCost}("");
        require(success, "Payment to subnet owner failed");

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

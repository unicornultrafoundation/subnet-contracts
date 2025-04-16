// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract SubnetResourceRent {
    struct Resource {
        uint256 id;
        address provider;
        uint256 cpuPricePerSecond;
        uint256 memoryPricePerSecond;
        uint256 gpuPricePerSecond;
        uint256 storagePricePerSecond;
        uint256 cpu;
        uint256 availableCpu;
        uint256 memoryBytes;
        uint256 availableMemoryBytes;
        uint256 gpu;
        uint256 availableGpu;
        uint256 storageBytes;
        uint256 availableStorageBytes;
        bool available;
    }

    struct Rental {
        uint256 resourceId;
        address renter;
        uint256 startTime;
        uint256 duration;
        uint256 totalCost;
        uint256 claimedTime;
        uint256 rentedCpu;
        uint256 rentedMemoryBytes;
        uint256 rentedGpu;
        uint256 rentedStorageBytes;
        uint256 cpuPricePerSecond;
        uint256 memoryPricePerSecond;
        uint256 gpuPricePerSecond;
        uint256 storagePricePerSecond;
        bool active;
    }

    uint256 public resourceCount;
    mapping(uint256 => Resource) public resources;
    mapping(uint256 => Rental) public rentals;
    uint256 public rentalCount;

    event ResourceRegistered(uint256 resourceId, address provider, uint256 cpuPricePerSecond, uint256 memoryPricePerSecond, uint256 gpuPricePerSecond, uint256 storagePricePerSecond, uint256 cpu, uint256 memoryBytes, uint256 gpu, uint256 storageBytes);
    event ResourceRented(uint256 rentalId, uint256 resourceId, address renter, uint256 duration, uint256 totalCost);
    event RentalCompleted(uint256 rentalId);

    function registerResource(
        uint256 cpuPricePerSecond,
        uint256 memoryPricePerSecond,
        uint256 gpuPricePerSecond,
        uint256 storagePricePerSecond,
        uint256 cpu,
        uint256 memoryBytes,
        uint256 gpu,
        uint256 storageBytes
    ) external {
        resources[++resourceCount] = Resource({
            id: resourceCount,
            provider: msg.sender,
            cpuPricePerSecond: cpuPricePerSecond,
            memoryPricePerSecond: memoryPricePerSecond,
            gpuPricePerSecond: gpuPricePerSecond,
            storagePricePerSecond: storagePricePerSecond,
            cpu: cpu,
            availableCpu: cpu,
            memoryBytes: memoryBytes,
            availableMemoryBytes: memoryBytes,
            gpu: gpu,
            availableGpu: gpu,
            storageBytes: storageBytes,
            availableStorageBytes: storageBytes,
            available: true
        });

        emit ResourceRegistered(resourceCount, msg.sender, cpuPricePerSecond, memoryPricePerSecond, gpuPricePerSecond, storagePricePerSecond, cpu, memoryBytes, gpu, storageBytes);
    }

    function rentResource(
        uint256 resourceId,
        uint256 duration,
        uint256 cpu,
        uint256 memoryBytes,
        uint256 gpu,
        uint256 storageBytes
    ) external payable {
        Resource storage resource = resources[resourceId];
        validateResource(resource, cpu, memoryBytes, gpu, storageBytes, duration);

        uint256 totalCost = calculateCost(resource, cpu, memoryBytes, gpu, storageBytes, duration);
        require(msg.value >= totalCost, "Insufficient payment");

        rentals[++rentalCount] = createRental(resourceId, msg.sender, duration, totalCost, cpu, memoryBytes, gpu, storageBytes, resource);
        updateResourceAvailability(resource, cpu, memoryBytes, gpu, storageBytes, false);

        emit ResourceRented(rentalCount, resourceId, msg.sender, duration, totalCost);
    }

    function completeRental(uint256 rentalId) external {
        Rental storage rental = rentals[rentalId];
        require(rental.active, "Rental already completed");
        require(block.timestamp >= rental.startTime + rental.duration, "Rental duration not yet completed");

        Resource storage resource = resources[rental.resourceId];
        updateResourceAvailability(resource, rental.rentedCpu, rental.rentedMemoryBytes, rental.rentedGpu, rental.rentedStorageBytes, true);

        rental.active = false;
        emit RentalCompleted(rentalId);
    }

    function claimEarnings(uint256 rentalId) external {
        Rental storage rental = rentals[rentalId];
        Resource storage resource = resources[rental.resourceId];
        require(rental.active, "Rental is not active");
        require(resource.provider == msg.sender, "Only the provider can claim earnings");

        processClaimEarnings(rental, resource);
    }

    function increaseRentedResources(
        uint256 rentalId,
        uint256 additionalCpu,
        uint256 additionalMemoryBytes,
        uint256 additionalGpu,
        uint256 additionalStorageBytes
    ) external payable {
        Rental storage rental = rentals[rentalId];
        Resource storage resource = resources[rental.resourceId];
        require(rental.active, "Rental is not active");
        require(rental.renter == msg.sender, "Only the renter can increase resources");

        processClaimEarnings(rental, resource);

        validateResource(resource, additionalCpu, additionalMemoryBytes, additionalGpu, additionalStorageBytes, rental.duration);
        uint256 additionalCost = calculateCost(resource, additionalCpu, additionalMemoryBytes, additionalGpu, additionalStorageBytes, rental.duration);
        require(msg.value >= additionalCost, "Insufficient payment");

        rental.totalCost += additionalCost;
        rental.rentedCpu += additionalCpu;
        rental.rentedMemoryBytes += additionalMemoryBytes;
        rental.rentedGpu += additionalGpu;
        rental.rentedStorageBytes += additionalStorageBytes;

        updateResourceAvailability(resource, additionalCpu, additionalMemoryBytes, additionalGpu, additionalStorageBytes, false);
        emit ResourceRented(rentalId, rental.resourceId, rental.renter, rental.duration, rental.totalCost);
    }

    function processClaimEarnings(Rental storage rental, Resource storage resource) internal {
        uint256 elapsedTime = block.timestamp > rental.startTime + rental.duration
            ? rental.duration
            : block.timestamp - rental.startTime;

        if (elapsedTime <= rental.claimedTime) return;

        uint256 claimableTime = elapsedTime - rental.claimedTime;
        uint256 claimableAmount = claimableTime * (
            (rental.cpuPricePerSecond * rental.rentedCpu) +
            (rental.memoryPricePerSecond * rental.rentedMemoryBytes) +
            (rental.gpuPricePerSecond * rental.rentedGpu) +
            (rental.storagePricePerSecond * rental.rentedStorageBytes)
        );

        rental.claimedTime += claimableTime;
        payable(resource.provider).transfer(claimableAmount);
    }

    function validateResource(
        Resource storage resource,
        uint256 cpu,
        uint256 memoryBytes,
        uint256 gpu,
        uint256 storageBytes,
        uint256 duration
    ) internal view {
        require(resource.available, "Resource not available");
        require(duration > 0, "Duration must be greater than 0");
        require(cpu <= resource.availableCpu, "Insufficient available CPU");
        require(memoryBytes <= resource.availableMemoryBytes, "Insufficient available Memory");
        require(gpu <= resource.availableGpu, "Insufficient available GPU");
        require(storageBytes <= resource.availableStorageBytes, "Insufficient available Storage");
    }

    function calculateCost(
        Resource storage resource,
        uint256 cpu,
        uint256 memoryBytes,
        uint256 gpu,
        uint256 storageBytes,
        uint256 duration
    ) internal view returns (uint256) {
        return (cpu * resource.cpuPricePerSecond * duration) +
               (memoryBytes * resource.memoryPricePerSecond * duration) +
               (gpu * resource.gpuPricePerSecond * duration) +
               (storageBytes * resource.storagePricePerSecond * duration);
    }

    function updateResourceAvailability(
        Resource storage resource,
        uint256 cpu,
        uint256 memoryBytes,
        uint256 gpu,
        uint256 storageBytes,
        bool increase
    ) internal {
        if (increase) {
            resource.availableCpu += cpu;
            resource.availableMemoryBytes += memoryBytes;
            resource.availableGpu += gpu;
            resource.availableStorageBytes += storageBytes;
        } else {
            resource.availableCpu -= cpu;
            resource.availableMemoryBytes -= memoryBytes;
            resource.availableGpu -= gpu;
            resource.availableStorageBytes -= storageBytes;
        }
    }

    function createRental(
        uint256 resourceId,
        address renter,
        uint256 duration,
        uint256 totalCost,
        uint256 cpu,
        uint256 memoryBytes,
        uint256 gpu,
        uint256 storageBytes,
        Resource storage resource
    ) internal view returns (Rental memory) {
        return Rental({
            resourceId: resourceId,
            renter: renter,
            startTime: block.timestamp,
            duration: duration,
            totalCost: totalCost,
            claimedTime: 0,
            rentedCpu: cpu,
            rentedMemoryBytes: memoryBytes,
            rentedGpu: gpu,
            rentedStorageBytes: storageBytes,
            cpuPricePerSecond: resource.cpuPricePerSecond,
            memoryPricePerSecond: resource.memoryPricePerSecond,
            gpuPricePerSecond: resource.gpuPricePerSecond,
            storagePricePerSecond: resource.storagePricePerSecond,
            active: true
        });
    }
}

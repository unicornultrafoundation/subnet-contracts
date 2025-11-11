// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ISubnetProvider {
    function getResourcePrice(address provider) external view returns (
        uint256 cpuPricePerSecond,
        uint256 gpuPricePerSecond,
        uint256 memoryPricePerSecond,
        uint256 diskPricePerSecond
    );
    function isProviderActive(address provider) external view returns (bool);
    function validateProviderRequirements(
        uint256 machineType,
        address provider,
        uint256 minCpuCores,
        uint256 minMemoryMB,
        uint256 minDiskGB,
        uint256 minGpuCores
    ) external view returns (bool);
    function isProviderOperatorOrOwner(address provider, address account) external view returns (bool);
    function getProviderOwner(address provider) external view returns (address);
    function setAuthorizedLocker(address locker, bool authorized) external;
    function lockResources(address provider, uint256 cpuCores, uint256 gpuCores, uint256 memoryMB, uint256 diskGB) external;
    function unlockResources(address provider, uint256 cpuCores, uint256 gpuCores, uint256 memoryMB, uint256 diskGB) external;
    function getAvailableResources(address provider) external view returns (
        uint256 availableCpu,
        uint256 availableGpu,
        uint256 availableMemory,
        uint256 availableDisk
    );
}

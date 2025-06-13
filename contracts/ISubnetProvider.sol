// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ISubnetProvider {
    function isMachineActive(uint256 providerId, uint256 machineId) external view returns (bool);
    function validateMachineRequirements(
        uint256 providerId,
        uint256 machineId,
        uint256 minCpuCores,
        uint256 minMemoryMB,
        uint256 minDiskGB,
        uint256 minGpuCores,
        uint256 minUploadSpeed,
        uint256 minDownloadSpeed
    ) external view returns (bool);
    function isProviderOperatorOrOwner(uint256 providerId, address account) external view returns (bool);
}

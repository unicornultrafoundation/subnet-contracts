// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./SubnetAppStore.sol";

/**
 * @title SubnetAppStore
 * @dev Registry to manage applications running on subnets and reward nodes based on resource usage.
 * Implements EIP-712 for structured data signing and Ownable for admin functionalities.
 */
contract SubnetAppStoreV2 is SubnetAppStore {

    /**
     * @dev Calculates the reward based on resource usage.
     * @param appId The application ID.
     * @param usedCpu The total CPU usage (in units) reported by the node.
     * @param usedGpu The total GPU usage (in units) reported by the node.
     * @param usedMemory The total memory usage (in GB) reported by the node.
     * @param usedStorage The total storage usage (in GB) reported by the node.
     * @param usedUploadBytes The total uploaded data (in bytes) reported by the node.
     * @param usedDownloadBytes The total downloaded data (in bytes) reported by the node.
     * @param duration The duration (in seconds) the node worked.
     * @return reward The calculated reward.
     */
    function calculateReward(
        uint256 appId,
        uint256 usedCpu,
        uint256 usedGpu,
        uint256 usedMemory,
        uint256 usedStorage,
        uint256 usedUploadBytes,
        uint256 usedDownloadBytes,
        uint256 duration
    ) public view override returns (uint256 reward) {
        App memory app = apps[appId];

        // Bandwidth usage (independent of duration)
        uint256 bandwidthGB = (usedUploadBytes + usedDownloadBytes) / 1e9;
        reward += bandwidthGB * app.pricePerBandwidthGB;

        // CPU (independent of duration)
        reward += usedCpu * app.pricePerCpu;

        // Memory, Storage, and GPU usage (dependent on duration)
        reward += (usedMemory * duration * app.pricePerMemoryGB) / 1e9;
        reward += (usedStorage * duration * app.pricePerStorageGB) / 1e9;
        reward += (usedGpu * duration * app.pricePerGpu) / 1e9;

        return reward;
    }
}

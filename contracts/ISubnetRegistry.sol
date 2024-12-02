// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ISubnetRegistry {
    struct Subnet {
        uint256 nftId; // NFT ID associated with the subnet
        address owner; // Address of the subnet owner
        string peerAddr; // Peer address of the subnet
        string metadata; // Metadata describing the subnet
        uint256 startTime; // Start time of the subnet's activity
        uint256 totalUptime; // Total uptime of the subnet
        uint256 claimedUptime; // Uptime claimed by the owner
        bool active; // Status of the subnet (active/inactive)
    }

    /**
     * @dev Retrieves the information of a subnet by its ID.
     * @param subnetId ID of the subnet.
     * @return Subnet The structure containing subnet information.
     */
    function subnets(uint256 subnetId) external view returns (Subnet memory);
}

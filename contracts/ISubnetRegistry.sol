// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ISubnetRegistry {
    struct Subnet {
        string name;
        uint256 nftId;
        address owner;
        address operator; // New operator field
        string peerAddr;
        string metadata;
        uint256 startTime;
        uint256 totalUptime;
        uint256 claimedUptime;
        bool active;
        uint256 trustScores;
    }

    /**
     * @dev Retrieves the information of a subnet by its ID.
     * @param subnetId ID of the subnet.
     * @return Subnet The structure containing subnet information.
     */
    function getSubnet(uint256 subnetId) external view returns (Subnet memory);
}

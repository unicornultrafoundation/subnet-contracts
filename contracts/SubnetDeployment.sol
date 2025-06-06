// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./SubnetAppStore.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 * @title SubnetDeployment
 * @dev This contract manages the deployment of subnets for applications in the SubnetAppStore.
 * It allows app owners to deploy subnets with specific Docker configurations on designated nodes.
 */
contract SubnetDeployment is Initializable {
    // Deployment structure
    struct Deployment {
        string dockerConfig;
        address owner; // App owner who created the deployment
        uint256 createdAt; // Timestamp when deployment was created
        uint256 updatedAt; // Timestamp when deployment was last updated
    }

    // Reference to SubnetAppStore
    SubnetAppStore public appStore;

    // Mapping to store deployments by appId and node IP
    mapping(uint256 => mapping(uint256 => Deployment)) private nodeDeployments;
    
    // Events
    event SubnetDeployed(uint256 indexed appId, uint256 indexed nodeIp, address indexed owner);
    event SubnetDeploymentUpdated(uint256 indexed appId, uint256 indexed nodeIp, string dockerConfig);
    event SubnetDeploymentDeleted(uint256 indexed appId, uint256 indexed nodeIp, address indexed owner);
    
    /**
     * @dev Initializes the contract with a reference to the SubnetAppStore.
     * @param _appStore The address of the SubnetAppStore contract.
     */
    function initialize(address _appStore) public initializer {
        require(_appStore != address(0), "Invalid SubnetAppStore address");
        appStore = SubnetAppStore(_appStore);
    }
    
    /**
     * @dev Deploys a subnet with a specific Docker configuration for a given node IP.
     * Only the owner of the application can deploy.
     * @param appId The ID of the application to deploy.
     * @param nodeIp The IP address of the node to deploy the subnet on.
     * @param dockerConfig The Docker configuration to use for the deployment.
     */
    function deploySubnet(
        uint256 appId,
        uint256 nodeIp,
        string memory dockerConfig
    ) public returns (Deployment memory) {
        // Verify the caller is the owner of the app
        SubnetAppStore.App memory app = appStore.getApp(appId);
        require(app.owner == msg.sender, "Only app owner can deploy subnets");

        // Create a new deployment
        Deployment memory newDeployment = Deployment({
            dockerConfig: dockerConfig,
            owner: msg.sender,
            createdAt: block.timestamp,
            updatedAt: block.timestamp
        });

        // Store the deployment in the mapping
        nodeDeployments[appId][nodeIp] = newDeployment;
        
        emit SubnetDeployed(appId, nodeIp, msg.sender);

        return newDeployment;
    }
    
    /**
     * @dev Updates an existing subnet deployment's Docker configuration
     * Only the owner of the application can update.
     * @param appId The ID of the application.
     * @param nodeIp The IP address of the node.
     * @param dockerConfig The new Docker configuration.
     */
    function updateDeployment(
        uint256 appId,
        uint256 nodeIp,
        string memory dockerConfig
    ) public {
        Deployment storage deployment = nodeDeployments[appId][nodeIp];
        require(deployment.owner == msg.sender, "Only deployment owner can update");
        
        deployment.dockerConfig = dockerConfig;
        deployment.updatedAt = block.timestamp;
        
        emit SubnetDeploymentUpdated(appId, nodeIp, dockerConfig);
    }
    
    /**
     * @dev Deletes an existing subnet deployment
     * Only the owner of the application can delete the deployment.
     * @param appId The ID of the application.
     * @param nodeIp The IP address of the node.
     */
    function deleteDeployment(
        uint256 appId,
        uint256 nodeIp
    ) public {
        Deployment storage deployment = nodeDeployments[appId][nodeIp];
        require(deployment.owner == msg.sender, "Only deployment owner can delete");
        
        // Store the owner for the event
        address owner = deployment.owner;
        
        // Delete the deployment by resetting its values
        delete nodeDeployments[appId][nodeIp];
        
        emit SubnetDeploymentDeleted(appId, nodeIp, owner);
    }

    /**
     * @dev Batch deletes multiple subnet deployments
     * Only the owner of the application can delete the deployments.
     * @param appId The ID of the application.
     * @param nodeIps Array of node IP addresses to delete deployments from.
     */
    function batchDeleteDeployments(
        uint256 appId,
        uint256[] memory nodeIps
    ) public {
        for (uint256 i = 0; i < nodeIps.length; i++) {
            if (nodeDeployments[appId][nodeIps[i]].owner == msg.sender) {
                delete nodeDeployments[appId][nodeIps[i]];
                emit SubnetDeploymentDeleted(appId, nodeIps[i], msg.sender);
            }
        }
    }

    /**
     * @dev Gets the deployment information for a specific app and node
     * @param appId The ID of the application.
     * @param nodeIp The IP address of the node.
     * @return The Deployment struct containing the Docker configuration, owner, and timestamps
     */
    function getDeployment(uint256 appId, uint256 nodeIp) public view returns (Deployment memory) {
        return nodeDeployments[appId][nodeIp];
    }
    
    /**
     * @dev Checks if a deployment exists for a specific app and node
     * @param appId The ID of the application.
     * @param nodeIp The IP address of the node.
     * @return true if deployment exists, false otherwise
     */
    function deploymentExists(uint256 appId, uint256 nodeIp) public view returns (bool) {
        // Check if a non-empty deployment exists (owner address is not zero)
        return nodeDeployments[appId][nodeIp].owner != address(0);
    }
    
    /**
     * @dev Gets the deployment duration in seconds
     * @param appId The ID of the application.
     * @param nodeIp The IP address of the node.
     * @return duration The time in seconds since deployment creation
     */
    function getDeploymentDuration(uint256 appId, uint256 nodeIp) public view returns (uint256 duration) {
        Deployment memory deployment = nodeDeployments[appId][nodeIp];
        require(deployment.owner != address(0), "Deployment does not exist");
        
        return block.timestamp - deployment.createdAt;
    }
    
    /**
     * @dev Gets the time since last update in seconds
     * @param appId The ID of the application.
     * @param nodeIp The IP address of the node.
     * @return timeSinceUpdate The time in seconds since last update
     */
    function getTimeSinceUpdate(uint256 appId, uint256 nodeIp) public view returns (uint256 timeSinceUpdate) {
        Deployment memory deployment = nodeDeployments[appId][nodeIp];
        require(deployment.owner != address(0), "Deployment does not exist");
        
        return block.timestamp - deployment.updatedAt;
    }
    
    /**
     * @dev Gets deployments for a specific app
     * @param appId The ID of the application.
     * @param nodeIps Array of node IP addresses to get deployments for.
     * @return deployments Array of Deployment structs
     */
    function getDeployments(uint256 appId, uint256[] memory nodeIps) public view returns (Deployment[] memory deployments) {
        deployments = new Deployment[](nodeIps.length);
        
        for (uint256 i = 0; i < nodeIps.length; i++) {
            deployments[i] = nodeDeployments[appId][nodeIps[i]];
        }
        
        return deployments;
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./SubnetAppStoreV2.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./SubnetVerifier.sol";

/**
 * @title SubnetAppStore
 * @dev Registry to manage applications running on subnets and reward nodes based on resource usage.
 * Implements EIP-712 for structured data signing and Ownable for admin functionalities.
 */
contract SubnetAppStoreV3 is SubnetAppStoreV2 {
    using SafeERC20 for IERC20;
    
    mapping(uint256 => address[]) public appVerifiers;
    SubnetVerifier public subnetVerifier;

    event VerifiersUpdated(uint256 indexed appId, address[] verifiers);
    event InactiveVerifierRemoved(uint256 indexed appId, address verifier);

    /**
     * @dev Sets the SubnetVerifier contract address.
     * @param _subnetVerifier The address of the SubnetVerifier contract.
     */
    function setSubnetVerifier(address _subnetVerifier) external onlyOwner {
        require(_subnetVerifier != address(0), "Invalid SubnetVerifier address");
        subnetVerifier = SubnetVerifier(_subnetVerifier);
    }

    /**
     * @dev Updates the verifiers of an existing application.
     * Only the owner of the application can perform the update.
     *
     * @param appId The ID of the application to update.
     * @param verifiers The new list of verifiers.
     */
    function updateVerifiers(uint256 appId, address[] memory verifiers) public {
        require(apps[appId].owner == msg.sender, "Only the owner can update the verifiers");
        appVerifiers[appId] = verifiers;
        emit VerifiersUpdated(appId, verifiers);
    }

    /**
     * @dev Removes an inactive verifier from the list of verifiers of an application.
     * Only the owner of the application can perform the removal.
     *
     * @param appId The ID of the application.
     * @param index The index of the verifier to remove.
     */
    function removeInactiveVerifier(uint256 appId, uint256 index) external  {
        address verifierAddr = appVerifiers[appId][index];
        require(!subnetVerifier.isActive(verifierAddr), "Verifier is active");
        appVerifiers[appId][index] = appVerifiers[appId][appVerifiers[appId].length - 1];
        appVerifiers[appId].pop();
        emit InactiveVerifierRemoved(appId, verifierAddr);
    }

    /**
     * @dev Reports usage for node resources based on usage data.
     * This function calculates rewards for a node by validating its reported resource usage,
     * ensuring it's within the application's budget, and storing the pending rewards.
     *
     * @param appId The ID of the application the node is working on.
     * @param providerId The ID of the provider where the node is registered.
     * @param peerId The ID of the peer node.
     * @param usedCpu The total CPU usage (in units) reported by the node.
     * @param usedGpu The total GPU usage (in units) reported by the node.
     * @param usedMemory The total memory usage (in GB) reported by the node.
     * @param usedStorage The total storage usage (in GB) reported by the node.
     * @param usedUploadBytes The total uploaded data (in bytes) reported by the node.
     * @param usedDownloadBytes The total downloaded data (in bytes) reported by the node.
     * @param duration The duration (in seconds) the node worked.
     * @param timestamp The timestamp of the usage report.
     * @param signatures The EIP-712 signature from the application owner or operator validating the usage data.
     */
    function reportUsage(
        uint256 appId,
        uint256 providerId,
        string memory peerId,
        uint256 usedCpu,
        uint256 usedGpu,
        uint256 usedMemory,
        uint256 usedStorage,
        uint256 usedUploadBytes,
        uint256 usedDownloadBytes,
        uint256 duration,
        uint256 timestamp,
        bytes memory signatures
    ) external override {
         // Hash and verify usage data
        Usage memory usage = Usage({
            appId: appId,
            providerId: providerId,
            peerId: peerId,
            usedCpu: usedCpu,
            usedGpu: usedGpu,
            usedMemory: usedMemory,
            usedStorage: usedStorage,
            usedUploadBytes: usedUploadBytes,
            usedDownloadBytes: usedDownloadBytes,
            duration: duration,
            timestamp: timestamp
        });

        validateUsageInputs(usage);
        bytes32 structHash = hashUsageData(usage);
        verifySignatures(usage.appId, structHash, signatures);
        uint256 reward = calculateReward(usage.appId, usage.usedCpu, usage.usedGpu, usage.usedMemory, usage.usedStorage, usage.usedUploadBytes, usage.usedDownloadBytes, usage.duration);
        processRewards(usage, reward);
    }

    function validateUsageInputs(Usage memory usage) internal view {
        require(usage.appId > 0 && usage.appId <= appCount, "Invalid App ID");
        App storage app = apps[usage.appId];
        require(app.budget > app.spentBudget, "App budget exhausted");
        require(subnetProvider.getPeerNode(usage.providerId, usage.peerId).isRegistered, "Peer node not registered");
    }

    function hashUsageData(Usage memory usage) internal returns (bytes32) {
        bytes32 structHash = _hashTypedDataV4(_hashUpdateUsageData(usage));
        require(!usedMessageHashes[structHash], "Replay attack detected");
        usedMessageHashes[structHash] = true;
        return structHash;
    }

    function verifySignatures(
        uint256 appId,
        bytes32 structHash,
        bytes memory _signatures
    ) internal view {
        bytes[] memory signatures = splitSignatures(_signatures);
        if (signatures.length > 1) {
            uint256 validSignatures = 0;
            for (uint256 i = 0; i < signatures.length; i++) {
                address signer = ECDSA.recover(structHash, signatures[i]);
                for (uint256 j = 0; j < appVerifiers[appId].length; j++) {
                    if (signer == appVerifiers[appId][j]) {
                        validSignatures++;
                        break;
                    }
                }
            }
            require(validSignatures >= (2 * appVerifiers[appId].length) / 3, "Not enough valid signatures");
        } else {
            address signer = ECDSA.recover(structHash, signatures[0]);
            require(signer == apps[appId].operator, "Invalid signature");
        }
    }

    function processRewards(
        Usage memory usage,
        uint256 reward
    ) internal {
        App storage app = apps[usage.appId];
        require(app.budget >= app.spentBudget + reward, "Insufficient budget");

        uint256 protocolFees = 0;
        uint256 verifierReward = 0;

        if (feeRate > 0 && treasury != address(0)) {
            protocolFees = (reward * feeRate) / 1000;
            reward -= protocolFees;
            IERC20(app.paymentToken).safeTransfer(treasury, protocolFees);
        }

        if (verifierRewardRate > 0 && appVerifiers[usage.appId].length > 0) {
            verifierReward = (reward * verifierRewardRate) / 1000;
            for (uint256 i = 0; i < appVerifiers[usage.appId].length; i++) {
                reward -= verifierReward;
                IERC20(app.paymentToken).safeTransfer(appVerifiers[usage.appId][i], verifierReward);
            }
        }

        pendingRewards[usage.appId][usage.providerId] += reward;
        app.spentBudget += reward + verifierReward + protocolFees;
        emit UsageReported(
            usage.appId,
            usage.providerId,
            usage.peerId,
            usage.usedCpu,
            usage.usedGpu,
            usage.usedMemory,
            usage.usedStorage,
            usage.usedUploadBytes,
            usage.usedDownloadBytes,
            usage.duration,
            usage.timestamp,
            reward
        );
    }

    /**
     * @dev Pays the locked reward to the provider and the verifier.
     * @param appId The ID of the application.
     * @param lockedReward The locked reward details.
     */
    function _payLockedReward(uint256 appId, LockedReward memory lockedReward) internal override {
        IERC20(apps[appId].paymentToken).safeTransfer(msg.sender, lockedReward.reward);
        emit LockedRewardPaid(appId, lockedReward.reward, 0, 0, msg.sender, address(0x0));
    }


    function splitSignatures(bytes memory signatures) internal pure returns (bytes[] memory) {
        require(signatures.length % 65 == 0, "Invalid signature length");
        
        uint256 numSignatures = signatures.length / 65;
        bytes[] memory sigArray = new bytes[](numSignatures);
        
        for (uint256 i = 0; i < numSignatures; i++) {
            bytes memory sig = new bytes(65);
            for (uint256 j = 0; j < 65; j++) {
                sig[j] = signatures[i * 65 + j];
            }
            sigArray[i] = sig;
        }

        return sigArray;
    }
}

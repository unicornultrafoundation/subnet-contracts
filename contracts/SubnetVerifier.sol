// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract SubnetVerifier is Initializable, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    struct VerifierInfo {
        bool isRegistered;
        string[] peerIds;
    }

    mapping(address => VerifierInfo) public verifiers;

    event VerifierRegistered(address indexed verifier);
    event VerifierPeersUpdated(address indexed verifier, string[] peerIds);
    event VerifierDeleted(address indexed verifier);

    function initialize(address _initialOwner) external initializer {
        __Ownable_init(_initialOwner);
    }

    /**
     * @dev Registers a new verifier.
     * @param verifier Address of the verifier.
     * @param peerIds Array of peer IDs associated with the verifier.
     */
    function registerVerifier(
        address verifier,
        string[] memory peerIds
    ) external onlyOwner {
        require(
            !verifiers[verifier].isRegistered,
            "Verifier already registered"
        );
        verifiers[verifier] = VerifierInfo({
            isRegistered: true,
            peerIds: peerIds
        });
        emit VerifierRegistered(verifier);
    }

    /**
     * @dev Updates the peer nodes for a verifier.
     * @param verifier Address of the verifier.
     * @param peerIds Array of new peer IDs associated with the verifier.
     */
    function updateVerifierPeers(
        address verifier,
        string[] memory peerIds
    ) external {
        require(verifiers[verifier].isRegistered, "Verifier not registered");
        require(
            msg.sender == verifier || msg.sender == owner(),
            "Only the verifier or owner can update peers"
        );
        verifiers[verifier].peerIds = peerIds;
        emit VerifierPeersUpdated(verifier, peerIds);
    }

    /**
     * @dev Deletes a verifier.
     * @param verifier Address of the verifier to delete.
     */
    function deleteVerifier(address verifier) external onlyOwner {
        require(verifiers[verifier].isRegistered, "Verifier not registered");
        delete verifiers[verifier];
        emit VerifierDeleted(verifier);
    }

    /**
     * @dev Gets the verifier information.
     * @param verifier Address of the verifier.
     * @return VerifierInfo struct containing the verifier information.
     */
    function getVerifierInfo(address verifier) external view returns (VerifierInfo memory) {
        return verifiers[verifier];
    }

    function version() public pure returns (string memory) {
        return "1.0.0";
    }
}

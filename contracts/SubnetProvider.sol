// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract SubnetProvider is Initializable, ERC721Upgradeable {
    uint256 private _tokenIds;

    struct PeerNode {
        bool isRegistered;
        string metadata;
    }

    struct Provider {
        uint256 tokenId;
        string providerName;
        address operator;
        string website;
        string metadata;
    }

    mapping(uint256 => Provider) public providers;
    mapping(uint256 => mapping(string => PeerNode)) public peerNodeRegistered; // Track registered peer nodes for each provider

    event ProviderRegistered(address providerAddress, uint256 tokenId, string providerName, string metadata, address operator, string website);
    event NFTMinted(address providerAddress, uint256 tokenId);
    event ProviderUpdated(uint256 tokenId, string providerName, string metadata, address operator, string website);
    event ProviderDeleted(uint256 tokenId);
    event OperatorUpdated(uint256 tokenId, address operator);
    event WebsiteUpdated(uint256 tokenId, string website);
    event PeerNodeRegistered(uint256 indexed tokenId, string peerId, string metadata);
    event PeerNodeDeleted(uint256 indexed tokenId, string peerId);
    event PeerNodeUpdated(uint256 indexed tokenId, string peerId, string metadata);

    function initialize() external initializer {
        __ERC721_init("SubnetProvider", "SUBNET");
    }

    /**
     * @dev Registers a new provider and mints an NFT.
     * @param _providerName Name of the provider.
     * @param _metadata Additional metadata for the provider.
     * @param _operator Address of the operator.
     * @param _website Website of the provider.
     */
    function registerProvider(string memory _providerName, string memory _metadata, address _operator, string memory _website) public returns (uint256) {
        _tokenIds++;
        uint256 newItemId = _tokenIds;
        _mint(msg.sender, newItemId);

        providers[newItemId] = Provider({
            tokenId: newItemId,
            providerName: _providerName,
            operator: _operator,
            website: _website,
            metadata: _metadata
        });

        emit ProviderRegistered(msg.sender, newItemId, _providerName, _metadata, _operator, _website);
        emit NFTMinted(msg.sender, newItemId);
        return newItemId;
    }

    /**
     * @dev Updates the provider information.
     * @param tokenId ID of the token.
     * @param _providerName New name of the provider.
     * @param _metadata New additional metadata for the provider.
     * @param _operator New operator address.
     * @param _website New website of the provider.
     */
    function updateProvider(uint256 tokenId, string memory _providerName, string memory _metadata, address _operator, string memory _website) public {
        require(ownerOf(tokenId) == msg.sender || providers[tokenId].operator == msg.sender, "Not the owner or operator of this token");

        Provider storage provider = providers[tokenId];
        provider.providerName = _providerName;
        provider.metadata = _metadata;
        provider.operator = _operator;
        provider.website = _website;

        emit ProviderUpdated(tokenId, _providerName, _metadata, _operator, _website);
    }

    /**
     * @dev Updates the operator of a provider.
     * @param tokenId ID of the token.
     * @param _operator New operator address.
     */
    function updateOperator(uint256 tokenId, address _operator) public {
        require(ownerOf(tokenId) == msg.sender || providers[tokenId].operator == msg.sender, "Not the owner or operator of this token");

        Provider storage provider = providers[tokenId];
        provider.operator = _operator;

        emit OperatorUpdated(tokenId, _operator);
    }

    /**
     * @dev Updates the website of a provider.
     * @param tokenId ID of the token.
     * @param _website New website of the provider.
     */
    function updateWebsite(uint256 tokenId, string memory _website) public {
        require(ownerOf(tokenId) == msg.sender || providers[tokenId].operator == msg.sender, "Not the owner or operator of this token");

        Provider storage provider = providers[tokenId];
        provider.website = _website;

        emit WebsiteUpdated(tokenId, _website);
    }

    /**
     * @dev Deletes the provider information and burns the NFT.
     * @param tokenId ID of the token.
     */
    function deleteProvider(uint256 tokenId) public {
        require(ownerOf(tokenId) == msg.sender, "Not the owner of this token");

        _burn(tokenId);
        delete providers[tokenId];

        emit ProviderDeleted(tokenId);
    }

    /**
     * @dev Registers a new peer node for a provider.
     * @param tokenId ID of the provider's token.
     * @param peerId ID of the peer node.
     * @param metadata Metadata for the peer node.
     */
    function registerPeerNode(uint256 tokenId, string memory peerId, string memory metadata) public {
        require(ownerOf(tokenId) == msg.sender || providers[tokenId].operator == msg.sender, "Not the owner or operator of this token");
        require(!peerNodeRegistered[tokenId][peerId].isRegistered, "Peer node already registered");
        peerNodeRegistered[tokenId][peerId] = PeerNode({
            isRegistered: true,
            metadata: metadata
        });

        emit PeerNodeRegistered(tokenId, peerId, metadata);
    }

    /**
     * @dev Updates the metadata of a peer node for a provider.
     * @param tokenId ID of the provider's token.
     * @param peerId ID of the peer node.
     * @param metadata New metadata for the peer node.
     */
    function updatePeerNode(uint256 tokenId, string memory peerId, string memory metadata) public {
        require(ownerOf(tokenId) == msg.sender || providers[tokenId].operator == msg.sender, "Not the owner or operator of this token");
        require(peerNodeRegistered[tokenId][peerId].isRegistered, "Peer node not registered");
        peerNodeRegistered[tokenId][peerId].metadata = metadata;

        emit PeerNodeUpdated(tokenId, peerId, metadata);
    }

    /**
     * @dev Deletes a peer node for a provider.
     * @param tokenId ID of the provider's token.
     * @param peerId ID of the peer node to delete.
     */
    function deletePeerNode(uint256 tokenId, string memory peerId) public {
        require(ownerOf(tokenId) == msg.sender || providers[tokenId].operator == msg.sender, "Not the owner or operator of this token");
        require(peerNodeRegistered[tokenId][peerId].isRegistered, "Peer node not registered");
        delete peerNodeRegistered[tokenId][peerId];

        emit PeerNodeDeleted(tokenId, peerId);
    }

    /**
     * @dev Retrieves the peer node information for a given provider and peer ID.
     * @param tokenId ID of the provider's token.
     * @param peerId ID of the peer node.
     * @return peerNode Information of the peer node.
     */
    function getPeerNode(uint256 tokenId, string memory peerId) public view returns (PeerNode memory) {
        return peerNodeRegistered[tokenId][peerId];
    }

    /**
     * @dev Returns the provider information for a given token ID.
     * @param _tokenId ID of the token.
     * @return Provider information.
     */
    function getProvider(uint256 _tokenId) public view returns (Provider memory) {
        return providers[_tokenId];
    }

    function version() public pure returns (string memory) {
        return "1.0.0";
    }

}
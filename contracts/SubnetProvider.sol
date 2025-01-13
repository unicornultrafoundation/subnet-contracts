// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract SubnetProvider is ERC721 {
    uint256 private _tokenIds;

    struct Provider {
        uint256 tokenId;
        string providerName;
        string metadata;
    }

    mapping(uint256 => Provider) public providers;

    event ProviderRegistered(address providerAddress, uint256 tokenId, string providerName, string metadata);
    event NFTMinted(address providerAddress, uint256 tokenId);
    event ProviderUpdated(uint256 tokenId, string providerName, string metadata);
    event ProviderDeleted(uint256 tokenId);

    constructor() ERC721("SubnetProviderNFT", "SPN") {}

    /**
     * @dev Registers a new provider and mints an NFT.
     * @param _providerName Name of the provider.
     * @param _metadata Additional metadata for the provider.
     */
    function registerProvider(string memory _providerName, string memory _metadata) public {
        require(balanceOf(msg.sender) == 0, "Provider already registered");

        _tokenIds++;
        uint256 newItemId = _tokenIds;
        _mint(msg.sender, newItemId);

        providers[newItemId] = Provider({
            tokenId: newItemId,
            providerName: _providerName,
            metadata: _metadata
        });

        emit ProviderRegistered(msg.sender, newItemId, _providerName, _metadata);
        emit NFTMinted(msg.sender, newItemId);
    }

    /**
     * @dev Updates the provider information.
     * @param tokenId ID of the token.
     * @param _providerName New name of the provider.
     * @param _metadata New additional metadata for the provider.
     */
    function updateProvider(uint256 tokenId, string memory _providerName, string memory _metadata) public {
        require(ownerOf(tokenId) == msg.sender, "Not the owner of this token");

        Provider storage provider = providers[tokenId];
        provider.providerName = _providerName;
        provider.metadata = _metadata;

        emit ProviderUpdated(tokenId, _providerName, _metadata);
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
     * @dev Returns the provider information for a given token ID.
     * @param _tokenId ID of the token.
     * @return Provider information.
     */
    function getProvider(uint256 _tokenId) public view returns (Provider memory) {
        return providers[_tokenId];
    }
}
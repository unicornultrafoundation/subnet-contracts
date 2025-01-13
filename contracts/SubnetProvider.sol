// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";

contract SubnetProvider is ERC721URIStorage {
    uint256 private _tokenIds;

    struct Provider {
        uint256 tokenId;
        string providerName;
        string metadata;
    }

    mapping(uint256 => Provider) public providers;
    mapping(address => uint256) public providerTokens;
    address[] public providerList;

    event ProviderRegistered(address providerAddress, uint256 tokenId, string providerName, string metadata);
    event NFTMinted(address providerAddress, uint256 tokenId);
    event ProviderUpdated(uint256 tokenId, string providerName, string metadata);

    constructor() ERC721("SubnetProviderNFT", "SPN") {}

    function registerProvider(string memory _providerName, string memory tokenURI, string memory _metadata) public {
        require(providerTokens[msg.sender] == 0, "Provider already registered");

        _tokenIds++;
        uint256 newItemId = _tokenIds;
        _mint(msg.sender, newItemId);
        _setTokenURI(newItemId, tokenURI);

        providers[newItemId] = Provider({
            tokenId: newItemId,
            providerName: _providerName,
            metadata: _metadata
        });

        providerTokens[msg.sender] = newItemId;
        providerList.push(msg.sender);

        emit ProviderRegistered(msg.sender, newItemId, _providerName, _metadata);
        emit NFTMinted(msg.sender, newItemId);
    }

    function updateProvider(string memory _providerName, string memory tokenURI, string memory _metadata) public {
        uint256 tokenId = providerTokens[msg.sender];
        require(tokenId != 0, "Provider not registered");

        Provider storage provider = providers[tokenId];
        provider.providerName = _providerName;
        provider.metadata = _metadata;

        _setTokenURI(tokenId, tokenURI);

        emit ProviderUpdated(tokenId, _providerName, _metadata);
    }

    function getProvider(uint256 _tokenId) public view returns (Provider memory) {
        return providers[_tokenId];
    }

    function getAllProviders() public view returns (Provider[] memory) {
        Provider[] memory allProviders = new Provider[](providerList.length);
        for (uint256 i = 0; i < providerList.length; i++) {
            uint256 tokenId = providerTokens[providerList[i]];
            allProviders[i] = providers[tokenId];
        }
        return allProviders;
    }
}
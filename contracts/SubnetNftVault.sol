// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract SubnetNftVault is ERC20, ERC20Permit {
    address public immutable nftContract; // Allowed NFT contract
    mapping(uint256 => address) public nftOwner; // Mapping from tokenId to owner address

     // Events
    event Locked(address indexed owner, uint256 indexed tokenId);
    event Redeemed(address indexed owner, uint256 indexed tokenId);
    event LockedBatch(address indexed owner, uint256[] tokenIds);
    event RedeemedBatch(address indexed owner, uint256[] tokenIds);

    constructor(
        string memory name_,
        string memory symbol_,
        address nftContract_
    ) ERC20(name_, symbol_) ERC20Permit(symbol_) {
        nftContract = nftContract_;
    }

    /// @notice Locks an NFT into the vault and mints ERC20 tokens
    /// @param tokenId The ID of the NFT to lock
    function lock(uint256 tokenId) external {
        // Ensure the caller is the owner of the NFT
        require(IERC721(nftContract).ownerOf(tokenId) == msg.sender, "Not the owner of the NFT");

        // Transfer the NFT to the contract
        IERC721(nftContract).transferFrom(msg.sender, address(this), tokenId);

        // Record the owner of the NFT
        nftOwner[tokenId] = msg.sender;

        // Mint 1 ERC20 token to the caller (1-to-1 mapping for simplicity)
        _mint(msg.sender, 1 ether); // Mint 1 token with 18 decimals

        emit Locked(msg.sender, tokenId); // Emit event
    }

    /// @notice Redeems an NFT by burning ERC20 tokens
    /// @param tokenId The ID of the NFT to redeem
    function redeem(uint256 tokenId) external {
        // Ensure the NFT is locked and owned by the caller
        require(nftOwner[tokenId] == msg.sender, "Not the NFT owner");

        // Burn 1 ERC20 token from the caller (1-to-1 mapping for simplicity)
        _burn(msg.sender, 1 ether); // Burn 1 token with 18 decimals

        // Transfer the NFT back to the caller
        IERC721(nftContract).transferFrom(address(this), msg.sender, tokenId);

        // Clear the owner record for the NFT
        delete nftOwner[tokenId];

        emit Redeemed(msg.sender, tokenId); // Emit event
    }

    /// @notice Locks multiple NFTs into the vault and mints ERC20 tokens
    /// @param tokenIds The IDs of the NFTs to lock
    function lockBatch(uint256[] calldata tokenIds) external {
        uint256 length = tokenIds.length;
        require(length > 0, "No tokenIds provided");

        for (uint256 i = 0; i < length; i++) {
            uint256 tokenId = tokenIds[i];

            // Ensure the caller is the owner of the NFT
            require(IERC721(nftContract).ownerOf(tokenId) == msg.sender, "Not the owner of the NFT");

            // Transfer the NFT to the contract
            IERC721(nftContract).transferFrom(msg.sender, address(this), tokenId);

            // Record the owner of the NFT
            nftOwner[tokenId] = msg.sender;
        }

        // Mint tokens to the caller (1 token per NFT locked)
        _mint(msg.sender, length * 1 ether); // Mint tokens with 18 decimals
        emit LockedBatch(msg.sender, tokenIds); // Emit event
    }

    /// @notice Redeems multiple NFTs by burning ERC20 tokens
    /// @param tokenIds The IDs of the NFTs to redeem
    function redeemBatch(uint256[] calldata tokenIds) external {
        uint256 length = tokenIds.length;
        require(length > 0, "No tokenIds provided");

        for (uint256 i = 0; i < length; i++) {
            uint256 tokenId = tokenIds[i];

            // Ensure the NFT is locked and owned by the caller
            require(nftOwner[tokenId] == msg.sender, "Not the NFT owner");

            // Clear the owner record for the NFT
            delete nftOwner[tokenId];

            // Transfer the NFT back to the caller
            IERC721(nftContract).transferFrom(address(this), msg.sender, tokenId);
        }

        // Burn tokens from the caller (1 token per NFT redeemed)
        _burn(msg.sender, length * 1 ether); // Burn tokens with 18 decimals
        emit RedeemedBatch(msg.sender, tokenIds); // Emit event
    }
}

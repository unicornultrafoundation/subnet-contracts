// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Importing OpenZeppelin upgradeable contracts for initialization, ownership, and ERC721 functionality.
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// SubnetIPRegistry is an upgradeable contract that manages IP ownership and peer bindings using ERC721 tokens.
contract SubnetIPRegistry is Initializable, ERC721Upgradeable, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    // Mapping to associate a token ID (IP) with a peer ID.
    mapping(uint256 => string) public ipPeer;

    // Address of the ERC20 token used for payments.
    IERC20 public paymentToken;

    // Address of the treasury where fees will be sent.
    address public treasury;

    // Fee amount required for purchasing an IP.
    uint256 public purchaseFee;

    // Tracks the next available IP.
    uint256 private nextIp;

    // Event emitted when a peer ID is bound to a token ID.
    event PeerBound(uint256 indexed tokenId, string peerId);

    // Initializes the contract with the given owner, payment token, treasury address, and fee.
    // @param initialOwner The address of the initial owner of the contract.
    // @param _paymentToken The address of the ERC20 token used for payments.
    // @param _treasury The address of the treasury to receive fees.
    // @param _purchaseFee The fee amount required for purchasing an IP.
    function initialize(
        address initialOwner,
        IERC20 _paymentToken,
        address _treasury,
        uint256 _purchaseFee
    ) external initializer {
        __ERC721_init("SubnetIP", "SIP"); // Initialize the ERC721 token with name and symbol.
        __Ownable_init(initialOwner); // Set the initial owner of the contract.
        paymentToken = _paymentToken; // Set the payment token.
        treasury = _treasury; // Set the treasury address.
        purchaseFee = _purchaseFee; // Set the purchase fee.

        // Initialize the next IP to start at 10.0.0.0 (0x0A000000).
        nextIp = 0x0A000001;
    }

    // Allows a user to purchase an IP by minting a new token.
    // Automatically assigns the next available IP in the 10.x.x.x range.
    // @param to The address that will receive the minted token.
    function purchase(address to) external {
        // Ensure the IP is within the 10.x.x.x range.
        require((nextIp & 0xFF000000) == 0x0A000000, "IP range exceeded");

        // Transfer the purchase fee from the sender to the treasury using safeTransferFrom.
        paymentToken.safeTransferFrom(msg.sender, treasury, purchaseFee);

        _mint(to, nextIp); // Mint the token to the specified address.

        // Increment the next IP.
        nextIp++;
    }

    // Binds a peer ID to a token ID (IP) if the caller owns the token.
    // @param tokenId The ID of the token (IP) to bind the peer ID to.
    // @param peerId The peer ID to associate with the token ID.
    function bindPeer(uint256 tokenId, string calldata peerId) external {
        require(ownerOf(tokenId) == msg.sender, "Not authorized"); // Ensure the caller owns the token.
        ipPeer[tokenId] = peerId; // Bind the peer ID to the token ID.
        emit PeerBound(tokenId, peerId); // Emit the PeerBound event.
    }

    // Retrieves the peer ID associated with a given token ID (IP).
    // @param tokenId The ID of the token (IP) to retrieve the peer ID for.
    // @return The peer ID associated with the given token ID.
    function getPeer(uint256 tokenId) external view returns (string memory) {
        return ipPeer[tokenId]; // Return the peer ID for the token ID.
    }
}

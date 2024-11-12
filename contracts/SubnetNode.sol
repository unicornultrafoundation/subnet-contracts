// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract SubnetNode is Ownable, EIP712 {
    // Domain Separator (EIP-712)
    string private constant SIGNING_DOMAIN = "SubnetNode";
    string private constant SIGNATURE_VERSION = "1";

    // Enum to define the pricing methods for the session
    // Pricing can either be based on the amount of data used (ByGB) or the duration (ByHour)
    enum PricingType {
        ByGB, // Pricing based on the amount of data used, in GB
        ByHour // Pricing based on the duration of the session, in hours
    }

    // Structure to store information about each Node (server)
    // Each Node represents a participating server in the network
    struct NodeInfo {
        string name; // The name of the Node (e.g., "Node A")
        address account; // The Ethereum address associated with the Node
        bytes publicKey; // The public key of the Node, used for encryption or authentication purposes
        uint256 pricePerGB; // Price the Node charges for each GB of data transferred or used
        uint256 pricePerHour; // Price the Node charges per hour of service
        bool registered; // Indicates whether the Node is registered and can participate in sessions
        uint256 lastActiveTime; // Timestamp of the last time the Node was active (used to check if it's inactive)
    }

    // Structure to store information about each session
    // Each Session tracks the interaction between a client and a Node
    struct Session {
        address client; // The address of the client who created the session
        address node; // The address of the Node the client is interacting with
        uint256 startTime; // The timestamp when the session started
        uint256 endTime; // The timestamp when the session ended (updated after the session finishes)
        uint256 downloadBytes; // The total amount of data downloaded by the client during this session (in GB)
        uint256 uploadBytes; // The total amount of data uploaded by the client during this session (in GB)
        uint256 duration; // The duration of the session (in seconds, or hours depending on pricing)
        bool active; // A flag indicating whether the session is currently active or has ended
        uint256 lastActiveTime; // Timestamp of the last activity in the session (used to track inactivity)
        uint256 deposit; // The deposit made by the client to start the session, used to calculate costs
        PricingType pricingType; // The pricing method used for this session (ByGB or ByHour)
    }

    // EIP-712 struct for UpdateUsage message
    struct UpdateUsageData {
        bytes32 sessionId;
        uint256 downloadBytes;
        uint256 uploadBytes;
        uint256 duration;
    }

    // Event for session end
    event SessionEnded(
        bytes32 indexed sessionId,
        uint256 totalCost,
        uint256 refundAmount,
        uint256 protocolCommission,
        uint256 nodePayment
    );

    // Mapping to store Node information, accessible via the Node's address
    mapping(address => NodeInfo) public nodes;

    // Mapping to store session information, each session identified by a sessionId (bytes32)
    mapping(bytes32 => Session) public sessions;

    // Mapping to store used message hashes to avoid duplicate updates
    mapping(bytes32 => bool) public usedMessageHashes;

    uint256 public inactivityTimeout = 1 hours; // Timeout for inactivity
    address public protocolWallet; // Protocol wallet address
    uint256 public protocolCommissionPercentage; // Protocol commission percentage in basis points (1% = 10000, 5% = 50000)

    // Event to be emitted when a new Node is registered
    event NodeRegistered(
        address indexed nodeAddress,
        string name,
        bytes publicKey,
        uint256 pricePerGB,
        uint256 pricePerHour
    );

    // Event to be emitted when a Node updates its status
    event NodeStatusUpdated(
        address indexed nodeAddress,
        uint256 lastActiveTime
    );

    // Event to be emitted when a Node is deleted
    event NodeDeleted(
        address indexed nodeAddress
    );

    // Event for creating a new session
    event SessionCreated(
        bytes32 indexed sessionId,
        address indexed client,
        address indexed node,
        uint256 deposit,
        PricingType pricingType
    );

     // Event for updating session usage
    event UsageUpdated(
        bytes32 indexed sessionId,
        uint256 downloadBytes,
        uint256 uploadBytes,
        uint256 duration,
        uint256 lastActiveTime
    );

     // Event for session refund
    event SessionRefunded(
        bytes32 indexed sessionId,
        uint256 refundAmount
    );

    // Modifier to only allow registered Nodes to call the function
    modifier onlyRegisteredNode(address node) {
        require(nodes[node].registered, "Node not registered"); // Check if the Node is registered
        _;
    }

    modifier nodeIsActive(address node) {
        // Check if the node is active based on the lastActiveTime
        require(
            block.timestamp <= nodes[node].lastActiveTime + inactivityTimeout,
            "Node is inactive"
        );
        _;
    }

    constructor(
        address initialOwner
    ) Ownable(initialOwner) EIP712(SIGNING_DOMAIN, SIGNATURE_VERSION) {}

    // Function to set the protocol wallet and commission rate (only owner can set)
    function setProtocolDetails(
        address _protocolWallet,
        uint256 _commissionPercentage
    ) public onlyOwner {
        require(
            _commissionPercentage <= 1000000,
            "Invalid commission percentage"
        ); // Ensure it doesn't exceed 100%
        protocolWallet = _protocolWallet;
        protocolCommissionPercentage = _commissionPercentage;
    }

    // Function to register a new Node
    function registerNode(
        string memory name, // The name of the Node
        bytes memory publicKey, // The public key of the Node
        uint256 pricePerGB, // Price per GB of data
        uint256 pricePerHour // Price per hour
    ) public {
        // Check if the Node is already registered by verifying the registered status in the mapping
        require(!nodes[msg.sender].registered, "Node already registered"); // Ensure the node isn't already registered

        // Add the Node information to the mapping, setting up the Node's details
        nodes[msg.sender] = NodeInfo({
            name: name, // Store the Node's name
            account: msg.sender, // Store the address of the Node
            publicKey: publicKey, // Store the Node's public key
            pricePerGB: pricePerGB, // Store the price per GB of data
            pricePerHour: pricePerHour, // Store the price per hour
            registered: true, // Mark the node as registered
            lastActiveTime: block.timestamp // Set the last active time to the current timestamp
        });

        // Emit the NodeRegistered event after a successful registration
        emit NodeRegistered(msg.sender, name, publicKey, pricePerGB, pricePerHour);
    }

    // Function to allow the Node to update its activity status
    function updateNodeStatus() public onlyRegisteredNode(msg.sender) {
        // Update the last active time to the current timestamp to reflect the Node's recent activity
        nodes[msg.sender].lastActiveTime = block.timestamp; // Update the node's last active time to current time

        // Emit the NodeStatusUpdated event after updating the status
        emit NodeStatusUpdated(msg.sender, block.timestamp);
    }

    // Function to delete the Node's registration
    function deleteNode() public onlyRegisteredNode(msg.sender) {
        // Mark the Node as unregistered, effectively deleting the Node's registration
        nodes[msg.sender].registered = false; // Set the registered flag to false, removing the Node from the system

        // Emit the NodeDeleted event to notify the deletion
        emit NodeDeleted(msg.sender);
    }

    // Function for the client to initiate a new session with a specified Node
    function createSession(
        address node,
        PricingType pricingType
    ) public payable returns (bytes32) {
        // Ensure that the specified Node is registered in the system
        require(nodes[node].registered, "Node not registered");

        // Ensure that the Node is active by checking its last active time against the inactivity timeout
        require(
            block.timestamp <= nodes[node].lastActiveTime + inactivityTimeout,
            "Node is inactive" // The Node is considered inactive if the current time exceeds the allowed inactivity period
        );

        // Ensure that the client deposits some value to start the session
        require(msg.value > 0, "Deposit must be greater than 0"); // Deposit must be greater than 0

        // Generate a unique sessionId using the client's address, the node's address, and the current timestamp
        bytes32 sessionId = keccak256(
            abi.encodePacked(msg.sender, node, block.timestamp) // Create a unique session ID by hashing relevant data
        );

        // Create a new session and store it in the sessions mapping for tracking
        sessions[sessionId] = Session({
            client: msg.sender, // Set the client (caller) as the initiator of the session
            node: node, // Set the specified node as the session's node
            startTime: block.timestamp, // Set the session's start time as the current timestamp
            endTime: 0, // Initialize the end time as 0, to be set later
            active: true, // Set the session status as active
            lastActiveTime: block.timestamp, // Initialize the last active time as the current timestamp
            deposit: msg.value, // Store the deposit amount sent by the client
            pricingType: pricingType, // Store the pricing type (either ByGB or ByHour)
            uploadBytes: 0, // Initialize upload bytes as 0, to be updated later
            downloadBytes: 0, // Initialize download bytes as 0, to be updated later
            duration: 0 // Initialize the session duration as 0, to be updated later
        });

         // Emit the SessionCreated event
        emit SessionCreated(sessionId, msg.sender, node, msg.value, pricingType);

        // Return the unique sessionId to the client so they can reference it for future operations
        return sessionId; // The client can now interact with the session using this sessionId
    }

    // Function to update the data usage for a session, requires the client's signature
    function updateUsage(
        bytes32 sessionId,
        uint256 downloadBytes,
        uint256 uploadBytes,
        uint256 duration,
        bytes memory clientSignature
    ) public {
        // Retrieve the session details using the sessionId
        Session storage session = sessions[sessionId];

        // Ensure that the caller is the node associated with the session
        require(session.node == msg.sender, "Unauthorized Node"); // Ensure the Node is authorized to update this session

        // Ensure the session is still active before allowing updates
        require(session.active, "Session not active"); // Ensure the session is active

        // Create the struct containing the update data
        UpdateUsageData memory data = UpdateUsageData({
            sessionId: sessionId,
            downloadBytes: downloadBytes,
            uploadBytes: uploadBytes,
            duration: duration
        });

        // Create the EIP-712 typed data hash
        bytes32 structHash = _hashTypedDataV4(_hashUpdateUsageData(data));
         // Recover the address of the signer from the provided signature
        address signer = ECDSA.recover(structHash, clientSignature);
        require(signer == session.client, "Invalid client signature");

        // Update the session with the new data usage values
        session.downloadBytes = downloadBytes; // Update the total download bytes used
        session.uploadBytes = uploadBytes; // Update the total upload bytes used
        session.duration = duration; // Update the duration of the session
        session.lastActiveTime = block.timestamp; // Update last activity time to the current timestamp

        // Also update the node's last active time (tracks when the node last interacted)
        nodes[session.node].lastActiveTime = block.timestamp; // Update node's last activity time

        // Mark the message hash as used to prevent reuse
        usedMessageHashes[structHash] = true; // Mark the messageHash as used

        // Emit the event for data usage update
        emit UsageUpdated(sessionId, downloadBytes, uploadBytes, duration, block.timestamp);
    }

    // Function to end a session and settle the payment
    function endSession(bytes32 sessionId) public {
        // Retrieve the session details using the sessionId
        Session storage session = sessions[sessionId];

        // Ensure that the caller is the node associated with the session
        require(session.node == msg.sender, "Unauthorized Node");

        // Ensure that the session is still active (not already ended)
        require(session.active, "Session already ended");

        // Mark the session as ended and set the end time
        session.endTime = block.timestamp;
        session.active = false;

        uint256 totalCost; // Total cost of the session
        uint256 refundAmount = 0; // Amount to be refunded (if any)
        uint256 paymentAmount = 0; // Amount to be paid (if any)

        // If the pricing model is based on GB (data usage)
        if (session.pricingType == PricingType.ByGB) {
            // Calculate the total number of bytes used in the session (upload + download)
            uint256 totalBytes = session.downloadBytes + session.uploadBytes;

            // Calculate the price per byte (since price is in per GB)
            uint256 bytePrice = nodes[session.node].pricePerGB / 1e9; // 1e9 is used to convert GB to bytes

            // Calculate the total cost based on the total bytes used
            totalCost = bytePrice * totalBytes;
        }
        // If the pricing model is based on Hour (time spent)
        else if (session.pricingType == PricingType.ByHour) {
            // Calculate the price per second (price per hour divided by 3600 seconds)
            uint256 secondPrice = nodes[session.node].pricePerHour / 3600;

            // Calculate the total cost based on the session's duration
            totalCost = session.duration * secondPrice;
        }

        // If the total cost exceeds the deposit, set paymentAmount to the deposit
        if (totalCost >= session.deposit) {
            paymentAmount = session.deposit;
        }
        // Otherwise, set paymentAmount to totalCost and calculate the refund amount
        else {
            paymentAmount = totalCost;
            refundAmount = session.deposit - totalCost; // Refund the excess deposit
        }

        // If there is an amount to be paid to the node
        if (paymentAmount > 0) {
            // Calculate the protocol's commission (percentage of the payment amount)
            uint256 protocolCommission = (paymentAmount *
                protocolCommissionPercentage) / 1000000;

            // Calculate the amount to be sent to the node after subtracting the commission
            uint256 nodePayment = paymentAmount - protocolCommission;

            // Transfer the commission to the protocol wallet
            payable(protocolWallet).transfer(protocolCommission);

            // Transfer the remaining payment to the node
            payable(session.node).transfer(nodePayment);
        }

        // If there is a refund amount (if the deposit was greater than the total cost)
        if (refundAmount > 0) {
            // Refund the excess amount back to the client
            payable(session.client).transfer(refundAmount);
        }
        // Emit event with the session ending details
        emit SessionEnded(sessionId, totalCost, refundAmount, (paymentAmount * protocolCommissionPercentage) / 1000000, paymentAmount - (paymentAmount * protocolCommissionPercentage) / 1000000);
    }

    // Function for the client to request a refund if the session has been inactive for too long
    function refundSession(bytes32 sessionId) public {
        Session storage session = sessions[sessionId];
        require(
            session.client == msg.sender,
            "Only the client can request a refund"
        );
        require(session.active, "Session already ended");
        require(
            block.timestamp > session.lastActiveTime + inactivityTimeout,
            "Session is still active"
        );

        uint256 refundAmount = session.deposit; // Refund based on the deposit stored in the session
        session.active = false;

        payable(msg.sender).transfer(refundAmount);

        emit SessionRefunded(sessionId, refundAmount);
    }

    // Hash the struct data (to match the EIP-712 format)
    function _hashUpdateUsageData(
        UpdateUsageData memory data
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    keccak256(
                        "UpdateUsageData(bytes32 sessionId,uint256 downloadBytes,uint256 uploadBytes,uint256 duration)"
                    ),
                    data.sessionId,
                    data.downloadBytes,
                    data.uploadBytes,
                    data.duration
                )
            );
    }

    // Override _domainSeparatorV4 to use the custom domain
    function _domainSeparatorV4() internal view override returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    keccak256(
                        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                    ),
                    keccak256(bytes(SIGNING_DOMAIN)),
                    keccak256(bytes(SIGNATURE_VERSION)),
                    block.chainid,
                    address(this)
                )
            );
    }
}

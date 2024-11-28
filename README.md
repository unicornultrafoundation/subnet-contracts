### **Subnet Contracts**

---

## **Overview**

The Subnet Contracts repository contains smart contracts for managing decentralized subnet resources, incentivizing uptime, and integrating NFT-based ownership. The primary contract, `SubnetRegistry`, allows subnet operators to register their resources, claim uptime-based rewards, and manage their participation in the subnet ecosystem.

---

## **Features**

- **Subnet Registration**:
  - Subnets can register by locking an NFT as collateral.
  - Each subnet is associated with metadata and a peer address (e.g., libp2p PeerID).

- **Uptime Tracking**:
  - Subnets earn rewards based on their uptime.
  - A Merkle Tree is used for efficient, scalable uptime validation.

- **Reward Distribution**:
  - Subnet owners can claim rewards in native tokens based on their uptime.

- **Dynamic Configuration**:
  - The reward rate (`rewardPerSecond`) can be updated by the contract owner.
  - Supports NFT-based ownership verification.

---

## **Contract Overview**

### **SubnetRegistry**

This is the main contract for managing subnets. It includes the following functionalities:

1. **Register Subnet**:
   - Locks an NFT to register a subnet.
   - Associates the subnet with metadata and a peer address.

2. **Deregister Subnet**:
   - Unlocks the NFT and removes the subnet from the registry.

3. **Claim Rewards**:
   - Subnet owners can claim rewards based on their validated uptime using a Merkle Proof.

4. **Update Configuration**:
   - The contract owner can update the `rewardPerSecond` and the Merkle Root for uptime validation.

---

## **Deployment**

### **Prerequisites**
- Install [Hardhat](https://hardhat.org/) and [Node.js](https://nodejs.org/).
- Deploy an NFT contract compatible with the **ERC721** standard.

### **Steps to Deploy**

1. **Clone the Repository**:
   ```bash
   git clone https://github.com/unicornultrafoundation/subnet-contracts.git
   cd subnet-contracts
   ```

2. **Install Dependencies**:
   ```bash
   npm install
   ```

3. **Compile the Contracts**:
   ```bash
   npx hardhat compile
   ```

4. **Deploy the Contracts**:
   - Use the provided Hardhat Ignition module for deployment:
     ```bash
     npx hardhat ignition deploy subnetRegistryModule
     ```

   - Alternatively, deploy via a script:
     ```bash
     npx hardhat run scripts/deploySubnetRegistry.js --network <network_name>
     ```

5. **Post-Deployment Configuration**:
   - Update the `rewardPerSecond` (optional):
     ```javascript
     const subnetRegistry = await ethers.getContract("SubnetRegistry");
     await subnetRegistry.updateRewardPerSecond(ethers.utils.parseEther("0.01")); // Example: 0.01 native token per second
     ```

---

## **Usage**

### **Registering a Subnet**
To register a subnet, the caller must:
1. Own an NFT from the specified contract.
2. Provide metadata and a peer address.

#### Example:
```javascript
await subnetRegistry.registerSubnet(
  1, // NFT ID
  "12D3KooW...", // Peer address
  "Metadata for subnet" // Subnet metadata
);
```

### **Claiming Rewards**
Rewards are claimed by providing a valid Merkle Proof:
```javascript
await subnetRegistry.claimReward(
  1, // Subnet ID
  "0xOwnerAddress...", // Owner address
  3600, // Total uptime
  merkleProof // Valid Merkle Proof
);
```

---

## **Testing**

1. **Run Tests**:
   ```bash
   npx hardhat test
   ```

2. **Coverage**:
   ```bash
   npx hardhat coverage
   ```

---

## **Configuration**

- **Reward Rate**:
  - The `rewardPerSecond` determines the token reward for each second of uptime.
  - Can be updated by the contract owner:
    ```javascript
    await subnetRegistry.updateRewardPerSecond(ethers.utils.parseEther("0.01"));
    ```

- **Merkle Root**:
  - The `merkleRoot` is updated periodically to validate uptime claims:
    ```javascript
    await subnetRegistry.updateMerkleRoot("0xNewMerkleRoot...");
    ```

---

## **Events**

1. **SubnetRegistered**:
   - Emitted when a subnet is registered.
   - Includes subnet ID, owner, peer address, and metadata.

2. **SubnetDeregistered**:
   - Emitted when a subnet is deregistered.
   - Includes subnet ID, owner, and total uptime.

3. **RewardClaimed**:
   - Emitted when rewards are claimed.
   - Includes subnet ID, owner, peer address, and reward amount.

4. **RewardPerSecondUpdated**:
   - Emitted when the reward rate is updated.

---

## **Security Considerations**

1. **Access Control**:
   - Only the contract owner can update the `rewardPerSecond` and `merkleRoot`.

2. **Reentrancy Protection**:
   - Ensure the `claimReward` function follows the **checks-effects-interactions** pattern.

3. **Sufficient Funding**:
   - Ensure the contract is funded with sufficient native tokens to cover rewards.

---

## **Roadmap**

- Support for dynamic peer address updates.
- Integration with decentralized uptime oracles.
- Token-based staking and slashing mechanisms for subnet validation.

---

## **Contributing**

Contributions are welcome! Please follow the [guidelines](CONTRIBUTING.md) for submitting pull requests and reporting issues.

---

## **License**

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
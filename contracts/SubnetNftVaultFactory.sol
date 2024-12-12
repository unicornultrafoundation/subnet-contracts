// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./SubnetNftVault.sol";

contract SubnetNftVaultFactory {
    // Event emitted whenever a new vault is created
    event VaultCreated(address indexed nftContract, address vaultAddress);

    // Array to store all deployed vaults
    address[] public allVaults;

    /// @notice Computes the salt based on name, symbol, and nftContract
    /// @param name_ The name of the ERC20 token
    /// @param symbol_ The symbol of the ERC20 token
    /// @param nftContract_ The address of the NFT contract allowed in the vault
    /// @return The computed salt
    function computeSalt(
        string memory name_,
        string memory symbol_,
        address nftContract_
    ) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(name_, symbol_, nftContract_));
    }

    /// @notice Computes the address of a Vault before deployment
    /// @param name_ The name of the ERC20 token
    /// @param symbol_ The symbol of the ERC20 token
    /// @param nftContract_ The address of the NFT contract allowed in the vault
    /// @return The precomputed address of the Vault
    function computeVaultAddress(
        string memory name_,
        string memory symbol_,
        address nftContract_
    ) public view returns (address) {
        bytes32 salt = computeSalt(name_, symbol_, nftContract_);
        bytes memory bytecode = getVaultBytecode(name_, symbol_, nftContract_);
        return
            address(
                uint160( // Convert the hash to an address
                    uint256(
                        keccak256( // Hash the data
                            abi.encodePacked(
                                bytes1(0xff), // Prefix for CREATE2
                                address(this), // Deployer address (this factory)
                                salt, // Salt value
                                keccak256(bytecode) // Bytecode hash
                            )
                        )
                    )
                )
            );
    }

    /// @notice Deploys a new NFT Vault using CREATE2 and a computed salt
    /// @param name_ The name of the ERC20 token
    /// @param symbol_ The symbol of the ERC20 token
    /// @param nftContract_ The address of the NFT contract allowed in the vault
    /// @return The address of the newly deployed Vault
    function createVault(
        string memory name_,
        string memory symbol_,
        address nftContract_
    ) external returns (address) {
        // Compute the salt
        bytes32 salt = computeSalt(name_, symbol_, nftContract_);

        // Compute the bytecode of the Vault
        bytes memory bytecode = getVaultBytecode(name_, symbol_, nftContract_);

        // Deploy the vault using CREATE2
        address vaultAddress;
        assembly {
            vaultAddress := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
            if iszero(vaultAddress) {
                revert(0, 0)
            }
        }

        // Store the address of the new vault
        allVaults.push(vaultAddress);

        // Emit the VaultCreated event
        emit VaultCreated(nftContract_, vaultAddress);

        return vaultAddress;
    }

    /// @notice Returns the number of deployed vaults
    /// @return The total number of deployed vaults
    function getVaultCount() external view returns (uint256) {
        return allVaults.length;
    }

    /// @notice Returns the address of a vault at a given index
    /// @param index The index of the vault in the array
    /// @return The address of the vault
    function getVault(uint256 index) external view returns (address) {
        require(index < allVaults.length, "Invalid index");
        return allVaults[index];
    }

    /// @notice Constructs the bytecode for the SubnetNftVault contract
    /// @param name_ The name of the ERC20 token
    /// @param symbol_ The symbol of the ERC20 token
    /// @param nftContract_ The address of the NFT contract allowed in the vault
    /// @return The bytecode of the Vault contract
    function getVaultBytecode(
        string memory name_,
        string memory symbol_,
        address nftContract_
    ) public pure returns (bytes memory) {
        return
            abi.encodePacked(
                type(SubnetNftVault).creationCode,
                abi.encode(name_, symbol_, nftContract_)
            );
    }
}
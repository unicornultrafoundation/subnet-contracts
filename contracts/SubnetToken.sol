// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title SubnetToken
 * @dev ERC20 token with symbol SCU, allowing the owner to mint tokens.
 */
contract SubnetToken is ERC20, Ownable {
    constructor(address initialOwner) ERC20("SubnetToken", "SCU") Ownable(initialOwner) {}

    /**
     * @dev Mints new tokens.
     * @param to The address to mint tokens to.
     * @param amount The amount of tokens to mint.
     */
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./ISubnetProvider.sol";

/**
 * @title BaseMarketplace
 * @dev Base contract with common functionality for all marketplace types
 */
abstract contract BaseMarketplace is Initializable, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    enum OrderStatus { Open, Matched, Closed }

    // Common order fields
    struct BaseOrder {
        uint256 machineType;
        address owner;
        OrderStatus status;
        uint256 createdAt;
        uint256 duration;
        address paymentToken;
        uint256 cpuCores; // mCPU (milliCPU): 1000 mCPU = 1 CPU
        uint256 gpuCores;
        uint256 memoryMB;
        uint256 diskGB;
        uint256 region;
        string specs;
        uint256 startAt;
        uint256 expiredAt;
        uint256 lastPaidAt;
    }

    uint256 public orderGracePeriod;
    address public paymentToken;
    address public subnetProviderContract;

    // Platform fee variables
    uint256 public platformFeePercentage;
    address public platformWallet;
    uint256 public totalAccumulatedFees;

    // Events
    event OrderGracePeriodUpdated(uint256 oldPeriod, uint256 newPeriod);
    event PlatformFeeUpdated(uint256 oldFee, uint256 newFee);
    event PlatformWalletUpdated(address oldWallet, address newWallet);
    event FeesWithdrawn(address wallet, uint256 amount);

    function __BaseMarketplace_init(
        address owner,
        address _paymentToken,
        address _subnetProviderContract
    ) internal onlyInitializing {
        __Ownable_init(owner);
        paymentToken = _paymentToken;
        subnetProviderContract = _subnetProviderContract;
        orderGracePeriod = 1 days;
        platformFeePercentage = 100; // Default 1%
        platformWallet = owner;
    }

    function setOrderGracePeriod(uint256 newGracePeriod) external onlyOwner {
        require(newGracePeriod > 0, "Grace period must be positive");
        uint256 oldPeriod = orderGracePeriod;
        orderGracePeriod = newGracePeriod;
        emit OrderGracePeriodUpdated(oldPeriod, newGracePeriod);
    }

    function setPaymentConfig(address _paymentToken) external onlyOwner {
        require(_paymentToken != address(0), "Invalid token");
        paymentToken = _paymentToken;
    }

    function setSubnetProviderContract(address _subnetProviderContract) external onlyOwner {
        require(_subnetProviderContract != address(0), "Invalid provider contract");
        subnetProviderContract = _subnetProviderContract;
    }

    function setPlatformFee(uint256 newFeePercentage) external onlyOwner {
        require(newFeePercentage <= 2000, "Fee cannot exceed 20%");
        uint256 oldFee = platformFeePercentage;
        platformFeePercentage = newFeePercentage;
        emit PlatformFeeUpdated(oldFee, newFeePercentage);
    }

    function setPlatformWallet(address newWallet) external onlyOwner {
        require(newWallet != address(0), "Cannot set zero address");
        address oldWallet = platformWallet;
        platformWallet = newWallet;
        emit PlatformWalletUpdated(oldWallet, newWallet);
    }

    function withdrawFees(uint256 amount) external onlyOwner {
        require(amount <= totalAccumulatedFees, "Insufficient fee balance");
        totalAccumulatedFees -= amount;
        IERC20(paymentToken).safeTransfer(platformWallet, amount);
        emit FeesWithdrawn(platformWallet, amount);
    }

    function calculateFee(uint256 amount) internal view returns (uint256) {
        return (amount * platformFeePercentage) / 10000;
    }
}


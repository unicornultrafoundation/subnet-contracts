// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./SubnetStakingPool.sol";

contract SubnetStakingPoolFactory {
    event PoolCreated(address indexed stakingToken, address indexed rewardToken, address poolAddress);

    // Array to store all deployed pools
    address[] public allPools;

    /// @notice Deploys a new staking pool
    /// @param stakingToken The address of the ERC20 token to be staked
    /// @param rewardRatePerSecond Reward rate per second for the pool
    /// @param startTime The start time of the staking pool
    /// @param endTime The end time of the staking pool
    /// @return The address of the newly deployed staking pool
    function createPool(
        IERC20 stakingToken,
        IERC20 rewardToken,
        uint256 rewardRatePerSecond,
        uint256 startTime,
        uint256 endTime
    ) external returns (address) {
        require(address(stakingToken) != address(0), "Invalid staking token address");
        require(address(rewardToken) != address(0), "Invalid reward token address");
        require(endTime > startTime, "End time must be after start time");

        bytes32 salt = keccak256(abi.encodePacked(address(stakingToken), address(rewardToken), rewardRatePerSecond, startTime, endTime));
        bytes memory bytecode = abi.encodePacked(
            type(SubnetStakingPool).creationCode,
            abi.encode(stakingToken, rewardToken, rewardRatePerSecond, startTime, endTime)
        );

        address poolAddress;
        assembly {
            poolAddress := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
            if iszero(poolAddress) {
                revert(0, 0)
            }
        }

        allPools.push(poolAddress);

        emit PoolCreated(address(stakingToken), address(rewardToken), poolAddress);
        return address(poolAddress);
    }

    /// @notice Returns the number of deployed pools
    /// @return The total number of deployed pools
    function getPoolCount() external view returns (uint256) {
        return allPools.length;
    }

    /// @notice Returns the address of a pool at a given index
    /// @param index The index of the pool in the array
    /// @return The address of the pool
    function getPool(uint256 index) external view returns (address) {
        require(index < allPools.length, "Invalid index");
        return allPools[index];
    }
}

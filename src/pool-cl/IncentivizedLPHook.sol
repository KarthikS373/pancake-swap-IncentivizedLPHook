// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {CLBaseHook} from "./CLBaseHook.sol";

import {ICLPoolManager} from "pancake-v4-core/src/pool-cl/interfaces/ICLPoolManager.sol";

import {BalanceDelta} from "pancake-v4-core/src/types/BalanceDelta.sol";
import {LPFeeLibrary} from "pancake-v4-core/src/libraries/LPFeeLibrary.sol";
import {PoolId, PoolIdLibrary} from "pancake-v4-core/src/types/PoolId.sol";
import {PoolKey} from "pancake-v4-core/src/types/PoolKey.sol";

/**
 * @title IncentivizedLPHook
 * @dev A PancakeSwap v4 hook to incentivize Liquidity Providers (LPs) based on multiple factors.
 */
contract IncentivizedLPHook is CLBaseHook {
    using PoolIdLibrary for PoolKey;

    // Struct to store LP information
    struct LPInfo {
        uint256 totalLiquidity;
        uint256 liquidityStartTime;
        uint256 consecutiveDays;
        uint256 lockupEndTime;
        uint256 crossPlatformContributions;
    }

    // Mapping from LP address to LPInfo
    mapping(address => LPInfo) public lpInfos;

    // Mapping from PoolId to accumulated rewards
    mapping(PoolId => uint256) public poolRewards;

    // Event declarations
    event LiquidityAdded(address indexed lp, uint256 amount);
    event LiquidityRemoved(address indexed lp, uint256 amount);
    event RewardsCalculated(address indexed lp, uint256 reward);
    event LiquidityLocked(address indexed lp, uint256 duration);

    /**
     * @param _poolManager Address of the pool manager
     */
    constructor(ICLPoolManager _poolManager) CLBaseHook(_poolManager) {}

    /**
     * @dev Registers the required callbacks.
     */
    function getHooksRegistrationBitmap()
        external
        pure
        override
        returns (uint16)
    {
        return
            _hooksRegistrationBitmapFrom(
                Permissions({
                    beforeInitialize: false,
                    afterInitialize: true,
                    beforeAddLiquidity: true,
                    afterAddLiquidity: true,
                    beforeRemoveLiquidity: true,
                    afterRemoveLiquidity: true,
                    beforeSwap: false,
                    afterSwap: false,
                    beforeDonate: false,
                    afterDonate: false,
                    beforeSwapReturnsDelta: false,
                    afterSwapReturnsDelta: false,
                    afterAddLiquidityReturnsDelta: false,
                    afterRemoveLiquidityReturnsDelta: false
                })
            );
    }

    /**
     * @dev Callback after pool initialization.
     */
    function afterInitialize(
        address,
        PoolKey calldata key,
        uint160,
        int24,
        bytes calldata hookData
    ) external override poolManagerOnly returns (bytes4) {
        // Initialize pool-specific rewards if necessary
        uint24 initialReward = abi.decode(hookData, (uint24));
        poolRewards[key.toId()] = initialReward;
        return this.afterInitialize.selector;
    }

    /**
     * @dev Callback before adding liquidity.
     */
    function beforeAddLiquidity(
        address sender,
        PoolKey calldata key,
        ICLPoolManager.ModifyLiquidityParams calldata params,
        bytes calldata
    ) external override poolManagerOnly returns (bytes4) {
        LPInfo storage info = lpInfos[sender];

        // If this is the first time adding liquidity, set the start time
        if (info.totalLiquidity == 0) {
            info.liquidityStartTime = block.timestamp;
        }

        // Update total liquidity
        require(params.liquidityDelta > 0, "Liquidity delta must be positive");
        info.totalLiquidity += uint256(params.liquidityDelta);

        emit LiquidityAdded(sender, uint256(params.liquidityDelta));

        return this.beforeAddLiquidity.selector;
    }

    /**
     * @dev Callback after adding liquidity.
     */
    function afterAddLiquidity(
        address sender,
        PoolKey calldata key,
        ICLPoolManager.ModifyLiquidityParams calldata params,
        BalanceDelta delta,
        bytes calldata data
    ) external override poolManagerOnly returns (bytes4, BalanceDelta) {
        // Calculate rewards based on liquidity addition
        _calculateRewards(sender, key);

        // Return the selector and the original delta
        return (this.afterAddLiquidity.selector, delta);
    }

    /**
     * @dev Callback before removing liquidity.
     */
    function beforeRemoveLiquidity(
        address sender,
        PoolKey calldata key,
        ICLPoolManager.ModifyLiquidityParams calldata params,
        bytes calldata
    ) external override poolManagerOnly returns (bytes4) {
        LPInfo storage info = lpInfos[sender];

        // Update total liquidity
        require(params.liquidityDelta > 0, "Liquidity delta must be positive");
        require(
            info.totalLiquidity >= uint256(params.liquidityDelta),
            "Insufficient liquidity"
        );
        info.totalLiquidity -= uint256(params.liquidityDelta);

        // Reset consecutive days if liquidity is fully removed
        if (info.totalLiquidity == 0) {
            info.consecutiveDays = 0;
        }

        emit LiquidityRemoved(sender, uint256(params.liquidityDelta));

        return this.beforeRemoveLiquidity.selector;
    }

    /**
     * @dev Callback after removing liquidity.
     */
    function afterRemoveLiquidity(
        address sender,
        PoolKey calldata key,
        ICLPoolManager.ModifyLiquidityParams calldata params,
        BalanceDelta delta,
        bytes calldata
    ) external override poolManagerOnly returns (bytes4, BalanceDelta) {
        // Calculate rewards based on liquidity removal
        _calculateRewards(sender, key);

        return (this.afterRemoveLiquidity.selector, delta);
    }

    /**
     * @dev Allows LPs to lock up their liquidity for a specified duration.
     * @param duration Duration in seconds for which liquidity is locked.
     */
    function lockupLiquidity(address lp, uint256 duration) external {
        require(duration > 0, "Duration must be positive");
        LPInfo storage info = lpInfos[lp];
        info.lockupEndTime = block.timestamp + duration;

        emit LiquidityLocked(lp, duration);
    }

    /**
     * @dev Internal function to calculate rewards based on various factors.
     * @param lp Address of the liquidity provider.
     * @param key PoolKey associated with the liquidity.
     */
    function _calculateRewards(address lp, PoolKey calldata key) internal {
        LPInfo storage info = lpInfos[lp];
        uint256 currentTime = block.timestamp;

        // Time-Based Rewards
        // Example: 1 token per second
        uint256 duration = currentTime - info.liquidityStartTime;
        uint256 timeReward = duration * 1e18;

        // Amount-Based Rewards
        // Example: 1 token per 1,000,000 liquidity
        uint256 amountReward = info.totalLiquidity * 1e12;

        // Milestone-Based Rewards
        // Example: 10 tokens per consecutive day
        if (duration >= 1 days * (info.consecutiveDays + 1)) {
            info.consecutiveDays += 1;
        }
        uint256 milestoneReward = info.consecutiveDays * 10e18;

        // Cross-Platform Rewards
        // Example: 5 tokens per cross-platform contribution
        uint256 crossReward = info.crossPlatformContributions * 5e18;

        // Lockup Boosted Rewards
        uint256 boostedReward = 0;
        if (currentTime < info.lockupEndTime) {
            uint256 remainingLockup = info.lockupEndTime - currentTime;
            uint256 lockupBoost = remainingLockup / 1 days;
            boostedReward =
                (timeReward + amountReward + milestoneReward + crossReward) *
                lockupBoost;
        } else {
            boostedReward =
                timeReward +
                amountReward +
                milestoneReward +
                crossReward;
        }

        // Update pool rewards
        poolRewards[key.toId()] += boostedReward;

        emit RewardsCalculated(lp, boostedReward);

        // Reset start time
        info.liquidityStartTime = currentTime;
    }

    /**
     * @dev Function to increment cross-platform contributions.
     * @param lp Address of the liquidity provider.
     */
    function incrementCrossPlatformContributions(address lp) external {
        // TODO: Implement cross-platform tracking
        // This function can be called by other contracts or mechanisms tracking cross-platform activities
        lpInfos[lp].crossPlatformContributions += 1;
    }
}

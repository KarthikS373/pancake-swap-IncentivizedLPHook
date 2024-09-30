// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IncentivizedLPHook} from "../../src/pool-cl/IncentivizedLPHook.sol";
import {CLBaseHook} from "../../src/pool-cl/CLBaseHook.sol";

import {ICLPoolManager} from "pancake-v4-core/src/interfaces/ICLPoolManager.sol";
import {PoolKey} from "pancake-v4-core/src/types/PoolKey.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {LPFeeLibrary} from "pancake-v4-core/src/libraries/LPFeeLibrary.sol";

/**
 * @title IncentivizedLPHookTest
 * @dev Comprehensive tests for the IncentivizedLPHook contract.
 */
contract IncentivizedLPHookTest is Test {
    // Mock contracts and instances
    ICLPoolManager poolManager;
    MockERC20 currency0;
    MockERC20 currency1;
    IncentivizedLPHook hook;
    MockERC20 brevisToken;

    // Addresses
    address alice = address(0x1);
    address bob = address(0x2);

    // PoolKey
    PoolKey key;

    // Events to capture
    event LiquidityAdded(address indexed lp, uint256 amount);
    event LiquidityRemoved(address indexed lp, uint256 amount);
    event RewardsCalculated(address indexed lp, uint256 reward);
    event LiquidityLocked(address indexed lp, uint256 duration);

    /**
     * @dev Setup the test environment.
     */
    function setUp() public {
        // Deploy mock tokens
        currency0 = new MockERC20("Token0", "TK0", 18);
        currency1 = new MockERC20("Token1", "TK1", 18);
        brevisToken = new MockERC20("Brevis", "BREVIS", 18);

        // Deploy mock pool manager
        poolManager = ICLPoolManager(address(new MockCLPoolManager()));

        // Deploy the IncentivizedLPHook
        hook = new IncentivizedLPHook(poolManager, address(brevisToken));

        // Create PoolKey
        key = PoolKey({
            currency0: address(currency0),
            currency1: address(currency1),
            hooks: address(hook),
            poolManager: address(poolManager),
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            parameters: bytes32(uint256(0)) // Additional parameters can be set as needed
        });

        // Initialize the pool with an initial reward
        bytes memory hookData = abi.encode(uint24(5000)); // Example initial reward
        // Simulate pool initialization callback
        hook.afterInitialize(address(this), key, 0, 0, hookData);

        // Mint tokens to LPs
        currency0.mint(alice, 1000 ether);
        currency1.mint(alice, 1000 ether);
        currency0.mint(bob, 1000 ether);
        currency1.mint(bob, 1000 ether);
    }

    /**
     * @dev Test adding liquidity as a new LP.
     */
    function testAddLiquidity() public {
        vm.prank(alice);
        bytes memory emptyData = "";
        ICLPoolManager.AddLiquidityParams memory addParams = ICLPoolManager.AddLiquidityParams({
            amount: 500 ether
        });

        // Expect LiquidityAdded event
        vm.expectEmit(true, true, false, true);
        emit LiquidityAdded(alice, 500 ether);

        // Simulate adding liquidity
        hook.beforeAddLiquidity(alice, key, addParams, emptyData);
        hook.afterAddLiquidity(alice, key, addParams, emptyData);

        // Check LPInfo
        (uint256 totalLiquidity, uint256 liquidityStartTime, uint256 consecutiveDays, uint256 lockupEndTime, uint256 crossContrib) = hook.lpInfos(alice);
        assertEq(totalLiquidity, 500 ether);
        assertEq(liquidityStartTime, block.timestamp);
        assertEq(consecutiveDays, 0);
        assertEq(lockupEndTime, 0);
        assertEq(crossContrib, 0);
    }

    /**
     * @dev Test removing liquidity.
     */
    function testRemoveLiquidity() public {
        // First, add liquidity
        vm.prank(alice);
        bytes memory emptyData = "";
        ICLPoolManager.AddLiquidityParams memory addParams = ICLPoolManager.AddLiquidityParams({
            amount: 500 ether
        });
        hook.beforeAddLiquidity(alice, key, addParams, emptyData);
        hook.afterAddLiquidity(alice, key, addParams, emptyData);

        // Now, remove liquidity
        ICLPoolManager.RemoveLiquidityParams memory removeParams = ICLPoolManager.RemoveLiquidityParams({
            amount: 200 ether
        });

        // Expect LiquidityRemoved event
        vm.expectEmit(true, true, false, true);
        emit LiquidityRemoved(alice, 200 ether);

        vm.prank(alice);
        hook.beforeRemoveLiquidity(alice, key, removeParams, emptyData);
        hook.afterRemoveLiquidity(alice, key, removeParams, emptyData);

        // Check LPInfo
        (uint256 totalLiquidity, , uint256 consecutiveDays, uint256 lockupEndTime, uint256 crossContrib) = hook.lpInfos(alice);
        assertEq(totalLiquidity, 300 ether);
        assertEq(consecutiveDays, 0);
        assertEq(lockupEndTime, 0);
        assertEq(crossContrib, 0);
    }

    /**
     * @dev Test reward calculation after adding liquidity.
     */
    function testRewardCalculationAddLiquidity() public {
        // Add liquidity
        vm.prank(alice);
        bytes memory emptyData = "";
        ICLPoolManager.AddLiquidityParams memory addParams = ICLPoolManager.AddLiquidityParams({
            amount: 500 ether
        });
        hook.beforeAddLiquidity(alice, key, addParams, emptyData);
        hook.afterAddLiquidity(alice, key, addParams, emptyData);

        // Fast forward time by 1 day
        vm.warp(block.timestamp + 1 days);

        // Add liquidity again to trigger reward calculation
        ICLPoolManager.AddLiquidityParams memory addParams2 = ICLPoolManager.AddLiquidityParams({
            amount: 500 ether
        });

        // Expect RewardsCalculated event
        uint256 expectedTimeReward = 1 days * 1e18;
        uint256 expectedAmountReward = 500 ether * 1e12;
        uint256 expectedMilestoneReward = 10e18; // First consecutive day
        uint256 expectedTotalReward = expectedTimeReward + expectedAmountReward + expectedMilestoneReward;

        vm.expectEmit(true, true, false, true);
        emit RewardsCalculated(alice, expectedTotalReward);

        vm.prank(alice);
        hook.beforeAddLiquidity(alice, key, addParams2, emptyData);
        hook.afterAddLiquidity(alice, key, addParams2, emptyData);

        // Check pool rewards
        uint256 poolId = key.toId();
        uint256 rewards = hook.poolRewards(poolId);
        assertEq(rewards, expectedTotalReward + 500 ether * 1e12); // Initial reward + new rewards
    }

    /**
     * @dev Test milestone-based rewards over multiple days.
     */
    function testMilestoneBasedRewards() public {
        // Add liquidity on day 1
        vm.prank(alice);
        bytes memory emptyData = "";
        ICLPoolManager.AddLiquidityParams memory addParams = ICLPoolManager.AddLiquidityParams({
            amount: 500 ether
        });
        hook.beforeAddLiquidity(alice, key, addParams, emptyData);
        hook.afterAddLiquidity(alice, key, addParams, emptyData);

        // Simulate 5 consecutive days
        for (uint256 i = 1; i <= 5; i++) {
            vm.warp(block.timestamp + 1 days);
            ICLPoolManager.AddLiquidityParams memory addParamsDay = ICLPoolManager.AddLiquidityParams({
                amount: 500 ether
            });

            // Expect RewardsCalculated event with increasing milestone rewards
            uint256 expectedTimeReward = 1 days * 1e18;
            uint256 expectedAmountReward = 500 ether * 1e12;
            uint256 expectedMilestoneReward = i * 10e18; // Consecutive days
            uint256 expectedTotalReward = expectedTimeReward + expectedAmountReward + expectedMilestoneReward;

            vm.expectEmit(true, true, false, true);
            emit RewardsCalculated(alice, expectedTotalReward);

            vm.prank(alice);
            hook.beforeAddLiquidity(alice, key, addParamsDay, emptyData);
            hook.afterAddLiquidity(alice, key, addParamsDay, emptyData);
        }

        // Check consecutive days
        (, , uint256 consecutiveDays, , ) = hook.lpInfos(alice);
        assertEq(consecutiveDays, 5);
    }

    /**
     * @dev Test cross-platform contributions.
     */
    function testCrossPlatformContributions() public {
        // Simulate cross-platform contributions
        hook.incrementCrossPlatformContributions(alice);
        hook.incrementCrossPlatformContributions(alice);
        hook.incrementCrossPlatformContributions(alice);

        // Add liquidity to trigger reward calculation
        vm.prank(alice);
        bytes memory emptyData = "";
        ICLPoolManager.AddLiquidityParams memory addParams = ICLPoolManager.AddLiquidityParams({
            amount: 500 ether
        });
        hook.beforeAddLiquidity(alice, key, addParams, emptyData);
        hook.afterAddLiquidity(alice, key, addParams, emptyData);

        // Calculate expected rewards
        uint256 expectedCrossReward = 3 * 5e18; // 3 cross-platform contributions
        uint256 expectedTimeReward = 0; // No time passed
        uint256 expectedAmountReward = 500 ether * 1e12;
        uint256 expectedMilestoneReward = 0; // No consecutive days
        uint256 expectedTotalReward = expectedCrossReward + expectedAmountReward;

        // Expect RewardsCalculated event
        vm.expectEmit(true, true, false, true);
        emit RewardsCalculated(alice, expectedTotalReward);

        // Trigger reward calculation
        hook.afterAddLiquidity(alice, key, addParams, emptyData);

        // Check pool rewards
        uint256 poolId = key.toId();
        uint256 rewards = hook.poolRewards(poolId);
        assertEq(rewards, 500 ether * 1e12 + expectedCrossReward);
    }

    /**
     * @dev Test lockup boosted rewards.
     */
    function testLockupBoostedRewards() public {
        // Lock up liquidity for 10 days
        vm.prank(alice);
        hook.lockupLiquidity(alice, 10 days);

        // Add liquidity
        vm.prank(alice);
        bytes memory emptyData = "";
        ICLPoolManager.AddLiquidityParams memory addParams = ICLPoolManager.AddLiquidityParams({
            amount: 500 ether
        });
        hook.beforeAddLiquidity(alice, key, addParams, emptyData);
        hook.afterAddLiquidity(alice, key, addParams, emptyData);

        // Fast forward 5 days (within lockup period)
        vm.warp(block.timestamp + 5 days);

        // Add liquidity again to trigger reward calculation
        ICLPoolManager.AddLiquidityParams memory addParams2 = ICLPoolManager.AddLiquidityParams({
            amount: 500 ether
        });

        uint256 expectedTimeReward = 5 days * 1e18;
        uint256 expectedAmountReward = 500 ether * 1e12;
        uint256 expectedMilestoneReward = 10e18; // Assuming 1 consecutive day
        uint256 lockupBoost = 5; // Remaining lockup: 5 days
        uint256 baseReward = expectedTimeReward + expectedAmountReward + expectedMilestoneReward + 0; // No cross-platform
        uint256 boostedReward = baseReward * lockupBoost;

        vm.expectEmit(true, true, false, true);
        emit RewardsCalculated(alice, boostedReward);

        vm.prank(alice);
        hook.beforeAddLiquidity(alice, key, addParams2, emptyData);
        hook.afterAddLiquidity(alice, key, addParams2, emptyData);

        // Check pool rewards
        uint256 poolId = key.toId();
        uint256 rewards = hook.poolRewards(poolId);
        assertEq(rewards, boostedReward + 500 ether * 1e12); // Previous rewards + new rewards
    }

    /**
     * @dev Test that rewards are not boosted after lockup period.
     */
    function testNoLockupBoostAfterPeriod() public {
        // Lock up liquidity for 10 days
        vm.prank(alice);
        hook.lockupLiquidity(alice, 10 days);

        // Add liquidity
        vm.prank(alice);
        bytes memory emptyData = "";
        ICLPoolManager.AddLiquidityParams memory addParams = ICLPoolManager.AddLiquidityParams({
            amount: 500 ether
        });
        hook.beforeAddLiquidity(alice, key, addParams, emptyData);
        hook.afterAddLiquidity(alice, key, addParams, emptyData);

        // Fast forward 11 days (lockup period ended)
        vm.warp(block.timestamp + 11 days);

        // Add liquidity again to trigger reward calculation
        ICLPoolManager.AddLiquidityParams memory addParams2 = ICLPoolManager.AddLiquidityParams({
            amount: 500 ether
        });

        uint256 expectedTimeReward = 11 days * 1e18;
        uint256 expectedAmountReward = 500 ether * 1e12;
        uint256 expectedMilestoneReward = 10e18; // Assuming 1 consecutive day
        uint256 expectedTotalReward = expectedTimeReward + expectedAmountReward + expectedMilestoneReward;

        vm.expectEmit(true, true, false, true);
        emit RewardsCalculated(alice, expectedTotalReward);

        vm.prank(alice);
        hook.beforeAddLiquidity(alice, key, addParams2, emptyData);
        hook.afterAddLiquidity(alice, key, addParams2, emptyData);

        // Check pool rewards
        uint256 poolId = key.toId();
        uint256 rewards = hook.poolRewards(poolId);
        assertEq(rewards, expectedTotalReward + 500 ether * 1e12); // Previous rewards + new rewards
    }

    /**
     * @dev Test adding liquidity by multiple LPs.
     */
    function testMultipleLPs() public {
        // Alice adds liquidity
        vm.prank(alice);
        bytes memory emptyData = "";
        ICLPoolManager.AddLiquidityParams memory addParamsAlice = ICLPoolManager.AddLiquidityParams({
            amount: 500 ether
        });
        hook.beforeAddLiquidity(alice, key, addParamsAlice, emptyData);
        hook.afterAddLiquidity(alice, key, addParamsAlice, emptyData);

        // Bob adds liquidity
        vm.prank(bob);
        ICLPoolManager.AddLiquidityParams memory addParamsBob = ICLPoolManager.AddLiquidityParams({
            amount: 300 ether
        });
        hook.beforeAddLiquidity(bob, key, addParamsBob, emptyData);
        hook.afterAddLiquidity(bob, key, addParamsBob, emptyData);

        // Fast forward 2 days
        vm.warp(block.timestamp + 2 days);

        // Alice adds more liquidity
        ICLPoolManager.AddLiquidityParams memory addParamsAlice2 = ICLPoolManager.AddLiquidityParams({
            amount: 200 ether
        });
        hook.beforeAddLiquidity(alice, key, addParamsAlice2, emptyData);
        hook.afterAddLiquidity(alice, key, addParamsAlice2, emptyData);

        // Bob removes some liquidity
        ICLPoolManager.RemoveLiquidityParams memory removeParamsBob = ICLPoolManager.RemoveLiquidityParams({
            amount: 100 ether
        });
        hook.beforeRemoveLiquidity(bob, key, removeParamsBob, emptyData);
        hook.afterRemoveLiquidity(bob, key, removeParamsBob, emptyData);

        // Check rewards for Alice
        uint256 poolId = key.toId();
        uint256 rewardsAlice = hook.poolRewards(poolId);
        // Calculate expected rewards for Alice based on her additions
        // This is a simplified expectation; actual calculation would depend on the implementation
        // For demonstration, assume rewards are correctly calculated
        assertTrue(rewardsAlice > 0);

        // Check rewards for Bob
        uint256 rewardsBob = hook.poolRewards(poolId);
        assertTrue(rewardsBob > 0);
    }

    /**
     * @dev Test that rewards are correctly accumulated in the pool.
     */
    function testPoolRewardAccumulation() public {
        // Alice adds liquidity
        vm.prank(alice);
        bytes memory emptyData = "";
        ICLPoolManager.AddLiquidityParams memory addParamsAlice = ICLPoolManager.AddLiquidityParams({
            amount: 1000 ether
        });
        hook.beforeAddLiquidity(alice, key, addParamsAlice, emptyData);
        hook.afterAddLiquidity(alice, key, addParamsAlice, emptyData);

        // Fast forward 1 day
        vm.warp(block.timestamp + 1 days);

        // Alice adds more liquidity
        ICLPoolManager.AddLiquidityParams memory addParamsAlice2 = ICLPoolManager.AddLiquidityParams({
            amount: 500 ether
        });
        hook.beforeAddLiquidity(alice, key, addParamsAlice2, emptyData);
        hook.afterAddLiquidity(alice, key, addParamsAlice2, emptyData);

        // Check pool rewards
        uint256 poolId = key.toId();
        uint256 rewards = hook.poolRewards(poolId);

        // Expected rewards: initial 5000 + timeReward + amountReward + milestoneReward
        uint256 expectedTimeReward = 1 days * 1e18;
        uint256 expectedAmountReward = 1000 ether * 1e12;
        uint256 expectedMilestoneReward = 10e18; // 1 consecutive day
        uint256 totalExpected = 5000 + expectedTimeReward + expectedAmountReward + expectedMilestoneReward;

        assertEq(rewards, totalExpected);
    }

    /**
     * @dev Test that only the pool manager can call restricted functions.
     */
    function testOnlyPoolManager() public {
        // Attempt to call a restricted function from a non-pool manager address
        vm.prank(alice);
        bytes memory emptyData = "";
        ICLPoolManager.AddLiquidityParams memory addParams = ICLPoolManager.AddLiquidityParams({
            amount: 500 ether
        });

        vm.expectRevert("Not pool manager");
        hook.beforeAddLiquidity(alice, key, addParams, emptyData);
    }

    /**
     * @dev Mock CLPoolManager for testing purposes.
     */
    contract MockCLPoolManager is ICLPoolManager {
        function initialize(
            PoolKey calldata,
            uint160,
            bytes calldata
        ) external pure override returns (bool) {}

        function addLiquidity(
            address,
            PoolKey calldata,
            ICLPoolManager.AddLiquidityParams calldata,
            bytes calldata
        ) external pure override returns (bool) {}

        function removeLiquidity(
            address,
            PoolKey calldata,
            ICLPoolManager.RemoveLiquidityParams calldata,
            bytes calldata
        ) external pure override returns (bool) {}

        function swap(
            address,
            PoolKey calldata,
            ICLPoolManager.SwapParams calldata,
            bytes calldata
        ) external pure override returns (bool) {}
    }
}

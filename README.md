# IncentivizedLPHook

The `IncentivizedLPHook` is a PancakeSwap v4 hoook that incentivizes Liquidity Providers (LPs) based on multiple factor. By utilizing various reward mechanisms, this hook aims to enhance liquidity provision by rewarding LPs for their contributions over time, the amount of liquidity provided, milestone achievements, cross-platform contributions and lockup commitments

Key Features

- **Time-Based Rewards**: LPs earn rewards that are directly proportional to the duration their liquidity remains locked in the pool. This ensures that the longer LPs provide liquidity, the more rewards they accumulate

- **Amount-Based Rewards**: Rewards are calculated based on the total amount of liquidity an LP contributes to the pool. This incentivizes larger contributions and encourages LPs to add more liquidity

- **Milestone-Based Rewards**: LPs receive additional rewards when they achieve specific milestones, such as maintaining liquidity for consecutive days. This feature promotes long-term engagement and commitment from LPs

- **Cross-Platform Contributions**: LPs are rewarded for contributions made across different platforms, recognizing their efforts in the broader DeFi ecosystem

- **Lockup Boosted Rewards**: By locking up liquidity for extended periods, LPs can earn bonus rewards, creating an incentive for them to commit their funds for longer durations

## Contract Overview

### Dependencies

The `IncentivizedLPHook` contract inherits from `CLBaseHook` and interacts with the PancakeSwap v4 core modules, specifically the `ICLPoolManager`, `BalanceDelta`, `PoolIdLibrary`, and `PoolKey` contracts

### Structs

- **LPInfo**: A struct that stores information about each liquidity provider, including:

  - `totalLiquidity`: Total liquidity provided by the LP
  - `liquidityStartTime`: Timestamp of when the LP first provided liquidity
  - `consecutiveDays`: Count of consecutive days the LP has provided liquidity
  - `lockupEndTime`: The timestamp when the liquidity lockup period ends
  - `crossPlatformContributions`: Count of contributions made across different platforms

### Mappings

- `lpInfos`: Maps each LP's address to their corresponding `LPInfo` struct
- `poolRewards`: Maps each pool's ID to the accumulated rewards for that pool

### Events

The contract emits several events to facilitate tracking and monitoring:

- `LiquidityAdded`: Emitted when liquidity is added by an LP
- `LiquidityRemoved`: Emitted when liquidity is removed by an LP
- `RewardsCalculated`: Emitted when rewards are calculated for an LP
- `LiquidityLocked`: Emitted when an LP locks up their liquidity

### Functions

- **Constructor**: Initializes the contract with the pool manager's address
- **getHooksRegistrationBitmap**: Registers the required callbacks for the hook. This function determines which events the hook will listen for during liquidity management
- **afterInitialize**: Callback executed after the pool is initialized, where initial pool-specific rewards are set
- **beforeAddLiquidity**: Callback executed before liquidity is added. It updates the LP's total liquidity and sets the liquidity start time if it’s their first contribution
- **afterAddLiquidity**: Callback executed after liquidity is added. It calculates and distributes rewards based on the LP's contribution
- **beforeRemoveLiquidity**: Callback executed before liquidity is removed. It updates the LP's total liquidity and resets the consecutive days counter if necessary
- **afterRemoveLiquidity**: Callback executed after liquidity is removed. It calculates rewards based on the LP's remaining liquidity
- **lockupLiquidity**: Allows LPs to lock up their liquidity for a specified duration, enhancing their reward potential
- **\_calculateRewards**: Internal function that calculates rewards based on various factors, including time, amount, milestones, cross-platform contributions and lockup status
- **incrementCrossPlatformContributions**: Function to increment the count of cross-platform contributions for an LP. This can be called by other contracts or mechanisms that track contributions across different platforms

## How to Use

1. **Deploy the Contract**: Deploy the `IncentivizedLPHook` contract with the address of the pool manager
2. **Add Liquidity**: Liquidity providers can add liquidity to the pool, which will trigger the `beforeAddLiquidity` and `afterAddLiquidity` callbacks
3. **Remove Liquidity**: When LPs choose to remove liquidity, the `beforeRemoveLiquidity` and `afterRemoveLiquidity` callbacks will handle the necessary updates and reward calculations
4. **Lock Up Liquidity**: LPs can lock their liquidity using the `lockupLiquidity` function, increasing their potential rewards
5. **Cross-Platform Contributions**: Integrate mechanisms to track and update cross-platform contributions to maximize rewards

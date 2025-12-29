# Test Scenarios Documentation

This document catalogs all test scenarios with their purpose, inputs, and expected outcomes. Use this as a reference for understanding the test coverage and running specific scenarios.

## Running Tests

```bash
# Run all tests
forge test

# Run with verbose output
forge test -vvv

# Run specific test file
forge test --match-path test/EdgeCases.t.sol -vvv

# Run specific test function
forge test --match-test test_SwapSmallAmountPrecision -vvv

# Generate gas report
forge test --gas-report

# Run fuzz tests with more runs
forge test --match-path test/SwapFuzz.t.sol --fuzz-runs 10000
```

---

## Test Categories

### 1. Edge Cases (`EdgeCases.t.sol`)
Tests boundary conditions and error handling.

| Test                                            | Purpose                         | Expected Result                           |
| ----------------------------------------------- | ------------------------------- | ----------------------------------------- |
| `testRevert_SwapZeroAmount`                     | Swap with 0 input               | Reverts with `INSUFFICIENT_INPUT_AMOUNT`  |
| `testRevert_AddLiquidityZeroAmountA`            | Add liquidity with 0 tokenA     | Reverts                                   |
| `testRevert_AddLiquidityZeroAmountB`            | Add liquidity with 0 tokenB     | Reverts                                   |
| `testRevert_SwapExpiredDeadline`                | Swap after deadline             | Reverts with `EXPIRED`                    |
| `testRevert_AddLiquidityExpiredDeadline`        | Add liquidity after deadline    | Reverts with `EXPIRED`                    |
| `testRevert_RemoveLiquidityExpiredDeadline`     | Remove liquidity after deadline | Reverts with `EXPIRED`                    |
| `testRevert_SwapInsufficientOutputAmount`       | Slippage exceeds tolerance      | Reverts with `INSUFFICIENT_OUTPUT_AMOUNT` |
| `testRevert_RemoveLiquidityInsufficientAmountA` | Output below minimum            | Reverts with `INSUFFICIENT_A_AMOUNT`      |
| `testRevert_RemoveLiquidityInsufficientAmountB` | Output below minimum            | Reverts with `INSUFFICIENT_B_AMOUNT`      |
| `testRevert_SwapWithoutApproval`                | Swap without token approval     | Reverts on transfer                       |
| `testRevert_AddLiquidityWithoutApproval`        | Add liquidity without approval  | Reverts on transfer                       |
| `test_SwapSmallAmountPrecision`                 | Very small swap amounts         | Non-zero output (no precision loss)       |
| `test_SwapLargeAmountNoOverflow`                | Large swap amounts              | Completes without overflow                |
| `testRevert_CreatePairIdenticalTokens`          | Create pair with same token     | Reverts with `IDENTICAL_ADDRESSES`        |
| `testRevert_CreatePairZeroAddress`              | Create pair with zero address   | Reverts with `ZERO_ADDRESS`               |
| `testRevert_CreateDuplicatePair`                | Create existing pair            | Reverts with `PAIR_EXISTS`                |
| `testRevert_SwapInvalidPathLength`              | Path with only 1 token          | Reverts with `INVALID_PATH`               |
| `testRevert_SwapNonExistentPair`                | Swap through non-existent pair  | Reverts                                   |
| `test_PairLockPreventsReentrancy`               | Multiple sequential swaps       | All succeed (lock releases correctly)     |
| `test_MinimumLiquidityLocked`                   | First liquidity provision       | MINIMUM_LIQUIDITY locked at address(0)    |

---

### 2. Market Conditions (`MarketConditions.t.sol`)
Simulates real-world trading scenarios.

| Test                                       | Scenario                          | Key Observation                         |
| ------------------------------------------ | --------------------------------- | --------------------------------------- |
| `test_HighSlippage_LargeTradeInSmallPool`  | 50% of pool traded                | >30% price impact, trade still succeeds |
| `test_LowLiquidity_MinimumViablePool`      | Pool just above MINIMUM_LIQUIDITY | Reserves > 0                            |
| `test_LowLiquidity_SwapDrainsPool`         | Huge swap vs small pool           | Output capped below total reserve       |
| `test_PriceImpact_GradualIncrease`         | Increasing trade sizes            | Price impact scales with size           |
| `test_ImbalancedPool_Extreme99to1Ratio`    | 99:1 reserve ratio                | Scarce token has high price             |
| `test_ImbalancedPool_ArbitrageOpportunity` | Arbitrage trade                   | K increases from fees                   |
| `test_SandwichAttack_VictimGetsLess`       | Front-run + victim + back-run     | Victim receives less than fair value    |
| `test_SandwichProtection_SlippageLimit`    | Attack with slippage protection   | Victim's swap reverts (protected)       |
| `test_ConsecutiveSwaps_PriceChange`        | Same-direction swaps              | Each yields less (price moves)          |
| `test_Volatility_RapidBidirectionalSwaps`  | 10 round-trip swaps               | K grows from accumulated fees           |

---

### 3. Remove Liquidity (`RemoveLiquidity.t.sol`)
Tests LP token lifecycle.

| Test                                              | Scenario                    | Verification                          |
| ------------------------------------------------- | --------------------------- | ------------------------------------- |
| `test_RemoveLiquidity_FullPosition`               | Remove 100% of LP tokens    | LP balance = 0, receive tokens        |
| `test_RemoveLiquidity_PartialPosition`            | Remove 50%                  | Half LP remains, receive proportional |
| `test_RemoveLiquidity_MultiplePartialRemovals`    | 4x 25% removals             | All LP removed across transactions    |
| `test_RemoveLiquidity_AfterSwaps_FeeAccumulation` | Remove after many swaps     | K increased, LP gets fee share        |
| `test_RemoveLiquidity_MultipleProviders`          | 2 LPs, different sizes      | Each gets proportional share          |
| `test_RemoveLiquidity_FromImbalancedPool`         | Remove from imbalanced pool | More of abundant token returned       |
| `test_RemoveLiquidity_WithMinimumAmounts`         | Enforce minimum outputs     | Exact expected amounts                |
| `test_RemoveLiquidity_ToDifferentRecipient`       | Send to another address     | Recipient receives tokens, LP burned  |
| `test_RemoveLiquidity_GasUsage`                   | Measure gas consumption     | < 200,000 gas                         |

---

### 4. Multi-Hop Routing (`MultiHop.t.sol`)
Tests path routing through multiple pools.

| Test                                       | Path                      | Key Verification               |
| ------------------------------------------ | ------------------------- | ------------------------------ |
| `test_MultiHop_ThreeTokenPath`             | A → B → C                 | Receives expected final output |
| `test_MultiHop_FourTokenPath`              | A → B → C → D             | 4-hop swap succeeds            |
| `test_MultiHop_DirectVsIndirectPath`       | A → C vs A → B → C        | Direct path more efficient     |
| `test_MultiHop_FeesCompound`               | 2/3/4 hop comparison      | Efficiency decreases with hops |
| `test_MultiHop_IntermediateAmountsCorrect` | A → B → C breakdown       | Intermediate = direct A → B    |
| `test_MultiHop_CircularArbitrage`          | A → B → C → A             | Log profit/loss                |
| `test_MultiHop_ReversePath`                | Forward then reverse      | Round trip < input (fee loss)  |
| `test_MultiHop_SlippageProtection`         | 3-hop with impossible min | Reverts correctly              |
| `test_MultiHop_LargeSwapPriceImpact`       | Large vs small multi-hop  | Large has worse efficiency     |
| `test_MultiHop_GasUsage`                   | 2-hop vs 3-hop gas        | 3-hop uses more gas            |

---

### 5. Router Extensions (`RouterExtensions.t.sol`)
Tests new Router functionality.

| Test                                 | Function                | Verification                      |
| ------------------------------------ | ----------------------- | --------------------------------- |
| `test_GetAmountsIn_Basic`            | `getAmountsIn`          | Correct input for desired output  |
| `test_GetAmountsIn_MultiHop`         | `getAmountsIn` 3-token  | All intermediate amounts correct  |
| `test_SwapTokensForExactTokens`      | Exact output swap       | Receives exact requested amount   |
| `test_AddLiquidityETH`               | Add liquidity with ETH  | Pool created, LP tokens received  |
| `test_AddLiquidityETH_RefundsExcess` | Excess ETH handling     | Unused ETH refunded               |
| `test_SwapExactETHForTokens`         | ETH → Token             | Tokens received, ETH consumed     |
| `test_SwapExactTokensForETH`         | Token → ETH             | ETH received                      |
| `test_SwapETHForExactTokens`         | ETH → Exact tokens      | Exact tokens, excess ETH refunded |
| `test_SwapTokensForExactETH`         | Token → Exact ETH       | Exact ETH received                |
| `test_RemoveLiquidityETH`            | Remove liquidity to ETH | Tokens + ETH received             |

---

### 6. Fuzz Tests (`SwapFuzz.t.sol`)
Randomized input testing.

| Test                       | Runs          | Bounds                      |
| -------------------------- | ------------- | --------------------------- |
| `testFuzz_SwapCorrectness` | 256 (default) | amountIn: 1000 to 1M tokens |

---

### 7. Invariant Tests (`Invariant.t.sol`)
System-wide property verification.

| Invariant                         | Property                         |
| --------------------------------- | -------------------------------- |
| `invariant_reservesMatchBalances` | Reserves ≤ actual token balances |

---

## Test Coverage Summary

| Category          | Tests        | Focus                         |
| ----------------- | ------------ | ----------------------------- |
| Edge Cases        | 20           | Boundaries, errors, precision |
| Market Conditions | 10           | Real-world scenarios          |
| Remove Liquidity  | 9            | LP lifecycle                  |
| Multi-Hop         | 10           | Path routing                  |
| Router Extensions | 12           | ETH wrappers, exact output    |
| Core Swap         | 3            | Basic functionality           |
| Fuzz              | 1 (256 runs) | Random inputs                 |
| Invariant         | 1            | Global properties             |
| **Total**         | **66**       |                               |

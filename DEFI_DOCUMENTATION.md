# DeFi Protocol Documentation

## Overview
This project implements a decentralized exchange (DEX) protocol based on the **Uniswap V2** architecture. It facilitates trustless token swapping and automated liquidity provision using the **Constant Product Market Maker (CPMM)** model.

## Features

### 1. Automated Market Maker (AMM)
*   **Constant Product Formula**: The core mechanism relies on the invariant $x \cdot y = k$, where $x$ and $y$ are the reserves of two tokens in a pool, and $k$ remains constant during trades (token value is determined by the ratio $x/y$).
*   **Liquidity Pools**: Users can become Liquidity Providers (LPs) by depositing an equal value of two tokens into a pool. In return, they receive **LP Tokens** representing their share of the pool.
*   **Fees**: A 0.3% fee is charged on every swap. This fee is added to the liquidity pool, acting as a reward for LPs (increasing the value of their LP tokens).

### 2. Core Contracts
*   **Factory (`Factory.sol`)**:
    *   Serves as a registry for all token pairs.
    *   Ensures only one unique pool exists for any pair of tokens.
    *   Deploys new `Pair` contracts using `create2` for deterministic addresses.
*   **Pair (`Pair.sol`)**:
    *   Holds the liquidity reserves for two specific tokens (Token A and Token B).
    *   Implements the low-level `swap` logic verification ($x \cdot y \ge k$).
    *   Handles `mint` (add liquidity) and `burn` (remove liquidity) logic.
    *   Inherits from `ERC20` to manage LP tokens.
*   **Router (`Router.sol`)**:
    *   The periphery contract that users interact with directly.
    *   Calculates optimal swap amounts and liquidity ratios.
    *   Handles safety checks (slippage protection, deadlines) and multi-hop routing paths.
    *   Manages user approvals and transfers.

### 3. Token Standards
*   **WETH9 (Wrapped Ether)**: Since the protocol handles ERC20/ERC20 pairs, native ETH is wrapped into WETH to conform to the ERC20 standard for uniform processing.
*   **ERC20Mock**: A standard ERC20 implementation used for testing and deploying demo tokens (e.g., "Test Token A").

## Mechanics (How it Works)

### Adding Liquidity
1.  **Approval**: User approves the Router to spend their tokens.
2.  **Add**: User calls `addLiquidity` on the Router with desired amounts.
3.  **Calculation**: The Router calculates the optimal ratio to ensure the current price isn't impacted (amountB = amountA * reserveB / reserveA).
4.  **Transfer**: Tokens are transferred from the user to the Pair contract.
5.  **Mint**: The Pair contract mints LP tokens to the user proportional to their contribution relative to the total pool size.

### Swapping
1.  **Calculation**: User requests to swap Amount In of Token A for Token B. The Router calculates Amount Out using the formula:
    $$ \text{Amount Out} = \frac{\text{Amount In} \cdot 997 \cdot \text{Reserve Out}}{(\text{Reserve In} \cdot 1000) + (\text{Amount In} \cdot 997)} $$
    *(The 997/1000 factor accounts for the 0.3% fee)*
2.  **Transfer**: User transfers Amount In to the Pair contract.
3.  **Swap**: The Pair contract executes the swap, sending Amount Out to the user, and verifying the K invariant holds.

### Removing Liquidity
1.  **Burn**: User sends LP tokens to the Pair contract via the Router.
2.  **Withdraw**: The Pair contract burns the LP tokens and sends the proportional share of the underlying reserves (Token A + Token B) back to the user.

## Testing & Verification

### 1. Automated Tests (Foundry)
The project includes a comprehensive test suite with **66 tests** covering:

#### Test Files
| File                     | Tests        | Focus                                         |
| ------------------------ | ------------ | --------------------------------------------- |
| `EdgeCases.t.sol`        | 20           | Zero amounts, overflows, precision, deadlines |
| `MarketConditions.t.sol` | 10           | Slippage, sandwich attacks, price impact      |
| `RemoveLiquidity.t.sol`  | 9            | LP lifecycle, fee accumulation                |
| `MultiHop.t.sol`         | 10           | Multi-token path routing                      |
| `RouterExtensions.t.sol` | 12           | ETH wrappers, exact output swaps              |
| `SwapFuzz.t.sol`         | 1 (256 runs) | Randomized input testing                      |
| `Invariant.t.sol`        | 1            | Reserve ≤ balance invariant                   |

**Run Tests:**
```bash
forge test -vvv
```

**Run with Gas Report:**
```bash
forge test --gas-report
```

See [TEST_SCENARIOS.md](./TEST_SCENARIOS.md) for detailed test documentation.

---

## Advanced Features

### 1. ETH Wrapper Functions
The Router supports native ETH through automatic WETH wrapping:

| Function                | Description                             |
| ----------------------- | --------------------------------------- |
| `addLiquidityETH`       | Add liquidity with native ETH           |
| `removeLiquidityETH`    | Remove liquidity and receive native ETH |
| `swapExactETHForTokens` | Swap ETH for tokens                     |
| `swapTokensForExactETH` | Swap tokens for exact ETH amount        |
| `swapExactTokensForETH` | Swap tokens for ETH                     |
| `swapETHForExactTokens` | Swap ETH for exact token amount         |

### 2. Exact Output Swaps
*"I want exactly 100 tokens — tell me how much to pay"*

```solidity
// Swap tokens to get exactly `amountOut` of output token
router.swapTokensForExactTokens(
    amountOut,    // Exact output desired
    amountInMax,  // Maximum input willing to spend
    path,
    to,
    deadline
);
```

### 3. TWAP Oracle
The `Oracle.sol` contract provides manipulation-resistant price feeds using Time-Weighted Average Prices.

**How TWAP Works:**
1. Prices are recorded as observations each time `update()` is called
2. TWAP = (cumulativePriceEnd - cumulativePriceStart) / timeElapsed
3. Manipulation requires sustaining artificial price for entire TWAP period

**Key Functions:**
| Function                                         | Description                   |
| ------------------------------------------------ | ----------------------------- |
| `update(pair)`                                   | Record new price observation  |
| `consult(pair, period)`                          | Get TWAP for specified period |
| `getSpotPrice(pair)`                             | Get current spot price        |
| `isPriceManipulated(pair, period, maxDeviation)` | Detect price manipulation     |

---

## Security Considerations

### 1. Reentrancy Protection
All state-changing functions in `Pair.sol` use a lock modifier:
```solidity
modifier lock() {
    require(unlocked == 1, "Pair: LOCKED");
    unlocked = 0;
    _;
    unlocked = 1;
}
```

### 2. Slippage Protection
Users should always set appropriate `amountOutMin` or `amountInMax`:
```solidity
// Protect against 1% slippage
uint amountOutMin = expectedOutput * 99 / 100;
router.swapExactTokensForTokens(amountIn, amountOutMin, path, to, deadline);
```

### 3. Deadline Protection
All Router functions require a deadline parameter to prevent stale transactions:
```solidity
uint deadline = block.timestamp + 20 minutes;
```

### 4. Flash Loan Considerations
While the Pair contract supports flash swaps (sending tokens before receiving), the K invariant check prevents exploitation.

---

## Local Development

### Full Setup
```bash
# Terminal 1: Start local blockchain
anvil

# Terminal 2: Deploy contracts
forge script script/Deploy.s.sol \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# Terminal 3: Start frontend
cd frontend && npm run dev
```

### Test Wallets
Anvil provides 10 pre-funded accounts. Account 0 (default deployer):
- Address: `0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266`
- Private Key: `0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80`


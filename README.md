# MiniSwap V2

A **production-ready** AMM implementation featuring comprehensive testing, ETH wrappers, and TWAP oracle — built for portfolio demonstration.

```
┌─────────────┐    ┌─────────────┐
│   Router    │───▶│    Pair     │
│ (Periphery) │    │   (Core)    │
└──────┬──────┘    └──────┬──────┘
       │                   │
┌──────▼──────┐    ┌──────▼──────┐
│   Factory   │    │   Oracle    │
│ (Registry)  │    │   (TWAP)    │
└─────────────┘    └─────────────┘
```

## Overview

This project implements a decentralized exchange (DEX) protocol based on the **Constant Product Market Maker (CPMM)** model. It facilitates trustless token swapping and automated liquidity provision, architected for security and extensibility.

### Key Features

| Feature         | Description                                 |
| --------------- | ------------------------------------------- |
| **Token Swaps** | ERC20 ↔ ERC20 with 0.3% fee                 |
| **Liquidity**   | Automated market making with LP tokens      |
| **ETH Support** | Native ETH wrapping/unwrapping              |
| **Oracle**      | On-chain TWAP (Time-Weighted Average Price) |
| **Safety**      | Slippage protection & deadline checks       |
| **Flash Swaps** | Optimistic transfers (borrow before pay)    |

---

## Architecture & Mechanics

### Core Contracts

*   **Factory (`Factory.sol`)**: The registry that deploys valid `Pair` contracts using `create2`. Ensures only one canonical pool exists per token pair.
*   **Pair (`Pair.sol`)**: Holds liquidity reserves and executes low-level swaps. Enforces the $x \cdot y = k$ constant product invariant.
*   **Router (`Router.sol`)**: The user-facing periphery. It handles multi-hop routing, safety checks (slippage, deadlines), and abstracting interaction with Pairs.

### How it Works

#### Automated Market Maker (AMM)
The protocol relies on the invariant $x \cdot y = k$, where $x$ and $y$ are the reserves of two tokens. When a user trades, they add to one reserve and subtract from the other, shifting the price along the hyperbola defined by $k$.

#### 1. Adding Liquidity
LPs deposit an equal value of both tokens. The protocol calculates optimal ratios to prevent arbitrage:
`amountB_optimal = amountA * reserveB / reserveA`
LPs receive **LP Tokens** representing their fractional ownership of the pool's liquidity.

#### 2. Swapping
Output amounts are calculated with a 0.3% fee applied to the input:
$$ \text{Amount Out} = \frac{\text{Amount In} \cdot 997 \cdot \text{Reserve Out}}{(\text{Reserve In} \cdot 1000) + (\text{Amount In} \cdot 997)} $$

#### 3. Removing Liquidity
LPs burn their LP tokens to receive their proportional share of the underlying reserves, including accumulated trading fees.

### Advanced Features

#### TWAP Oracle (`Oracle.sol`)
Provides manipulation-resistant price feeds.
*   **Mechanism**: Accumulates cumulative prices on every block interaction.
*   **Usage**: `TWAP = (priceCumulativeEnd - priceCumulativeStart) / timeElapsed`.
*   **Security**: Attacking the oracle requires sustaining a manipulated price over the entire period, making it economically infeasible for long durations.

#### Flash Loans
The `Pair` contract supports flash swaps, allowing users to receive tokens *before* paying for them, provided the invariant constraint is met by the end of the transaction.

---

## Security Considerations

1.  **Reentrancy Protection**: Critical functions in `Pair.sol` are protected by a mutex lock to prevent reentrant attacks.
2.  **Slippage Guards**: Router functions require `amountOutMin` or `amountInMax` arguments to protect users from front-running/sandwich attacks.
3.  **Deadlines**: Transactions expire if not executed by a specific timestamp, preventing miners from holding transactions until they are unfavorable.
4.  **K Invariant**: The strict enforcement of `reserve0 * reserve1 >= k` ensures the pool can never be drained (except for negligible rounding).

---

## Development

### Tech Stack
*   **Language**: Solidity 0.8.24
*   **Framework**: Foundry (Forge, Cast, Anvil)
*   **Lib**: Solmate (for optimized ERC20)

### Project Structure
```
├── src/
│   ├── Factory.sol      # Registry & Pair deployment
│   ├── Pair.sol         # Core AMM logic
│   ├── Router.sol       # User interaction layer
│   ├── Oracle.sol       # Price feeds
│   └── WETH9.sol        # ETH wrapper
├── test/
│   ├── EdgeCases.t.sol       # Boundary conditions
│   ├── MarketConditions.t.sol # Simulation tests
│   ├── RemoveLiquidity.t.sol  # LP flows
│   ├── MultiHop.t.sol         # Routing logic
│   └── SwapFuzz.t.sol         # Fuzzing
└── script/
    └── Deploy.s.sol     # Deployment scripts
```

### Quick Start

**Prerequisites**: [Foundry](https://getfoundry.sh), Node.js ≥ 18

1.  **Start Local Chain**
    ```bash
    anvil
    ```

2.  **Deploy Contracts**
    ```bash
    forge script script/Deploy.s.sol \
      --rpc-url http://127.0.0.1:8545 \
      --broadcast \
      --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
    ```

---

## Testing & Verification

The project implements a comprehensive test suite with **66 tests** covering edge cases, market simulations, and fuzzing.

### Run Tests
```bash
forge test                  # Run all
forge test -vvv             # Verbose execution traces
forge test --gas-report     # Gas usage analysis
```

### Test Scope

| Category         | Count | Focus Areas                                                                 |
| :--------------- | :---- | :-------------------------------------------------------------------------- |
| **Edge Cases**   | 20    | Zero amounts, overflows, precision loss, expired deadlines, invalid paths.  |
| **Market Types** | 10    | High slippage, sandwich attacks, liquidity draining, volatility simulation. |
| **LP Lifecycle** | 9     | Full/partial removals, fee accumulation, multiple providers.                |
| **Multi-Hop**    | 10    | A→B→C routing, fee compounding, path efficiency.                            |
| **Router Ext**   | 12    | WETH wrapping, exact output swaps (`swapTokensForExactTokens`).             |
| **Invariants**   | 5+    | Fuzzing 1000s of runs to ensure `reserves <= balances`.                     |

---

## License
MIT

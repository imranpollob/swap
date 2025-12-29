# MiniSwap V2

A **production-ready** Uniswap V2 implementation featuring comprehensive testing, ETH wrappers, and TWAP oracle — built for portfolio demonstration.

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│   Frontend  │───▶│   Router    │───▶│    Pair     │
│  (Next.js)  │    │ (Periphery) │    │   (Core)    │
└─────────────┘    └──────┬──────┘    └──────┬──────┘
                          │                   │
                   ┌──────▼──────┐    ┌──────▼──────┐
                   │   Factory   │    │   Oracle    │
                   │ (Registry)  │    │   (TWAP)    │
                   └─────────────┘    └─────────────┘
```

## Features

| Feature             | Status | Description                     |
| ------------------- | ------ | ------------------------------- |
| Token Swaps         | ✅      | ERC20 ↔ ERC20 with 0.3% fee     |
| Liquidity Provision | ✅      | Add/remove liquidity, LP tokens |
| ETH Support         | ✅      | Native ETH wrapping/unwrapping  |
| Exact Output Swaps  | ✅      | Specify desired output amount   |
| Multi-hop Routing   | ✅      | A→B→C path support              |
| TWAP Oracle         | ✅      | Manipulation-resistant pricing  |
| Slippage Protection | ✅      | Min output / max input guards   |
| Deadline Protection | ✅      | Transaction expiry              |

## Quick Start

### Prerequisites
- [Foundry](https://getfoundry.sh)
- Node.js ≥ 18

### 1. Deploy Contracts

```bash
# Start local node
anvil

# Deploy (new terminal)
forge script script/Deploy.s.sol \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```

### 2. Run Frontend

```bash
cd frontend
npm install
npm run dev
# Open http://localhost:3000
```

### 3. Run Tests

```bash
# All tests
forge test

# With gas report
forge test --gas-report

# Specific test file
forge test --match-path test/MarketConditions.t.sol -vvv
```

### 4. Setup Browser Wallet (MetaMask)

1.  **Install Wallet**: Install [MetaMask](https://metamask.io/) or [Rabby](https://rabby.io/) extension.
2.  **Add Network**:
    *   **Network Name**: Anvil Local
    *   **RPC URL**: `http://127.0.0.1:8545`
    *   **Chain ID**: `31337`
    *   **Currency Symbol**: ETH
3.  **Import Account**:
    *   Import a private key from the running `anvil` terminal.
    *   **Test Key**: `0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80` (Account 0)
4.  **Important Note**:
    *   When you restart `anvil`, the blockchain state resets.
    *   You must **reset your account** in MetaMask to fix nonce errors:
        *   `Settings` -> `Advanced` -> `Clear activity tab data`

## Project Structure

```
├── src/
│   ├── Factory.sol      # Pair registry, CREATE2 deployment
│   ├── Pair.sol         # AMM core with x*y=k invariant
│   ├── Router.sol       # User-facing periphery (swaps, liquidity, ETH)
│   ├── Oracle.sol       # TWAP price oracle
│   └── WETH9.sol        # Wrapped ETH
├── test/
│   ├── EdgeCases.t.sol       # 20 boundary condition tests
│   ├── MarketConditions.t.sol # 10 real-world scenario tests
│   ├── RemoveLiquidity.t.sol  # 9 LP lifecycle tests
│   ├── MultiHop.t.sol         # 10 routing tests
│   ├── RouterExtensions.t.sol # 12 ETH/exact output tests
│   ├── SwapFuzz.t.sol         # Fuzz testing
│   └── Invariant.t.sol        # Invariant testing
├── frontend/            # Next.js 15 + wagmi + viem
└── script/
    └── Deploy.s.sol     # Deployment + initial liquidity
```

## Test Coverage

| Category                | Tests  | Coverage                               |
| ----------------------- | ------ | -------------------------------------- |
| Edge Cases              | 20     | Zero amounts, overflows, precision     |
| Market Conditions       | 10     | Slippage, sandwich attacks, volatility |
| Remove Liquidity        | 9      | Full/partial removal, fee accumulation |
| Multi-Hop               | 10     | 3/4-token paths, efficiency            |
| Router Extensions       | 12     | ETH wrappers, exact output             |
| Core + Fuzz + Invariant | 5      | Basic ops, random inputs               |
| **Total**               | **66** |                                        |

## Documentation

- [TEST_SCENARIOS.md](./TEST_SCENARIOS.md) — Detailed test catalog
- [DEFI_DOCUMENTATION.md](./DEFI_DOCUMENTATION.md) — Protocol deep-dive

## Tech Stack

**Contracts**: Solidity 0.8.24, Foundry, Solmate  
**Frontend**: Next.js 15, TypeScript, wagmi, viem, TailwindCSS

## License

MIT

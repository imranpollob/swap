# MiniSwap V2

A minimal implementation of Uniswap V2 (Factory, Pair, Router) + Next.js Frontend.

## Architecture

### Contracts (Foundry)
- **Core**: `src/Factory.sol`, `src/Pair.sol`
- **Periphery**: `src/Router.sol`, `src/WETH9.sol`
- **Libraries**: `src/libraries/Math.sol`, `src/libraries/TransferHelper.sol`

### Frontend (Next.js)
- **Directory**: `frontend/`
- **Framework**: Next.js 15 + TypeScript + Tailwind CSS
- **Web3**: `viem` + `wagmi`
- **State**: React Query

## Prerequisites
- [Foundry](https://getfoundry.sh)
- [Node.js](https://nodejs.org/) >= 18

## Getting Started

### 1. Contracts Setup

Start a local node:
```bash
anvil
```

In a new terminal, deploy contracts:
```bash
# Deploy to local Anvil node (ensure anvil is running)
forge script script/Deploy.s.sol --rpc-url http://127.0.0.1:8545 --broadcast --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```
*Note: The private key `0xac09...` is the default Account 0 for Anvil.*

Copy the deployed addresses from the output (WETH9, Factory, Router, TestTokenA) and update `frontend/src/lib/addresses.ts`.

### 2. Frontend Setup

```bash
cd frontend
npm install
npm run dev
```

Open [http://localhost:3000](http://localhost:3000).

## Features (MVP)
- **Swap**: Swap exact tokens for tokens (WETH <> TKA)
- **Pool**: Add liquidity to WETH/TKA pair.

## Testing

Run contract tests:
```bash
cd contracts
forge test
```

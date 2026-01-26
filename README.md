# Swap DEX

A decentralized exchange (DEX) implementation built with Solidity and Foundry, featuring an automated market maker (AMM) protocol with TWAP oracle integration.

## Overview

This project implements a production-ready AMM protocol inspired by Uniswap V2, providing trustless token swapping and liquidity provision on the Ethereum blockchain.

## Core Features

### 🔄 **Automated Market Maker (AMM)**
- Constant product formula (x * y = k) for price discovery
- Deterministic pricing based on liquidity pool reserves
- Slippage protection with minimum output guarantees

### 🏭 **Factory Pattern**
- Deterministic pair creation using CREATE2
- One pair per token combination
- Permissionless pair deployment

### 💧 **Liquidity Management**
- Add liquidity to trading pairs
- Remove liquidity with LP tokens
- Optimal liquidity calculation
- Minimum liquidity lock for initial providers

### 🔀 **Token Swapping**
- Exact input token swaps
- Multi-hop routing support
- Deadline protection for time-sensitive transactions
- Path-based routing for optimal trade execution

### 📊 **TWAP Oracle**
- Time-Weighted Average Price calculations
- Manipulation-resistant price feeds
- Cumulative price tracking
- Configurable observation periods

### 🛡️ **Security Features**
- Reentrancy protection
- Deadline checks for transaction expiration
- Safe math operations with Solmate
- Integer overflow protection

## Technology Stack

- **Solidity** ^0.8.0 - Smart contract development
- **Foundry** - Development framework and testing
- **Solmate** - Gas-optimized contract libraries
- **OpenZeppelin** - Security standards


## Installation

```bash
# Clone the repository
git clone <repository-url>
cd swap

# Install dependencies
forge install

# Build contracts
forge build
```

## Testing

```bash
# Run all tests
forge test

# Run tests with verbosity
forge test -vvv

# Run specific test file
forge test --match-path test/Swap.t.sol

# Run fuzz tests
forge test --match-path test/SwapFuzz.t.sol

# Run with gas reporting
forge test --gas-report
```

## Deployment

```bash
# Deploy to local network
forge script script/Deploy.s.sol --fork-url http://localhost:8545 --broadcast

# Deploy to testnet
forge script script/Deploy.s.sol --rpc-url <RPC_URL> --private-key <PRIVATE_KEY> --broadcast --verify
```


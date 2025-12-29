```md
# AI-Coder Instruction File — Build a Minimal Swap (Uniswap V2–style) Portfolio Project

## 0) Goal (Definition of Done)
Build a working AMM DEX with:
- **Factory + Pair (LP token) + Router + WETH9**
- Add/remove liquidity
- Single-hop + multi-hop swaps via `path[]`
- Slippage protection (`amountOutMin`) + transaction expiry (`deadline`)
- Tests (unit + a few invariant-style checks)
- Simple **Next.js** frontend (Swap + Pool pages)
- Local dev chain (Anvil) + optional Sepolia deployment

**Non-goals (MVP scope limits)**
- No Uniswap V3 ticks / concentrated liquidity
- No governance, fee switch, on-chain oracle, MEV protection
- No complex analytics backend; event-based UI is enough

---

## 1) Tech Stack (Use exactly this unless blocked)
- **Contracts:** Foundry (forge + anvil)
- **Frontend:** Next.js + TypeScript + `viem` (or `ethers` if faster)
- **Wallet:** wagmi + rainbowkit (optional; can do minimal connect)
- **Node:** >= 18

Repo name: `mini-swap-v2`

---

## 2) Repo Structure (Create)
```

mini-swap-v2/
contracts/
foundry.toml
src/
Factory.sol
Pair.sol
Router.sol
WETH9.sol
libraries/
Math.sol
UQ112x112.sol (optional)
TransferHelper.sol
test/
Factory.t.sol
Pair.t.sol
Router.t.sol
Invariants.t.sol (optional but recommended)
script/
Deploy.s.sol
frontend/
package.json
next.config.js
src/
app/
page.tsx
swap/page.tsx
pool/page.tsx
lib/
addresses.ts
abis/
client.ts
math.ts
README.md

```

---

## 3) High-Level Architecture
### Core
- **Factory**: creates pools (Pairs), stores `getPair[token0][token1]`
- **Pair**: holds reserves, mints/burns LP shares, executes swaps, enforces invariant
- **LP token**: Pair itself is an ERC20-like token (name/symbol minimal)

### Periphery
- **Router**: user-friendly functions:
  - `addLiquidity`
  - `removeLiquidity`
  - `swapExactTokensForTokens`
  - (optional) `swapExactETHForTokens`, `swapExactTokensForETH` using WETH9
- **WETH9**: deposit/withdraw wrapper

---

## 4) Implementation Phases (Step-by-step)

# PHASE A — Contracts Foundation

## A1) Initialize Foundry workspace
**Tasks**
1. `mkdir -p contracts && cd contracts`
2. `forge init --no-commit`
3. Configure `foundry.toml` (set `src`, `out`, `libs`, optimizer on)
4. Add `src/` and `test/` directories as in structure.

**Acceptance**
- `forge build` succeeds.

---

## A2) Implement ERC20Mock + TransferHelper
**Files**
- `src/libraries/TransferHelper.sol` (safe transfer/transferFrom/approve)
- `src/test/mocks/ERC20Mock.sol` (simple mintable token used only in tests)

**Requirements**
- ERC20Mock must have `mint(address,uint256)`.
- TransferHelper should `revert()` on failure.

**Acceptance**
- Unit test: mint tokens, approve, transferFrom works.

---

## A3) Implement WETH9 (minimal)
**File:** `src/WETH9.sol`

**Functions**
- `deposit()` payable → mint WETH
- `withdraw(uint256)` → burn WETH, send ETH
- ERC20 interface: `balanceOf`, `approve`, `transfer`, `transferFrom`

**Acceptance**
- Test: deposit 1 ETH → WETH balance increases; withdraw returns ETH.

---

# PHASE B — Core AMM (Factory + Pair)

## B1) Implement Factory
**File:** `src/Factory.sol`

**Storage**
- `mapping(address => mapping(address => address)) public getPair;`
- `address[] public allPairs;`

**Functions**
- `createPair(address tokenA, address tokenB) returns (address pair)`
  - sort tokens: `token0 < token1`
  - require non-zero, require pair not exists
  - deploy Pair (use `new Pair(token0, token1)` or create2 optional)
  - set both mapping directions
  - push to allPairs
  - emit `PairCreated(token0, token1, pair, allPairs.length)`

**Acceptance**
- Test: createPair stores mapping; second createPair reverts; token sorting works.

---

## B2) Implement Pair (LP token + reserves + mint/burn + swap)
**File:** `src/Pair.sol`

### Pair State
- `address public token0;`
- `address public token1;`
- `uint112 private reserve0;`
- `uint112 private reserve1;`
- `uint32  private blockTimestampLast;` (optional)
- LP token state: `totalSupply`, `balanceOf`, `allowance`, `Transfer/Approval`

### Events
- `event Mint(address indexed sender, uint amount0, uint amount1);`
- `event Burn(address indexed sender, uint amount0, uint amount1, address indexed to);`
- `event Swap(address indexed sender, uint amount0In, uint amount1In, uint amount0Out, uint amount1Out, address indexed to);`
- `event Sync(uint112 reserve0, uint112 reserve1);`

### Required Functions
- `getReserves() returns (uint112, uint112, uint32)`
- `_update(balance0, balance1)` updates reserves + emit Sync
- `mint(address to) returns (uint liquidity)`
  - compute amounts added: `balance0 - reserve0`, `balance1 - reserve1`
  - if `totalSupply == 0`: `liquidity = sqrt(amount0*amount1) - MINIMUM_LIQUIDITY`
  - else: `liquidity = min(amount0*totalSupply/reserve0, amount1*totalSupply/reserve1)`
  - mint LP to `to`
- `burn(address to) returns (uint amount0, uint amount1)`
  - burn LP held by Pair itself (Router should transfer LP to Pair before burn)
  - amounts pro-rata: `liquidity*balance0/totalSupply` etc.
- `swap(uint amount0Out, uint amount1Out, address to, bytes calldata data)`
  - require `amount0Out > 0 || amount1Out > 0`
  - require `amount0Out < reserve0 && amount1Out < reserve1`
  - transfer out tokens to `to`
  - compute `amount0In/amount1In` from post-swap balances
  - enforce invariant with fee (0.30%):
    - `balance0Adjusted = balance0*1000 - amount0In*3`
    - `balance1Adjusted = balance1*1000 - amount1In*3`
    - require `balance0Adjusted * balance1Adjusted >= reserve0*reserve1*1000^2`
  - update reserves

### Constants / Helpers
- `MINIMUM_LIQUIDITY = 1000` (mint to address(0) at init)
- `sqrt` + `min` in `libraries/Math.sol`

**Acceptance Tests**
- Mint first liquidity sets LP supply and reserves
- Second liquidity mint mints proportional LP
- Burn returns proportional underlying
- Swap:
  - exact amount out works
  - invariant holds
  - swap fails with insufficient output liquidity
  - swap fails if `to` is token0/token1 (optional safety)

---

# PHASE C — Router (Periphery UX)

## C1) Implement Router
**File:** `src/Router.sol`

**Constructor**
- `address public factory;`
- `address public WETH;`

**Core Helpers**
- `sortTokens(tokenA, tokenB)`
- `pairFor(factory, tokenA, tokenB)` via Factory `getPair`
- `getReserves(tokenA, tokenB)`
- Quote math:
  - `quote(amountA, reserveA, reserveB)`
  - `getAmountOut(amountIn, reserveIn, reserveOut)` with 0.30% fee:
    - `amountInWithFee = amountIn * 997`
    - `amountOut = (amountInWithFee * reserveOut) / (reserveIn*1000 + amountInWithFee)`
  - `getAmountsOut(amountIn, path[])`
  - (optional) `getAmountIn` and `getAmountsIn`

**External Router Methods (MVP)**
- `addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin, to, deadline)`
  - createPair if needed
  - compute optimal amounts based on reserves
  - transferFrom user → Pair
  - call `Pair.mint(to)`
- `removeLiquidity(tokenA, tokenB, liquidity, amountAMin, amountBMin, to, deadline)`
  - transferFrom user → Pair (LP token)
  - call `Pair.burn(to)`
  - check mins
- `swapExactTokensForTokens(amountIn, amountOutMin, path, to, deadline)`
  - compute `amounts = getAmountsOut(amountIn, path)`
  - require `amounts[last] >= amountOutMin`
  - transferFrom user → first Pair
  - do `_swap(amounts, path, to)` through hops calling `Pair.swap(...)`

**Optional ETH Methods (Recommended)**
- `addLiquidityETH`
- `removeLiquidityETH`
- `swapExactETHForTokens`
- `swapExactTokensForETH`
(using WETH deposit/withdraw)

**Deadline**
- `require(block.timestamp <= deadline, "EXPIRED")`

**Acceptance Tests**
- addLiquidity creates pool and mints LP
- swapExactTokensForTokens works 1-hop + 2-hop
- slippage fails when `amountOutMin` too high
- deadline fails when expired

---

# PHASE D — Deployment Scripts

## D1) Foundry Script
**File:** `script/Deploy.s.sol`

**Deploy Order**
1. WETH9
2. Factory
3. Router(factory, WETH)

**Acceptance**
- `forge script ... --fork-url` optional
- On anvil: script broadcasts, prints addresses

---

# PHASE E — Frontend MVP (Next.js)

## E1) Frontend bootstrap
**Tasks**
- `npx create-next-app@latest frontend --ts`
- Install:
  - `viem` + `wagmi` + `@rainbow-me/rainbowkit` (optional)
  - or minimal ethers + window.ethereum

**Acceptance**
- `npm run dev` works

---

## E2) ABI + Addresses wiring
**Files**
- `frontend/src/lib/abis/*.json` (Factory/Pair/Router/ERC20/WETH)
- `frontend/src/lib/addresses.ts` (anvil addresses)
- `frontend/src/lib/client.ts` (publicClient/walletClient config)
- `frontend/src/lib/math.ts` (quote formulas for UI)

**Acceptance**
- UI can read `Factory.getPair` and `Pair.getReserves`

---

## E3) Swap Page
**Route:** `frontend/src/app/swap/page.tsx`

**UI Requirements**
- Wallet connect
- Token selectors (hardcode 2–4 token addresses for MVP; dynamic list optional)
- Input amount
- Quote output using on-chain reserves (read Pair reserves + compute `getAmountOut`)
- Slippage setting (default 0.5% / 1%)
- Approval flow:
  - if allowance < amountIn → `approve(Router, amountIn)`
- Swap button → call `Router.swapExactTokensForTokens`

**Acceptance**
- User swaps TokenA → TokenB successfully on anvil

---

## E4) Pool Page (Liquidity)
**Route:** `frontend/src/app/pool/page.tsx`

**UI Requirements**
- Create pool (implicitly by addLiquidity)
- Add liquidity (A + B inputs)
- Remove liquidity (LP amount input)
- Display:
  - reserves
  - LP balance
  - pool share = LP balance / totalSupply

**Acceptance**
- Add liquidity mints LP, remove returns tokens

---

# PHASE F — Documentation + Polish

## F1) README
**Must include**
- Architecture: core vs periphery
- How to run:
  - `anvil`
  - `forge test`
  - deploy script
  - start frontend
- Security notes: invariant, fee math, deadline/slippage, approvals

## F2) Extra credibility (pick at least 2)
- Add invariant tests (see below)
- Add multi-hop routing demo (TokenA→TokenB→TokenC)
- Add event-based history list on UI (Swap/Mint/Burn)
- Deploy to Sepolia + verified contracts

---

## 5) Testing Requirements (Minimum)
Write tests in Foundry that cover:
1. Factory:
   - createPair works, rejects duplicates
2. Pair:
   - initial mint + MINIMUM_LIQUIDITY
   - second mint proportional
   - burn returns proportional
   - swap invariant + fee
3. Router:
   - addLiquidity/removeLiquidity flows
   - swapExactTokensForTokens with slippage + deadline checks
4. (Optional) Invariant-style:
   - After random swaps, `k` (adjusted) never decreases illegally
   - Reserves match actual token balances after operations

---

## 6) Implementation Rules for AI-Coder
- Do NOT leave TODOs; every step compiles.
- After each phase: run `forge fmt`, `forge build`, `forge test`.
- Prefer explicit revert messages.
- Keep contracts small and readable; no premature optimization.
- Avoid copying Uniswap code verbatim; implement logic from spec-style description.

---

## 7) Common Edge Cases (Must Handle)
- tokenA == tokenB (revert)
- zero address tokens (revert)
- insufficient liquidity (swap reverts)
- amountOutMin not met (router reverts)
- expired deadline (router reverts)
- rounding: ensure no underflows; use checked math (solidity ^0.8)

---

## 8) Deliverables Checklist
- [ ] Contracts: Factory/Pair/Router/WETH9 compile
- [ ] Tests: `forge test` green
- [ ] Deploy script prints addresses
- [ ] Frontend: Swap + Pool pages working on anvil
- [ ] README with run instructions + screenshots/gif

---

## 9) Commands (Local Runbook)
In one terminal:
- `anvil`

In `contracts/`:
- `forge test`
- `forge script script/Deploy.s.sol --rpc-url http://127.0.0.1:8545 --broadcast`

In `frontend/`:
- `npm install`
- `npm run dev`

---

## 10) Exact Contract Interfaces (MVP signatures)
Factory:
- `function createPair(address tokenA, address tokenB) external returns (address pair);`
- `function getPair(address tokenA, address tokenB) external view returns (address pair);`

Pair:
- `function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);`
- `function mint(address to) external returns (uint liquidity);`
- `function burn(address to) external returns (uint amount0, uint amount1);`
- `function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external;`

Router:
- `function addLiquidity(...) external returns (uint amountA, uint amountB, uint liquidity);`
- `function removeLiquidity(...) external returns (uint amountA, uint amountB);`
- `function swapExactTokensForTokens(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline) external returns (uint[] memory amounts);`

WETH9:
- `function deposit() external payable;`
- `function withdraw(uint wad) external;`

END.
```

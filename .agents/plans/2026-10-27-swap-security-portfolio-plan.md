# Swap DEX — Security Research Portfolio Plan (v2)

**Status:** v2 (rewritten in place over the v1 draft, same file; review corrections applied during execution — see implementation notes at the end of §8)
**Goal:** turn this repository into a credible **blockchain security researcher portfolio piece** — an audit case study with executable exploits, quantified impact, verified fixes, and professional reporting — not merely a hardened Uniswap V2 clone.

---

## 0. Verified baseline (do not skip this again)

| Item | Result |
|---|---|
| Repo | Foundry/Solidity 0.8 AMM: `Pair`, `Factory`, `Router`, `Oracle`, `WETH9`; 9 test suites |
| Toolchain | `forge 1.8.4`; solc **0.8.24** auto-selected (`pragma ^0.8.0`, not pinned); solmate + forge-std submodules |
| `forge build` | Succeeds, with lint warnings (`uint` vs `uint256`, unused imports, timestamp-read warnings) |
| `forge test` | **66 passed, 1 failed, 67 total** |
| Failing test | `test/Swap.t.sol::testFailSwapExpired` — `testFail*` was removed in forge 1.8.4 |
| Worktree | Not clean: plan file staged (the `vm.py` modification was Windows-checkout-specific and does not reproduce here) |
| Existing test quality | Broad but shallow; several tests are misleading (see §1.2) |

**v1's Step 1 says "expected: green" and "working tree clean." Both are false.** The plan was written without running the baseline. Fix the red test before anything else, then tag the audit target.

Evidence gathered during this review (throwaway test, now removed):

- `isPriceManipulated` returns `false` with **zero observations** and with `period = 0` — fail-open.
- `consult(pair, 1 days)` returns a **60-second TWAP** when only 60 seconds of history exists — no revert.
- A **30-day-old** observation is accepted as current — `MAX_OBSERVATION_AGE` is dead code.
- `consult` costs **4,939,945 gas with 2,000 observations** (~2.5k gas/observation, linear). One day of per-block updates (~7,200 observations) is ~18M gas; multi-day history exceeds the block gas limit.
- Dust first mint reverts with a **panic (0x11)**, not a reason string.

These are not "gas optimizations." They are availability and oracle-integrity findings.

---

## 1. Review of the project and of plan v1

### 1.1 What the project does well

- The AMM core is a faithful, readable Uniswap V2-style implementation: constant product, 0.3% fee enforced by the K check, LP ERC20, `MINIMUM_LIQUIDITY`, cumulative-price accumulators, `lock` mutex on `Pair`.
- `Factory` uses deterministic CREATE2 pairs; `Router` covers exact-in/exact-out, multi-hop, and the full WETH/ETH suite.
- The code is small enough to audit end-to-end (~1,000 lines of `src/`), which is ideal for a portfolio: a reviewer can actually read it.
- There is already a broad test suite and an invariant handler; the foundation exists.
- No admin keys, no upgradeability, no protocol fee — a clean, immutable target with a small trust surface. This is a security positive and should be stated in the report.

### 1.2 What a security reviewer will flag immediately

**Code issues** (full inventory in §3):

- `Oracle.isPriceManipulated` **fails open** on missing/short history and on `period = 0`.
- `Oracle` observations are **unbounded**; `consult`/`consultBoth`/`isPriceManipulated` scan linearly. This is a permissionless, griefable **DoS**, not just gas drift.
- `Oracle` accepts **stale observations** (`MAX_OBSERVATION_AGE` unused) and **silently shortens** the requested TWAP window.
- `Oracle` trusts **any pair address**; a fake pair can fabricate reserves/cumulatives. No factory provenance check.
- `Oracle` mixes **Q112.112 and 1e18 units**, uses a truncated conversion constant, and ignores token decimals.
- `Pair.initialize` has no one-time guard; dust first mint panics; `amount0 * amount1` can overflow; `swap` has an unused `data` parameter; external `getReserves` is readable mid-transaction (read-only reentrancy surface).
- `Factory.createPair` does not check the CREATE2 result; a failed deployment can corrupt `getPair`/`allPairs`.
- `Router` ETH paths have no reentrancy guard; `pairFor` duplicates the CREATE2 formula; nonexistent pairs revert with no reason; `getAmountIn` can panic; `assert` is used in `receive` and `_addLiquidity`.
- The deploy script mixes infrastructure and seeding, mints test tokens, spends 100 ETH from the broadcaster, and would happily run on mainnet.

**Test-suite issues** (these matter for a security portfolio because they are the evidence):

- `test_PairLockPreventsReentrancy` does **not** attempt reentrancy. It performs two swaps.
- `test_MultiHop_CircularArbitrage` has **no assertion** — it only emits a log.
- `test_MultiHop_GasUsage` asserts 3 hops cost more gas than 2; that is not a security property and is flaky.
- `testFuzz_SwapCorrectness` compares `Router` output to `Router.getAmountsOut` — the same code path. It is a tautology, not an independent check.
- `test_MultiHop_ReversePath` uses an opaque balance formula (simplifies to a round-trip loss bound; keep but clarify, low priority).
- `Invariant.t.sol` only checks `reserve <= balance` (which is true by construction) and its handler swallows all reverts. It does not test `k`, LP backing, token conservation, oracle monotonicity, or access control.
- No tests for: `initialize` guard, CREATE2 prediction, `receive` sender, fee-on-transfer, non-standard ERC20, 6-decimal tokens, read-only reentrancy, donation/`sync`, first-depositor inflation, stale TWAP, or observation DoS.

### 1.3 What plan v1 gets right

- Correctly prioritizes the Oracle as the highest-risk unit.
- Identifies most of the obvious Oracle correctness issues (freshness, short history, duplicate lookup, dead constant, Q112 conversion, zero division).
- Identifies the Pair dust/overflow/initialize issues, Router ETH reentrancy/ordering, Factory CREATE2 result, and deploy-script mixing.
- Risk-ordered approach; no unnecessary dependencies; explicit non-goals; validation commands.
- Correctly says not to redesign the AMM economics.

### 1.4 Where plan v1 is insufficient or wrong

1. **Wrong genre.** It is an engineering hardening plan, not a security research portfolio plan. There is no exploit, no impact, no severity, no methodology, no evidence, and no victim. `docs/FINDINGS.md` as a changelog is not an audit report. Hiring managers for security roles look for **found → exploited → fixed → verified**, with PoCs and economic reasoning.
2. **False baseline.** It claims green/clean; the suite has a red test and the tree is dirty. Its own Step 1 would fail.
3. **Under-rates the Oracle.** The unbounded array is a DoS, not a gas optimization. It misses the **fail-open** `isPriceManipulated`, the **fake-pair provenance** hole, **stale/short-window** severity, **decimal scaling**, and the API hazard of `getSpotPrice`.
4. **FIFO pruning is the wrong data structure.** Shifting a dynamic array on every update is O(n) and can itself exceed block gas. It also says to preserve the `observations` layout “that `test/Oracle.t.sol` indexes” — the test does not index it. Use a **fixed-size ring buffer + binary search + minimum observation interval**.
5. **"Existing suites stay green unmodified in intent" preserves misleading tests.** A security portfolio needs **test-suite triage**: delete or rewrite tests that do not test what their names claim. Keeping them is worse than having fewer tests.
6. **No adversarial/economic attack classes:** donation + `sync` oracle manipulation, first-depositor inflation, read-only reentrancy, fake pair, decimals, non-standard tokens, sandwich profitability, oracle manipulation cost curves.
7. **No victim.** Fixing the Oracle in isolation does not show why it matters. The centerpiece should be a **mock lending protocol** that trusts the Oracle and gets drained, then the same attack failing after the fix.
8. **No CI, static analysis, coverage, fork tests, gas bounds, or toolchain pinning.** Table stakes for a security portfolio.
9. **Deploy safety is incomplete.** It catches the split but not canonical WETH on mainnet, chain-id guards, or explicit signer requirements. Seeding 100 ETH on mainnet would be catastrophic.
10. **No narrative/commit strategy.** No audit-target tag, PoC branch, per-finding fix commits, or pre-fix evidence logs. The git history is part of the portfolio.
11. **Missed findings:** Factory CREATE2 result, `Router.pairFor` duplication/drift, `getAmountIn` underflow, `Pair.getReserves` read-only reentrancy, token-code validation, `swap` unused `data`, `MINIMUM_LIQUIDITY` decimal dependence.
12. **No severity taxonomy, no residuals, no "what was not found."** A real audit states its limits.

**Verdict:** v1 is a useful engineering checklist. It is not sufficient for the stated goal. Keep its good findings, change the framing and evidence bar, and add the missing attack surface.

---

## 2. Positioning, success criteria, non-goals

### 2.1 The narrative

> "I took a Uniswap V2-style AMM and its TWAP oracle as an audit target. I threat-modeled it, found High-severity oracle-integrity and availability issues, wrote executable PoCs that drain a mock lending integrator and make `consult` uncallable, fixed them with a bounded ring buffer, freshness/fail-closed semantics and factory provenance, and proved the fixes with regression tests, invariants, fuzzing, static analysis, and a professional report."

That arc is the portfolio. The code is the evidence; the report is the deliverable.

### 2.2 Success criteria

A reviewer should be able to do this in **under 15 minutes**:

1. Open `README.md`, see the findings summary table with 3–5 High/Medium findings and links.
2. Run `forge test` and see green.
3. Run `forge test --match-path 'test/exploits/*' -vvv` and see the attacks blocked.
4. Read `docs/AUDIT_REPORT.md` and find, for each finding: severity, location, impact, PoC, root cause, fix, regression test, residual risk.
5. See CI, coverage, and static-analysis results without installing anything.

Concrete done criteria:

- Every finding in §3 is **fixed** or explicitly **accepted with a test and rationale**.
- Every High/Medium finding has a test that **fails on the audit-target tag** and **passes on HEAD** (evidence logs in `docs/evidence/`).
- The Oracle has bounded gas, no fail-open path, freshness enforcement, full-window validation, factory provenance, and documented units/decimals.
- The invariant suite covers `k` behavior, LP backing, token conservation, oracle monotonicity/bounds, and factory/router consistency.
- `forge fmt --check`, `forge build`, `forge test`, `FOUNDRY_PROFILE=ci forge test`, and `forge coverage` pass; Slither/Aderyn findings are triaged in writing.
- `README.md` makes no production-ready claim; `SECURITY.md` and `docs/THREAT_MODEL.md` exist.
- Git history tells the story: `audit-target` tag → PoC commits → per-finding fixes → `v1.0.0-audited` tag.

### 2.3 Non-goals

- No AMM economic redesign (fee stays 0.3%, no protocol fee, no flash swaps, no permit, no multicall, no upgradeability, no governance).
- No fee-on-transfer/rebasing support; document as unsupported with tests proving the failure mode.
- No mainnet deployment. Local Anvil + optional testnet + optional mainnet-fork tests only.
- No frontend, subgraph, monitoring stack, or Chainlink integration.
- No claim of a professional audit; this is a **self-audit for portfolio purposes**, clearly disclaimed.

---

## 3. Findings inventory (verified)

Severity is assessed **as if the contracts were deployed and the Oracle were used by an integrator**. No funds are at risk in the repo itself. Calibrate honestly in the report; do not inflate.

### 3.1 Oracle

| ID | Sev | Finding | Evidence / impact | Fix | Regression test |
|---|---|---|---|---|---|
| O-01 | **High** | `isPriceManipulated` fails open: `obs.length < 2` → `false`; `timeElapsed < MIN_TWAP_PERIOD` (incl. `period = 0`) → `false` | Verified. A guard on a fresh pair or with a short period is bypassable; integrator lends against manipulated spot | Validate `period >= MIN_TWAP_PERIOD && <= MAX_TWAP_PERIOD`, `maxDeviation <= 10000`; insufficient/stale history → return `true` (fail-closed); add `isReady(pair)` | `test/exploits/OracleFailOpen.t.sol` |
| O-02 | **High** | Unbounded observations; linear scans in `consult`/`consultBoth`/`isPriceManipulated` | Verified **4.94M gas at 2,000 obs**; ~2.5k/obs; per-block updates make `consult` uncallable within days; permissionless `update` griefing | Fixed-size ring buffer (1024), `MIN_OBSERVATION_INTERVAL = 5 min`, binary search, `MAX_TWAP_PERIOD`, gas-bound test | `test/exploits/OracleObservationDos.t.sol` |
| O-03 | **High** | Stale observations accepted; `MAX_OBSERVATION_AGE` is never enforced | Verified 30-day-old TWAP returned as current; bad collateral pricing / arbitrage | Enforce freshness against latest observation; revert `STALE_OBSERVATION`; `isPriceManipulated` fails closed | `test/exploits/OracleStaleTwap.t.sol` |
| O-04 | **High** | Short history silently shortens the requested TWAP window | Verified `consult(1 days)` returns a 60s TWAP; consumer believes it has 1-day manipulation resistance | Require an anchor observation at/before `latest.timestamp - period` and `elapsed >= period`; revert `INSUFFICIENT_HISTORY` | `test/exploits/OracleShortWindow.t.sol` |
| O-05 | **High** | No pair provenance check; any contract can be registered/consulted as a pair | A fake pair can return fabricated/decreasing cumulatives; an integrator accepting a user-supplied pair can be drained | Oracle takes `factory`; validate `factory.getPair(token0, token1) == pair` in `update`/`consult`/`getSpotPriceUnsafe`; add `FakePair` PoC | `test/exploits/FakePairOracle.t.sol` |
| O-06 | **Medium** | `getSpotPrice` is spot, not TWAP; name/docs invite oracle misuse | Manipulable within a block/donation+`sync`; a naive integrator is trivially drained | Rename `getSpotPriceUnsafe`; NatSpec “never use as an oracle”; victim PoC; provide `consultScaled` | `test/exploits/DonationSync.t.sol` |
| O-07 | **Medium** | Mixed Q112.112 and 1e18 units; truncated `5192296858534827` conversion; division by zero if TWAP scales to 0 | Wrong prices at low values; precision loss; panic | One `_to1e18(x) = (x * 1e18) >> 112`; zero guard; NatSpec units; `consultScaled` | `test/Oracle.t.sol` unit tests |
| O-08 | **Medium** | `period > block.timestamp` underflows; `period = 0` accepted in `isPriceManipulated` | Panic vs. reason; fail-open | Shared `_validatePeriod`; explicit errors | `test/Oracle.t.sol` |
| O-09 | **Medium** | Token decimals ignored in 1e18 scaling | USDC(6)/WETH(18) is off by 1e12; Q112 is raw-unit | Document raw units; add `consultScaled(pair, period, baseDecimals, quoteDecimals)`; 6-decimal tests | `test/Decimals.t.sol` |
| O-10 | Low/Info | Duplicated lookup logic; dead `OBSERVATION_IN_FUTURE` check; unused `FixedPointMathLib` import | Drift risk, noise | Extract one `_twap`/`_lookup`; delete dead code | `forge lint` clean |
| O-11 | Low/Info | `update` is permissionless and unincentivized; keeper liveness risk | Stale oracle in normal operation | `updateMany`; keeper script; document operational assumption | `test/Oracle.t.sol` |
| O-12 | Low/Info | 2106 `uint32` truncation | Not actionable now | Document | — |
| O-13 | Low/Info | `isPriceManipulated` returns `true` on zero reserves but `false` on missing history — inconsistent fail mode | Confusing API | Fail closed consistently; document | `test/Oracle.t.sol` |

### 3.2 Pair / Factory

| ID | Sev | Finding | Evidence / impact | Fix | Regression test |
|---|---|---|---|---|---|
| P-01 | Medium | Dust first mint underflows with panic, not a reason | Verified; first mint with `sqrt(amount0*amount1) <= 1000` panics | Pre-check product/minimum; `require(root > MINIMUM_LIQUIDITY, "Pair: INSUFFICIENT_INITIAL_LIQUIDITY")` | `test/EdgeCases.t.sol` |
| P-02 | Low | `amount0 * amount1` / `amount * totalSupply` can overflow with >uint112 balances | Checked-math panic; malicious/rebasing token griefing | Require `amount0/1 <= type(uint112).max` before multiplying; document | `test/EdgeCases.t.sol` |
| P-03 | Low | `initialize` has no one-time guard | Factory is atomic today; defense-in-depth and future-factory safety | `require(token0 == 0 && token1 == 0, "Pair: ALREADY_INITIALIZED")` | `test/EdgeCases.t.sol` |
| P-04 | Low/Info | LP tokens donated to the pair are captured by the next `burn` caller | Known Uniswap behavior; donor loss only | Document/test | `test/EdgeCases.t.sol` |
| P-05 | Info | `swap` has an unused `data` parameter; no flash-swap callback | Misleading API | Remove `data` (only Router calls it) | compile/test |
| P-06 | Low | Read-only reentrancy: `getReserves()` returns stale reserves during `swap`/`burn` token callbacks | A victim reading reserves mid-callback can misprice | Guard external `getReserves` with `unlocked == 1`; internal `_getReserves`; test malicious token callback gets `Pair: LOCKED`; document `balanceOf`/cumulative getters | `test/exploits/ReadOnlyReentrancy.t.sol` |
| P-07 | Medium | Donation + `sync` changes reserves/cumulatives without a swap; an LP (especially a dominant LP) can manipulate the oracle cheaply | Economic oracle attack; victim using spot is drained | Threat model + PoC; mitigate with TWAP + minimum liquidity + integrator limits; document residual | `test/exploits/DonationSync.t.sol` |
| P-08 | Low/Info | `MINIMUM_LIQUIDITY = 1000` raw units is decimal-dependent | For 6-decimal tokens it is ~$0.001; first-depositor attack is cheaper | Analyze/test; document; optional scaled minimum or virtual shares (do not silently change) | `test/exploits/FirstDepositor.t.sol` |
| P-09 | Info | `skim` lets anyone send excess tokens to any address | Accidental transfers are recoverable by anyone; not an LP loss | Document/test | `test/EdgeCases.t.sol` |
| F-01 | Medium | `Factory.createPair` ignores the CREATE2 result; a failed deploy can set `getPair = 0` and push a zero address | State corruption; low likelihood but cheap to fix | `require(pair != 0 && pair.code.length > 0, "Factory: PAIR_DEPLOY_FAILED")` | `test/Factory.t.sol` |
| F-02 | Low | `createPair` accepts EOAs/non-contracts | Junk pairs, `mint` later reverts | `require(tokenA.code.length > 0 && tokenB.code.length > 0, "Factory: INVALID_TOKEN")` | `test/Factory.t.sol` |
| F-03 | Info | No protocol fee / `feeTo`; immutability is a positive | — | Document as design choice | — |
| F-04 | Low/Medium | `Router.pairFor` duplicates the CREATE2 formula; drift risk if Pair bytecode changes | Integration correctness | Add `Factory.computePairAddress`; make `Router.pairFor` read `factory.getPair` and revert `PAIR_NOT_FOUND`; consistency test | `test/Factory.t.sol` |

### 3.3 Router / WETH / Deploy

| ID | Sev | Finding | Evidence / impact | Fix | Regression test |
|---|---|---|---|---|---|
| R-01 | Medium | ETH entry points lack a reentrancy guard; external calls (refund/withdraw/send) before completion | No direct theft path found in the current API, but latent risk for future multicall/integration; be honest in the report | Global `lock` on all external state-changing functions; effects before interactions; malicious-recipient test | `test/Reentrancy.t.sol` |
| R-02 | Low | `assert` in `receive()` and `_addLiquidity` | Consumes all gas; wrong semantics | `require` with reasons | `test/RouterExtensions.t.sol` |
| R-03 | Low/Medium | Nonexistent pair calls revert with no reason / into empty addresses | Integration UX; no silent loss found because data-returning calls revert | `pairFor` via `factory.getPair` + `PAIR_NOT_FOUND` | `test/EdgeCases.t.sol` |
| R-04 | Low | `getAmountIn` panics when `amountOut > reserveOut` | Panic vs. reason | `require(amountOut < reserveOut, "Router: INSUFFICIENT_LIQUIDITY")` | `test/RouterExtensions.t.sol` |
| R-05 | Low/Info | Unbounded path length; duplicate tokens revert `IDENTICAL_ADDRESSES` | Gas griefing/user error | Document; optional `MAX_PATH_LENGTH` | `test/MultiHop.t.sol` |
| R-06 | Info | `factory`/`WETH` are storage, not immutable | Gas/clarity only | Make immutable | compile |
| W-01 | **High (operational)** | Deploy script deploys a custom `WETH9` on every chain, including mainnet | Splits liquidity; wrong WETH; catastrophic if used on mainnet | Chain-aware config: canonical WETH on mainnet/testnets, deploy WETH9 only on local; `WETH` env; assertions | `script` dry run |
| W-02 | Low/Info | `WETH9.withdraw` uses `transfer` (2300 gas) | Canonical behavior; recipients needing >2300 gas fail | Document; don't change canonical semantics without a reason | `test/RouterExtensions.t.sol` |
| W-03 | Low/Info | `WETH9.totalSupply` = contract balance; forced ETH inflates supply | Not exploitable here | Document; use canonical WETH on mainnet | — |
| D-01 | **High (operational)** | Deploy script mixes infra + test-token mint + 100 ETH liquidity seed; recipient derived from `msg.sender` inside broadcast | Dangerous on live networks; non-reproducible | Split `Deploy.s.sol` (infra only) and `SeedLocal.s.sol`; explicit recipient; balance checks; signer required | `script` dry run |
| D-02 | **High (operational)** | Seed script can run on mainnet and spend real ETH | Catastrophic | `require(block.chainid != 1)` / allowlist; `SEED_RECIPIENT`; `vm.envUint` checks | script test |
| D-03 | Low | `vm.envOr("PRIVATE_KEY", 0)` silently uses default sender; `startBroadcast()` without a key | Wrong signer / failed deploys | Require explicit `PRIVATE_KEY` or `--account`; document | script dry run |
| D-04 | Low | No post-deploy sanity checks | Misconfiguration | Assert `router.factory() == factory`, `router.WETH() == weth`, pair creation works | script test |

### 3.4 Tests / docs

| ID | Sev | Finding | Fix |
|---|---|---|---|
| T-01 | **High (portfolio)** | Baseline red: `testFailSwapExpired` | Convert to `vm.expectRevert("Router: EXPIRED")` |
| T-02 | **High** | Misleading tests (fake reentrancy test, no-assert arbitrage test, tautological fuzz, flaky gas test, opaque reverse-path math) | Triage: rewrite or delete; do not preserve “in intent” |
| T-03 | **High** | Invariant suite is weak (only `reserve <= balance`, handler swallows reverts) | Rebuild with ghost accounting, bounded handlers, `fail_on_revert`, multiple invariants |
| T-04 | **High** | No adversarial/exploit tests for the actual findings | Add `test/exploits/` + `test/adversarial/` |
| T-05 | Medium | No fork tests, real WETH, USDC 6-decimals, non-standard ERC20 | Add env-gated mainnet-fork smoke/differential tests; 6-decimal suite |
| T-06 | Medium | No CI, coverage, static analysis, gas snapshots, fmt | Add GitHub Actions + Makefile + Slither/Aderyn + coverage + snapshot |
| T-07 | Medium | Fuzz/invariant runs at defaults (256) | `[profile.ci]` with `fuzz.runs = 5000`, `invariant.runs = 1000`, `depth = 200` |
| T-08 | Low | No `forge fmt`/lint enforcement; warnings | Format once in a dedicated commit; fix high-signal lint warnings |
| DOC-01 | **High (portfolio)** | README overclaims “production-ready”, credits OpenZeppelin without importing it, misattributes overflow protection | Rewrite as a security case study; drop overclaims |
| DOC-02 | **High** | No audit report with severity/impact/PoC/remediation/verification | `docs/AUDIT_REPORT.md` |
| DOC-03 | **High** | No threat model | `docs/THREAT_MODEL.md` |
| DOC-04 | Medium | No methodology, scope, coverage, residuals, “what was not found” | Sections in the report + `docs/INVARIANTS.md` |
| DOC-05 | Medium | No security policy/contact | `SECURITY.md` |
| DOC-06 | Medium | No architecture diagrams or exploit reproduction instructions | Mermaid diagrams + README commands |
| DOC-07 | Low | No changelog/timeline/evidence | `docs/CHANGELOG.md`, `docs/evidence/` |

---

## 4. Target design (what “fixed” means)

### 4.1 Oracle: bounded, fresh, fail-closed, provenance-checked

**Data structure**

```solidity
uint256 public constant MAX_OBSERVATIONS = 1024;
uint256 public constant MIN_OBSERVATION_INTERVAL = 5 minutes;
uint256 public constant MAX_OBSERVATION_AGE = 1 hours;
uint256 public constant MIN_TWAP_PERIOD = 15 minutes;
uint256 public constant MAX_TWAP_PERIOD = (MAX_OBSERVATIONS - 1) * MIN_OBSERVATION_INTERVAL;

struct Observation {
    uint256 timestamp;
    uint256 price0Cumulative;
    uint256 price1Cumulative;
}

struct ObservationState {
    Observation[MAX_OBSERVATIONS] data;
    uint16 head;   // next write index
    uint16 count;  // min(total written, MAX_OBSERVATIONS)
}

mapping(address => ObservationState) private _observations;
```

- Logical index `i` (0 = oldest) maps to `(head + MAX_OBSERVATIONS - count + i) % MAX_OBSERVATIONS`.
- `update` appends at `head`, advances `head`, increments `count` up to `MAX_OBSERVATIONS`; when full it overwrites the oldest.
- Rate-limit: if `block.timestamp < latest.timestamp + MIN_OBSERVATION_INTERVAL`, return without writing. This bounds cardinality and update griefing.
- Parameters rationale (document in NatSpec + report):
  - 5-minute cadence × 1024 = ~85 hours of history; a 1-day TWAP is available.
  - 15-minute minimum TWAP = ~75 mainnet blocks; 1 minute (~5 blocks) is too cheap to manipulate.
  - 1-hour freshness tolerates a few missed keeper runs while bounding staleness.
  - Tunable constants; state the tradeoff (longer MIN_TWAP_PERIOD = more manipulation resistance, slower response to real moves).

**Lookup**

- Binary search over logical indices for the latest observation with `timestamp <= target`.
- If none, or if `elapsed < period`, revert `INSUFFICIENT_HISTORY`.
- If `block.timestamp > latest.timestamp + MAX_OBSERVATION_AGE`, revert `STALE_OBSERVATION`.
- Validate `period >= MIN_TWAP_PERIOD`, `period <= MAX_TWAP_PERIOD`, `period <= latest.timestamp`.
- One internal `_twap(pair, period)` shared by `consult`, `consultBoth`, `isPriceManipulated`.
- Gas bound: binary search over 1024 entries ≈ 10 SLOADs; test `consult` < 150k gas with a full ring (measured ~62k normal, ~105k under coverage instrumentation). Document the pre-fix 4.94M/2,000 obs measurement.

**Semantics**

- `consult` returns Q112.112 raw-unit price. NatSpec must say so.
- `consultScaled(pair, period)` returns 1e18-scaled price via `(twap * 1e18) >> 112`; guard zero.
- `getSpotPrice` → **rename** `getSpotPriceUnsafe`; NatSpec: “spot, manipulable, never use as an oracle”; keep a scaled helper for tests if useful.
- `isPriceManipulated`:
  - Validate `period`, `maxDeviation <= 10000`.
  - If history is insufficient/stale, return `true` (fail-closed), not `false`.
  - If `twap == 0`, return `true`.
  - Compute deviation in bps with the 1e18 conversion; no division by zero.
- Add `isReady(pair)` so integrators can distinguish “not ready” from “manipulated.” `consult` still reverts with reasons.
- `getSpotPriceUnsafe` and all Oracle entry points validate pair provenance:
  ```solidity
  address token0 = Pair(pair).token0();
  address token1 = Pair(pair).token1();
  require(token0 != address(0) && token1 != address(0), "Oracle: INVALID_PAIR");
  require(IFactory(factory).getPair(token0, token1) == pair, "Oracle: UNTRUSTED_PAIR");
  ```
  Constructor takes `address _factory`; `factory` immutable. Update deploy script and all tests.
- `updateMany(address[] calldata pairs)` for keepers; document that one invalid pair reverts the batch (or use try/catch if desired).
- `observationCount`, `getObservation(pair, i)`, `latestObservation` for tooling; no public dynamic array.
- Remove unused `FixedPointMathLib` import.

**Keep for later (document, don't implement now):** interpolating the cumulative to `block.timestamp`; a Chainlink/Uniswap-V3-style production oracle; multiple oracle sources. State that this Oracle is a reference implementation, not a production price feed.

### 4.2 Pair / Factory

- `Pair.initialize`: one-time guard (`token0 == 0 && token1 == 0`) + factory-only.
- `Pair.mint`:
  - Require `amount0 <= type(uint112).max && amount1 <= type(uint112).max` before multiplication (`Pair: OVERFLOW`).
  - First mint: `require(root > MINIMUM_LIQUIDITY, "Pair: INSUFFICIENT_INITIAL_LIQUIDITY")`; no arithmetic panic.
  - Keep `_mint(address(0), MINIMUM_LIQUIDITY)` and `liquidity > 0`.
- `Pair.getReserves`:
  - External `getReserves()` requires `unlocked == 1` (`Pair: LOCKED`), to block read-only reentrancy.
  - Internal `_getReserves()` used by `mint`/`burn`/`swap`; public behavior outside a lock unchanged.
  - Add a malicious-token test that reads reserves during a transfer callback and gets `Pair: LOCKED`.
  - Document that `balanceOf` and the public cumulative getters are still readable mid-callback; integrators must not use them during callbacks.
- `Pair.swap`: remove the unused `data` parameter (only Router calls it); update Router. Document “no flash swaps.”
- `Factory.createPair`:
  - `require(tokenA.code.length > 0 && tokenB.code.length > 0, "Factory: INVALID_TOKEN")`.
  - `require(pair != address(0) && pair.code.length > 0, "Factory: PAIR_DEPLOY_FAILED")`.
  - Add `computePairAddress(tokenA, tokenB)` public view using the CREATE2 formula; use it in tests and docs.
- `Router.pairFor`:
  - Replace the duplicated CREATE2 computation with `Factory(factory).getPair(tokenA, tokenB)`.
  - `require(pair != address(0), "Router: PAIR_NOT_FOUND")`.
  - `_addLiquidity` creates the pair first, then `pairFor` reads it.
  - Add a consistency test: `factory.getPair(a,b) == factory.computePairAddress(a,b)` plus router behavior on missing pairs (`PAIR_NOT_FOUND`). (`Router.pairFor` is `internal`, so it cannot be called from tests directly.)
- Keep `MINIMUM_LIQUIDITY = 1000` but document the decimal caveat and test the first-depositor economics; do not silently change it (compatibility + scope).

### 4.3 Router

- Add a global reentrancy mutex (custom `lock` like `Pair`, or solmate `ReentrancyGuard`) to **all external state-changing entry points**, not only ETH paths. Rationale: malicious ERC20 callbacks can also reenter; the Router is stateless today, but the guard is cheap and future-proofs multicall/integrations. Document the gas cost.
- Order effects before interactions where possible. For ETH paths:
  - `removeLiquidityETH`: burn LP → transfer token → `withdraw` → send ETH; mutex prevents reentry; the pair is already updated.
  - `swapExactTokensForETH`/`swapTokensForExactETH`: `_swap` → `withdraw` → send; mutex.
  - `addLiquidityETH`/`swapETHForExactTokens`: refund last; mutex.
- `receive()`: `require(msg.sender == WETH, "Router: NOT_WETH")`.
- `_addLiquidity`: `require(amountAOptimal <= amountADesired, "Router: ...")` instead of `assert`.
- `getAmountIn`: `require(amountOut < reserveOut, "Router: INSUFFICIENT_LIQUIDITY")` before subtraction.
- Make `factory`/`WETH` immutable.
- Validate `path.length` (>= 2; optional max 5) and document duplicate-token revert.
- Add `to != address(0)` checks? Document as user error; do not add unless tests show a real issue.
- Do **not** add `multicall`; it would enlarge the reentrancy surface for no portfolio benefit.

### 4.4 Deploy / config / CI

**Scripts**

- `script/Deploy.s.sol`: infrastructure only.
  - Chain-aware WETH: on mainnet/testnets use a configured canonical address; on local (31337) deploy `WETH9`.
  - Require an explicit signer (`PRIVATE_KEY` or `--account`); no silent default.
  - Log WETH/factory/router; assert `router.factory() == factory`, `router.WETH() == weth`.
  - No token mint, no liquidity seed, no `msg.sender`-derived recipient.
- `script/SeedLocal.s.sol`: local/testnet only.
  - `require(block.chainid != 1, "Seed: MAINNET_FORBIDDEN")` and an allowlist of chain IDs.
  - Explicit `SEED_RECIPIENT` env; validate balances; bound amounts; log.
- `.env.example`: `PRIVATE_KEY`, `MAINNET_RPC_URL`, `SEED_RECIPIENT`, `WETH_ADDRESS`; `.env` ignored.

**Foundry**

```toml
[profile.default]
src = "src"
out = "out"
libs = ["lib"]
solc = "0.8.24"          # pin; current build uses 0.8.24
optimizer = true
optimizer_runs = 200
via_ir = true
remappings = ["solmate/=lib/solmate/src/", "forge-std/=lib/forge-std/src/"]
evm_version = "paris"     # maximize chain compatibility; document

[profile.default.fuzz]
runs = 1000

[profile.default.invariant]
runs = 512
depth = 100
fail_on_revert = true

[profile.ci.fuzz]
runs = 5000

[profile.ci.invariant]
runs = 1000
depth = 200
fail_on_revert = true

[fmt]
line_length = 100
tab_width = 4
bracket_spacing = true
int_types = "preserve"
```

- Run `forge fmt` once in a dedicated commit; fix high-signal `forge lint` warnings in touched files.
- `Makefile` targets: `build`, `test`, `test-ci`, `coverage`, `fmt`, `lint`, `slither`, `aderyn`, `snapshot`, `audit`.
- `.github/workflows/ci.yml`:
  - `forge fmt --check`, `forge build --sizes`, `FOUNDRY_PROFILE=ci forge test -vvv`.
  - `forge coverage --ir-minimum --report summary --report lcov`; upload artifact.
  - Slither (`pip install slither-analyzer`) with `slither.config.json` filtering `lib/`, `test/`, `script/`; Aderyn; triage output in `docs/STATIC_ANALYSIS.md`.
  - Fork tests skipped unless `MAINNET_RPC_URL` secret is set.
- `slither.config.json`: `filter_paths`, `exclude_dependencies`, documented exclusions. Do not hide findings; explain each.
- `forge snapshot` committed; use it to show the Oracle gas improvement.

### 4.5 Test strategy

**Triage first.** Do not preserve misleading tests “in intent.”

- `Swap.t.sol`: fix `testFailSwapExpired` → `test_Revert_SwapExpired` with `vm.expectRevert("Router: EXPIRED")`. Keep happy paths.
- `SwapFuzz.t.sol`: replace the tautological comparison with an independent `AmmMathRef` (test-only) implementing the constant-product formulas; fuzz `getAmountOut`/`getAmountIn` against it; add round-trip properties.
- `MultiHop.t.sol`: delete the gas-order test (move gas to snapshot); fix the circular-arbitrage test to assert a concrete loss/profit; simplify the reverse-path assertion.
- `Invariant.t.sol`: replace with a stateful handler + multiple invariants (see below).
- `Oracle.t.sol`: rewrite for the new semantics (ring buffer, freshness, full window, fail-closed).
- Keep `EdgeCases`, `RemoveLiquidity`, `RouterExtensions`, `MarketConditions` where they add value; add assertions where weak.
- Add `test/Factory.t.sol` for CREATE2 prediction, token-code check, duplicate/identical/zero cases, `computePairAddress` consistency.

**Invariants** (`test/invariant/`):

- `invariant_reservesMatchBalances`: `reserve0 <= balance0`, `reserve1 <= balance1`.
- `invariant_lpSupplyBacked`: `MINIMUM_LIQUIDITY <= totalSupply <= sqrt(reserve0*reserve1) + 1` (fees grow `k`, so supply ≤ sqrt(k)); document rounding.
- `invariant_kNonDecreasingOnSwap`: handler records `kBefore`/`kAfter` and asserts `kAfter >= kBefore` for swaps (not for burn/mint/sync; those are separate).
- `invariant_tokenConservation`: each token's `totalSupply` equals the sum of tracked balances (pair, router, users) via ghosts.
- `invariant_routerHoldsNoFunds`: after each action, router token/ETH balances are zero (except transient within a call).
- `invariant_oracleBounded`: `observationCount <= MAX_OBSERVATIONS`; `latest.timestamp <= block.timestamp`; `consult` gas bound in a separate test.
- `invariant_cumulativeMonotonic`: `price0CumulativeLast`/`price1CumulativeLast` non-decreasing (test-range; document overflow semantics).
- `invariant_factoryConsistency`: `getPair(a,b) == getPair(b,a)`, `pair.factory == factory`, `allPairs` unique, `computePairAddress` matches.
- Handler: bounded inputs, no blind `catch`; `fail_on_revert = true`; explicitly model expected failures (e.g., zero amounts) by avoiding invalid inputs or using a separate “expected revert” handler action. Add ghost accounting.

**Exploit/regression tests** (`test/exploits/`):

1. `OracleFailOpen.t.sol` — mock `VulnerableLender` uses `isPriceManipulated` as a guard; no observations → guard says safe; attacker manipulates spot and borrows. On HEAD, assert the guard now blocks/`consult` reverts. Include the pre-fix output in `docs/evidence/`.
2. `OracleStaleTwap.t.sol` — stale observation → `consult` reverts; a naive lender cannot price.
3. `OracleShortWindow.t.sol` — 1-day request with 60s history → `INSUFFICIENT_HISTORY`.
4. `OracleObservationDos.t.sol` — fill 1024 observations; `consult` gas < 150k; `observationCount <= MAX`; pre-fix log shows 4.94M/2,000.
5. `FakePairOracle.t.sol` — fake pair returns fabricated cumulatives; `update`/`consult` revert `UNTRUSTED_PAIR`.
6. `DonationSync.t.sol` — attacker LP donates + `sync` to move spot; a lender using `getSpotPriceUnsafe` is drained; after the fix, the API is clearly named unsafe and the TWAP path is resistant within its window. Quantify the attacker cost and the victim loss.
7. `FirstDepositor.t.sol` — inflation/donation attack; quantify cost vs. victim loss for 18- and 6-decimal tokens; document the `MINIMUM_LIQUIDITY` tradeoff.
8. `ReadOnlyReentrancy.t.sol` — malicious token reads `getReserves()` during `swap`/`burn`; expect `Pair: LOCKED`; document unguarded `balanceOf`/cumulative getters.

**Adversarial tests** (`test/adversarial/`):

- Reentrancy: ERC777-style token reenters `Pair.swap` → `Pair: LOCKED`; malicious ETH recipient reenters Router → `Router: LOCKED`.
- Fee-on-transfer token: `addLiquidity`/`swap` revert or lose value; document unsupported.
- Non-standard ERC20 (USDT-like, no return data): SafeTransferLib path works.
- 6-decimal token: swaps/rounding work; Oracle scaling is documented/tested.
- Sandwich: existing victim/attacker scenario + assert attacker profit > 0 and `amountOutMin` blocks the victim loss; deadline expiry.
- `receive`: EOA send reverts; WETH withdraw succeeds.
- `initialize`: direct/second call reverts.
- CREATE2: predicted address matches; `pairFor` consistency; nonexistent pair reverts with reason.
- `skim`/`sync`: donation recovery, reserve changes, LP-token donation to pair.

**Fork/differential** (`test/fork/`, env-gated):

- Deploy the stack on a mainnet fork with canonical WETH; create a pair with a mock 6-decimal USDC; add/swap/remove; assert.
- Differential: compare `Router.getAmountsOut` to canonical Uniswap V2 `UniswapV2Router02.getAmountsOut` for the same USDC/WETH reserves; assert equality. This is a strong, independent validation of the math.
- `MAINNET_RPC_URL` optional; `vm.skip(true)` if unset. CI runs it only when the secret exists.

### 4.6 Documentation / portfolio artifacts

- `README.md` — rewrite:
  - Title + one-line thesis: “A security-focused Uniswap V2-style AMM: audit, PoCs, fixes, invariants.”
  - Findings summary table (top 5) with severity and links.
  - “What this demonstrates” mapping to skills: manual review, threat modeling, PoC development, economic analysis, invariant/fuzz testing, remediation, reporting.
  - Mermaid architecture + swap/oracle sequence diagrams.
  - Quickstart (`forge build`, `forge test`, `forge test --match-path 'test/exploits/*' -vvv`).
  - “Reproduce the audit” (tag/commit links, evidence).
  - Quality commands (coverage, slither, aderyn, fork).
  - Security properties, limitations, non-goals; no “production-ready.”
  - License.
- `docs/AUDIT_REPORT.md` — the main artifact:
  - Executive summary; scope (commit, files, LOC); methodology (manual review, threat model, static analysis, fuzzing, invariants, fork/differential); severity definitions; findings summary; detailed findings with location/impact/likelihood/root cause/PoC/recommendation/fix/verification; residual risks; “what was not found”; appendix (tool outputs, coverage, gas).
  - Each finding links to a code line, a PoC, a fix commit, and a regression test.
- `docs/THREAT_MODEL.md` — assets, actors, trust boundaries, per-entry-point abuse cases, assumptions, accepted risks (MEV/sandwich, fee-on-transfer, rebasing, read-only reentrancy for integrators, adminless, unaudited), economic attack scenarios (oracle manipulation cost, donation+sync, first depositor).
- `docs/INVARIANTS.md` — invariant definitions, handler actions, results, and why each matters.
- `SECURITY.md` — scope, self-audit disclaimer, reporting contact (GitHub security advisories), no bug bounty.
- `docs/CHANGELOG.md` — security fixes by version.
- `docs/evidence/` — pre-fix exploit logs, gas measurements, CI/coverage/static-analysis outputs. Do not commit secrets.
- Optional: a short `docs/PORTFOLIO.md` with “what I would do next” (Chainlink/TWAP design, monitoring, formal verification) to show judgment.

---

## 5. Step-by-step implementation plan

Effort estimates are indicative for one focused engineer; adjust. **MVP** = required for the portfolio; **Stretch** = valuable if time permits.

### Phase 0 — Baseline, hygiene, narrative setup (0.5 day) — MVP

1. Fix `testFailSwapExpired`; run `forge test` to green (67/67); record the baseline output.
2. Pin `solc = "0.8.24"`; add `[fmt]`, fuzz/invariant profiles; run `forge fmt` in a dedicated commit.
3. Add `docs/AUDIT_REPORT.md` and `docs/THREAT_MODEL.md` skeletons with scope/severity definitions.
4. Tag `audit-target` at the commit that represents the code under audit (after the baseline fix, before fixes).
5. Add `.env.example`; confirm `.gitignore` covers `.env`, `broadcast/`, `cache/`, `out/`.

**Exit:** green baseline, pinned toolchain, audit-target tag, skeletons committed.

### Phase 1 — Oracle: PoCs first, then rewrite (3 days) — MVP

1. Write `test/exploits/OracleFailOpen.t.sol`, `OracleStaleTwap.t.sol`, `OracleShortWindow.t.sol`, `OracleObservationDos.t.sol`, `FakePairOracle.t.sol` against the current code. Record pre-fix outputs in `docs/evidence/`. Commit on `audit/poc` and tag `poc-vulnerable`. Time-travel with ABSOLUTE warp arithmetic from a loop counter (`T0 + i * STEP`): relative `vm.warp(block.timestamp + …)` in a loop does not advance time across iterations (observed during verification — stale reads), which would silently record one observation and invalidate the test. Assert `observationCount` before every `consult` so exploit tests cannot pass/fail vacuously.
2. Rewrite `src/Oracle.sol`:
   - ring buffer + binary search + `MIN_OBSERVATION_INTERVAL`;
   - freshness + full-window validation;
   - fail-closed `isPriceManipulated` + `isReady`;
   - factory provenance + `updateMany`;
   - units/decimals docs + `consultScaled` + `getSpotPriceUnsafe`;
   - extract one `_twap`/`_lookup`; remove dead code/unused import.
3. Update `test/Oracle.t.sol` for new semantics; add a full-ring gas-bound test.
4. Re-run the five exploit tests; they must now revert/be blocked. Add regression assertions.
5. Measure `consult` gas with 1024 observations; record before/after in the report.

**Exit:** no fail-open; bounded gas; freshness/full-window enforced; fake pair rejected; all Oracle tests green; pre/post evidence captured.

### Phase 2 — Pair / Factory (1 day) — MVP

1. `initialize` guard; dust-mint reason; `uint112` pre-checks; remove unused `data`; guard `getReserves` for read-only reentrancy.
2. `Factory` CREATE2 result + token-code checks; `computePairAddress`.
3. `Router.pairFor` via `factory.getPair`; consistency test.
4. Add `test/Factory.t.sol`, `test/exploits/ReadOnlyReentrancy.t.sol`, donation/skim/initialize tests.

**Exit:** all Pair/Factory findings fixed or accepted with tests; CREATE2 consistency proven.

### Phase 3 — Router (1–1.5 days) — MVP

1. Global mutex; effects-before-interactions; `receive`/`_addLiquidity` `require`; `getAmountIn` guard; immutable `factory`/`WETH`.
2. Add `test/Reentrancy.t.sol` (malicious ERC20 + ETH recipient), nonexistent-pair/getAmountIn/receive tests.
3. Keep sandwich/deadline tests; add attacker-profit assertion.

**Exit:** reentrancy attempts revert; explicit errors; no regressions in ETH paths.

### Phase 4 — Deploy / config / CI (1 day) — MVP

1. Split `Deploy.s.sol` / `SeedLocal.s.sol`; chain-aware WETH; explicit signer; mainnet guard; post-deploy assertions.
2. Add `Makefile`, `[profile.ci]`, `slither.config.json`, `.github/workflows/ci.yml`.
3. Add `forge coverage` (with `--ir-minimum`), `forge snapshot`, Slither/Aderyn runs; triage into `docs/STATIC_ANALYSIS.md`.

**Exit:** CI green; deploy dry run on Anvil; seed script refuses mainnet; coverage/static-analysis artifacts exist.

### Phase 5 — Invariants, fuzzing, fork/differential (2 days) — MVP core + Stretch

1. Replace `Invariant.t.sol` with a bounded handler + the invariants in §4.5; run with `fail_on_revert = true`.
2. Add independent `AmmMathRef` fuzz tests; add 6-decimal, fee-on-transfer, non-standard ERC20 tests.
3. Add env-gated fork smoke + differential test vs Uniswap V2 (Stretch).
4. Add `test/exploits/DonationSync.t.sol` and `FirstDepositor.t.sol`; quantify economics (Stretch if time).

**Exit:** invariants pass at high runs; fuzz tests are independent; economic attacks documented with numbers.

### Phase 6 — Documentation and portfolio polish (1.5 days) — MVP

1. Write `docs/AUDIT_REPORT.md` from the final diff; every finding links to code/PoC/fix/test.
2. Write `docs/THREAT_MODEL.md`, `docs/INVARIANTS.md`, `SECURITY.md`, `docs/CHANGELOG.md`, `docs/STATIC_ANALYSIS.md`.
3. Rewrite `README.md`; add Mermaid diagrams, findings table, reproduction commands, “what this demonstrates,” limitations.
4. Add `docs/evidence/` logs; ensure no secrets.
5. Optional `docs/PORTFOLIO.md` with next steps.

**Exit:** a reviewer can understand the work in 15 minutes; all claims trace to evidence.

### Phase 7 — Final validation and release (0.5 day)

1. Run the full validation matrix (§6).
2. Verify every finding row has a code link, PoC, fix, and regression test.
3. Tag `v1.0.0-audited`; write release notes.
4. Optional: deploy to a testnet, verify contracts, add addresses to README (only if safe and useful).

**Exit:** clean repo, green CI, report published, tags in place.

---

## 6. Validation matrix

| Check | Command | Pass condition | When |
|---|---|---|---|
| Build | `forge build` | Clean; no errors | Every phase |
| Unit/integration | `forge test` | All green | Every phase |
| CI profile | `FOUNDRY_PROFILE=ci forge test` | All green at high fuzz/invariant runs | Phase 4+ |
| Format | `forge fmt --check` | Clean | Phase 0+ |
| Lint | `forge lint` | No high-signal warnings; triage rest | Phase 4+ |
| Coverage | `forge coverage --ir-minimum --report summary` | ≥90% lines for `src/`; document gaps | Phase 5+ |
| Static analysis | `slither . --config-file slither.config.json`; `aderyn .` | Every finding triaged in `docs/STATIC_ANALYSIS.md` | Phase 4+ |
| Gas | `forge snapshot`; full-ring `consult` test | `consult` <150k gas; no unbounded loop | Phase 1+ |
| Fork | `forge test --match-path 'test/fork/*'` with `MAINNET_RPC_URL` | Smoke/differential pass | Phase 5 (Stretch) |
| Exploits | `forge test --match-path 'test/exploits/*' -vvv` | Attacks blocked; pre-fix evidence recorded | Phase 1+ |
| Deploy | `forge script script/Deploy.s.sol --rpc-url http://localhost:8545` | Infra only; assertions pass | Phase 4 |
| Seed | `forge script script/SeedLocal.s.sol ...` | Works locally; reverts on mainnet | Phase 4 |
| Traceability | manual | Every finding: code + PoC + fix + test | Phase 6/7 |
| Secrets | `git grep -i private_key`; check `.env` ignored | None committed | Phase 7 |
| README claims | manual | No “production-ready”; all numbers reproducible | Phase 7 |

---

## 7. Portfolio packaging

**The 60-second reviewer path** (put this in the README):

1. **Findings:** 3 High / 4 Medium / several Low, with links.
2. **Proof:** `forge test --match-path 'test/exploits/*' -vvv`; pre-fix logs in `docs/evidence/`.
3. **Report:** `docs/AUDIT_REPORT.md` — severity, impact, root cause, fix, verification.
4. **Hardening:** bounded Oracle, fail-closed guards, factory provenance, router mutex, invariants, CI.

**Git narrative**

- `audit-target` tag: code under audit (baseline green).
- `poc-vulnerable` tag/branch: failing exploit tests + pre-fix logs.
- Per-finding fix commits (`fix(oracle): ... (O-01)` etc.).
- `v1.0.0-audited` tag: final, green, documented.
- Keep the report’s code links pinned to commit hashes, not `main`, so they never rot.

**Evidence to capture**

- Pre-fix: `forge test --match-path 'test/exploits/*' -vvv` output showing the attack succeeds / fail-open returns false / `consult` gas.
- Post-fix: same commands showing revert/blocked/bounded.
- Coverage summary, Slither/Aderyn output, gas snapshot, CI run link.
- A short “attack cost” table for the Oracle manipulation (liquidity, trade size, fees, hold time, victim loss). Even a spreadsheet-style table in the report is strong.

**What hiring managers look for (make it explicit)**

- Can you find real issues, not just run a linter?
- Can you prove impact with a PoC?
- Can you calibrate severity and explain tradeoffs?
- Can you fix without breaking the protocol?
- Can you test the fix (regression, invariant, fuzz)?
- Can you communicate it clearly?
- Do you know the limits of your audit?

---

## 8. Risks, decisions, open questions

| Item | Decision / risk | Mitigation |
|---|---|---|
| Oracle parameter changes | `MIN_TWAP_PERIOD` 1 min → 15 min; 5-min observation cadence; 1024 cap. Breaks existing test expectations. | Intentional security change; rewrite `Oracle.t.sol`; document rationale/tradeoffs; tag the change. |
| Ring buffer vs. public `observations` getter | Replaces the public dynamic array. The existing test does not index it. | Provide `observationCount`/`getObservation`; update integrations/docs. |
| Router global mutex | Adds ~2k gas per call; changes no semantics. | Accept; document; measure with `forge snapshot`. |
| `getReserves` lock check | External reads during a pair callback now revert. This is the point. | Internal `_getReserves`; test; document for integrators. |
| `MINIMUM_LIQUIDITY` | Unchanged for compatibility; decimal-dependent. | Document; first-depositor test; recommend a scaled minimum for low-decimal deployments. |
| Slither/Aderyn noise | False positives (timestamp, arbitrary send, reentrancy). | `docs/STATIC_ANALYSIS.md` triage; do not hide findings; explain. |
| Fork tests | Require an RPC secret; CI may skip. | Env-gated skip; local instructions; don't make CI depend on it. |
| Time budget | The full plan is ~8–10 focused days. | MVP first: baseline, Oracle + PoCs, Pair/Factory/Router fixes, report/threat model/README, CI/invariants. Cut Low/Info fixes before cutting evidence. |
| Self-audit credibility | A self-audit can look self-serving. | Clear disclaimer; publish the pre-fix code/tag and failing PoCs; state “what was not found”; invite review. |
| Production use | Not production-ready. | `SECURITY.md`, README limitations, no mainnet deploy, use canonical WETH on mainnet. |

**Implementation notes (added during execution):**

- Consult gas bound is 150k, not 100k: measured ~62k on normal runs, ~105k
  under coverage instrumentation (counters on every statement). Either is
  ~30x below the pre-fix cold-read cost and < 0.5% of the block gas limit.
- Pre-fix cold consult was never directly re-measured (in-test reads are
  warm: 161k at 2,000 obs); the 4.94M figure stands as code-consistent
  (2,000 cold SLOADs ≈ 4.2M + overhead) but the committed evidence log
  records the warm number — re-measure on a fork before citing cold.
- `consult` at small `block.timestamp` panics `0x11` on `block.timestamp -
  period` underflow while at large timestamps it silently shortens: both
  manifestations are fixed by the same full-window validation.
- `test_MultiHop_ReversePath` criticism softened: the math simplifies to a
  legitimate round-trip loss bound.
- Fork/differential tests deferred (no RPC available); math differentially
  tested against an independent in-repo reference (`AmmMathRef`) instead.
- Slither/Aderyn run in CI only (no local Python toolchain); manual
  pre-triage in `docs/STATIC_ANALYSIS.md`.
- Time-travel quirk (relative warp in loops) added to Phase 1 above.
- `forge lint` is active in this toolchain (1.8.4) and informed T-06/T-08.
- `foundry.toml` pins `solc 0.8.24` (build-verified) with default + CI
  fuzz/invariant profiles (`fail_on_revert = true` everywhere).

**Open questions (resolve before Phase 1):**

1. Is the portfolio target a **security researcher** role (audit narrative) or a **smart contract engineer** role (product narrative)? This plan assumes security researcher; if engineering, keep the fixes but de-emphasize the victim/PoC and add feature depth instead.
2. Do you want a **testnet deployment** as part of the portfolio? It adds credibility but also operational risk; local fork is sufficient for most reviewers.
3. Is there a **time budget** (e.g., one week vs. one month)? If one week, execute MVP only: baseline, Oracle rewrite + 3 PoCs, Router/Pair/Factory guards, audit report + threat model + README, CI + basic invariants.
4. Do you want **Slither/Aderyn** in CI, or is a local triage report enough? CI is a stronger signal but adds maintenance.

---

## Appendix A — Oracle ring buffer reference pseudocode

```solidity
function _at(ObservationState storage s, uint16 i) private view returns (Observation storage) {
    uint16 physical = (s.head + uint16(MAX_OBSERVATIONS) - s.count + i) % uint16(MAX_OBSERVATIONS);
    return s.data[physical];
}

function update(address pair) external {
    _validatePair(pair);
    (uint256 p0, uint256 p1, uint32 ts) = _currentCumulativePrices(pair);
    ObservationState storage s = _observations[pair];

    if (s.count > 0) {
        Observation storage last = _at(s, s.count - 1);
        if (ts < last.timestamp + MIN_OBSERVATION_INTERVAL) return;
    }

    s.data[s.head] = Observation(ts, p0, p1);
    s.head = (s.head + 1) % uint16(MAX_OBSERVATIONS);
    if (s.count < MAX_OBSERVATIONS) s.count++;
    emit ObservationRecorded(pair, ts, p0, p1);
}

function _findAtOrBefore(ObservationState storage s, uint256 target)
    private view returns (uint16 idx, bool found)
{
    if (s.count == 0) return (0, false);
    if (_at(s, 0).timestamp > target) return (0, false);
    uint16 lo = 0;
    uint16 hi = s.count - 1;
    while (lo < hi) {
        uint16 mid = (lo + hi + 1) / 2;
        if (_at(s, mid).timestamp <= target) lo = mid;
        else hi = mid - 1;
    }
    return (lo, true);
}

function _twap(address pair, uint256 period) private view returns (uint256 p0, uint256 p1) {
    if (period < MIN_TWAP_PERIOD) revert Oracle__PeriodTooShort();
    if (period > MAX_TWAP_PERIOD) revert Oracle__PeriodTooLong();
    ObservationState storage s = _observations[pair];
    if (s.count < 2) revert Oracle__InsufficientObservations();
    Observation storage latest = _at(s, s.count - 1);
    if (block.timestamp > latest.timestamp + MAX_OBSERVATION_AGE) revert Oracle__StaleObservation();
    if (period > latest.timestamp) revert Oracle__InsufficientHistory();

    (uint16 idx, bool found) = _findAtOrBefore(s, latest.timestamp - period);
    if (!found) revert Oracle__InsufficientHistory();
    Observation storage anchor = _at(s, idx);
    uint256 elapsed = latest.timestamp - anchor.timestamp;
    if (elapsed < period) revert Oracle__InsufficientHistory();

    unchecked {
        p0 = (latest.price0Cumulative - anchor.price0Cumulative) / elapsed;
        p1 = (latest.price1Cumulative - anchor.price1Cumulative) / elapsed;
    }
}
```

Notes:

- Use custom errors or consistent `require` strings; the codebase currently uses strings. Pick one and apply consistently in touched files.
- `uint16` arithmetic must be checked/cast carefully; `MAX_OBSERVATIONS` 1024 fits.
- `_validatePair` must run before any external call to `Pair`.
- `isPriceManipulated` should call a `_tryTwap`-style helper and return `true` on any validation failure.

## Appendix B — Finding → evidence map

| Finding | Pre-fix evidence | Regression test | Report section |
|---|---|---|---|
| O-01 | `isPriceManipulated` false with 0 obs / period 0 | `test/exploits/OracleFailOpen.t.sol` | H-01 |
| O-02 | 4.94M gas / 2,000 obs; unbounded count | `test/exploits/OracleObservationDos.t.sol` | H-02 |
| O-03 | 30-day-old TWAP accepted | `test/exploits/OracleStaleTwap.t.sol` | H-03 |
| O-04 | 1-day request → 60s TWAP | `test/exploits/OracleShortWindow.t.sol` | H-04 |
| O-05 | fake pair accepted | `test/exploits/FakePairOracle.t.sol` | H-05 |
| O-06 | donation+sync moves spot | `test/exploits/DonationSync.t.sol` | M-01 |
| P-06 | stale reserves during callback | `test/exploits/ReadOnlyReentrancy.t.sol` | M-02 |
| P-07 | LP manipulates oracle via sync | `test/exploits/DonationSync.t.sol` | M-03 |
| R-01 | recipient reenters ETH path | `test/Reentrancy.t.sol` | M-04 |
| F-01 | create2 failure path | `test/Factory.t.sol` | M-05 |
| T-03 | weak invariant suite | `test/Invariant.t.sol` | Appendix |

## Appendix C — Audit report template (use this structure)

```markdown
# Security Review — Swap DEX / TWAP Oracle

## 1. Executive summary
## 2. Scope
- Commit: <hash>; files: <list>; LOC: <n>; excluded: lib/, test/, script/
## 3. Methodology
- Manual review; threat model; static analysis (Slither/Aderyn); fuzzing; invariants; fork/differential; economic modeling
## 4. Severity definitions
- Critical / High / Medium / Low / Informational (impact × likelihood)
## 5. Findings summary
| ID | Severity | Title | Status |
## 6. Detailed findings
### H-01: <title>
- Severity, location, impact, likelihood, description, root cause
- PoC (test link + pre-fix output)
- Recommendation
- Fix (commit link)
- Verification (test link + post-fix output)
- Residual risk
## 7. Residual risks / accepted risks
## 8. What was not found / out of scope
## 9. Appendix
- Tool outputs, coverage, gas, invariants, timeline
## 10. Disclaimer
- Self-audit for portfolio purposes; not a professional audit; not deployed on mainnet.
```

---

## 9. One-sentence summary

**Stop polishing a DEX; start publishing an audit.** The portfolio value is the **finding → PoC → fix → verification** chain, with the Oracle as the headline and the report/README as the interface. Keep the AMM small, make the evidence rigorous, and let the git history and tests prove the work.

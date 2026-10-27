# Security Review — Swap DEX / TWAP Oracle

> Self-audit for portfolio purposes. Not a professional audit. No mainnet deployment.
> Audit target: the pre-fix tree (git tag `audit-target` to be created at release;
> pre-fix exploit outputs: `docs/evidence/phase1-pre-fix-exploits.log`).

## 1. Executive summary

A Uniswap V2-style AMM (`Pair`, `Factory`, `Router`, `WETH9`) plus a push-based
TWAP oracle (`Oracle`) was reviewed as an audit target. The AMM core is sound;
the oracle was not: it failed open with no/short/stale history, scanned an
unbounded observation array (linear gas → uncallable within days), accepted any
contract address as a price source, and mixed Q112.112 with 1e18 units. A mock
lending integrator trusting the oracle was drained in-prototype (666k debt
tokens borrowed against 100k of collateral after a 90k donation moved spot
10x), and a fabricated-price contract priced the TWAP directly.

All High findings are fixed (bounded ring buffer, freshness/full-window
validation, fail-closed guard, factory provenance, documented units) with
executable PoCs that fail on the audit target and pass on the fixed tree, plus
regression, invariant (8/8, 51k calls, 0 reverts), fuzz (independent
constant-product reference), and adversarial suites. Spot-price oracle misuse
(`getSpotPriceUnsafe`) remains exploitable by construction and is pinned as an
accepted residual with a passing drain demo. 119/119 tests green (default and CI profiles); `src/`
line coverage ~97%.

## 2. Scope

- In scope: `src/Pair.sol`, `src/Factory.sol`, `src/Router.sol`,
  `src/Oracle.sol`, `src/WETH9.sol`, `script/Deploy.s.sol`,
  `script/SeedLocal.s.sol`.
- Excluded: `lib/` (forge-std, solmate), test files (except as evidence).
- Lines of code: ~1,000 (`src/`).

## 3. Methodology

Manual review; threat model (`docs/THREAT_MODEL.md`); exploit PoCs written
against the vulnerable tree first (evidence in `docs/evidence/`); remediation;
regression + invariant + fuzz + adversarial verification; `forge lint`
pre-triage with Slither/Aderyn delegated to CI (`docs/STATIC_ANALYSIS.md`);
economic modeling of attacker cost vs victim loss for every profit claim.

## 4. Severity definitions

- **Critical**: direct, likely theft/loss of funds at scale.
- **High**: breaks a core security property (oracle integrity, availability).
- **Medium**: latent vulnerability or concretely exploitable under conditions.
- **Low / Informational**: defense-in-depth, clarity, gas, non-exploitable.

## 5. Findings summary

| ID | Severity | Title | Status |
|----|----------|-------|--------|
| H-01 (O-01) | High | Manipulation guard fails open | Fixed, PoC + regression |
| H-02 (O-02) | High | Unbounded observations: consult DoS | Fixed, gas-bound test |
| H-03 (O-03) | High | Stale observations accepted | Fixed, freshness enforced |
| H-04 (O-04) | High | Short history silently shortens TWAP window | Fixed, reverts |
| H-05 (O-05) | High | No pair provenance check | Fixed, factory check |
| M-01 (O-06) | Medium | Spot price usable as oracle | Residual (renamed unsafe + pinned) |
| M-02 (P-07) | Medium | Donation + sync manipulates spot cheaply | Mitigated via TWAP; spot residual |
| M-03 (P-06) | Medium | Read-only reentrancy on getReserves | Fixed, lock-guarded + test |
| M-04 (R-01) | Medium | Router ETH paths lack reentrancy guard | Fixed, global mutex + tests |
| M-05 (F-01) | Medium | CREATE2 result unchecked | Fixed, result + code checks |
| L-01.. | Low/Info | Dust mint panic, init guard, overflow pre-checks, asserts, getAmountIn panic, decimals, MINIMUM_LIQUIDITY scale | Fixed or documented |

## 6. Detailed findings

### H-01: manipulation guard fails open (O-01)

- Severity: High. Location: `src/Oracle.sol`, `isPriceManipulated`.
- Impact: with < 2 observations, a short window, or `period = 0`, the guard
  returned `false` — a lending integrator's safety check passed on zero data.
- Root cause: early `return false` on missing/short history.
- PoC: `test/exploits/OracleFailOpen.t.sol` (`test_GuardRejectsFreshPair`,
  `test_GuardRejectsZeroPeriod` fail pre-fix; Narrative demo
  `test_OverBorrowBlockedAfterFix` borrows 666k against 100k collateral
  pre-fix, reverts post-fix). Pre-fix log: `docs/evidence/phase1-pre-fix-exploits.log`.
- Fix: all validation failures return `true` (fail-closed) + `isReady()`.
- Verification: guard tests + healthy-borrow positive control green.
- Residual risk: none in the guard; integrators must still call it.

### H-02: unbounded observations make consult uncallable (O-02)

- Severity: High (availability). Location: `src/Oracle.sol` observations array.
- Impact: linear scans; ~2.1k gas/observation cold. Measured 161k warm
  in-test for 2,000 observations; projected ~4.2–4.9M cold — consistent with
  the 4.94M pre-fix measurement. Per-block updates (~7,200/day) exceed the
  block gas limit within days; `update` is permissionless (griefing).
- PoC: `test/exploits/OracleObservationDos.t.sol` (count hits 2,000 pre-fix).
- Fix: fixed 1,024-entry ring buffer + binary search + 5-minute minimum
  observation interval. Measured post-fix: ~62k normal runs, ~105k under
  coverage instrumentation; bound pinned at 150k (< 0.5% of block gas).
- Verification: `test_ObservationsCapped`, `test_ConsultGasBounded` green.

### H-03: stale observations accepted (O-03)

- Severity: High. `MAX_OBSERVATION_AGE` was declared, never enforced; a
  30-day-old TWAP priced as current (verified pre-fix).
- Fix: revert `Oracle: STALE_OBSERVATION` when the latest observation is
  older than 1 hour; boundary (exactly max age) accepted, +1s rejected.
- Verification: `test_StaleObservationRejected`, `test_FreshnessBoundary`.

### H-04: short history silently shortens the window (O-04)

- Severity: High. `consult(1 days)` on 60s of history returned a 60s TWAP
  (verified); with `block.timestamp < period` it panicked with `0x11` instead.
- Fix: revert `Oracle: INSUFFICIENT_HISTORY` unless an anchor at/before
  `latest - period` exists and elapsed >= period.
- Verification: `test_ShortWindowRejected`.

### H-05: no pair provenance check (O-05)

- Severity: High. Any contract implementing the getters could be registered;
  fabricated reserves priced the TWAP (verified: 1000x fabricated TWAP).
- Fix: constructor takes `factory`; every entry point requires
  `factory.getPair(token0, token1) == pair` (`Oracle: UNTRUSTED_PAIR`).
- Verification: `test_FakePairRejected`, `test_FabricatedConsultRejected`.

### M-01: spot price usable as oracle (O-06) — RESIDUAL

- `getSpotPrice` renamed `getSpotPriceUnsafe` with "never use as an oracle"
  NatSpec. A guardless spot lender is drained by donation + sync pre- AND
  post-fix (pinned by `test_GuardlessSpotLenderDrainedByDonation`: 10x spot
  move, 666k borrowed on 100k collateral). The TWAP path resists the same
  attack (`test_TwapLenderResistsDonation`). Integrators must use TWAP.

### M-02: donation + sync manipulates spot (P-07)

- A 90k donation into a 10k/10k pool moved spot 10x for ~190k total attacker
  cost vs ~476k profit against a spot lender (measured). TWAP-window
  manipulation costs scale with depth × time; see threat model. Mitigated for
  TWAP consumers; residual for spot consumers (M-01).

### M-03: read-only reentrancy (P-06)

- `getReserves()` was readable mid-swap/burn (stale reserves). Now requires
  `unlocked == 1` (`Pair: LOCKED`); internal `_getReserves` for use under
  lock. Proven by `test_MidSwapReserveReadBlocked` (malicious token probes
  mid-callback: blocked, never sees reserves; normal reads unaffected).

### M-04: router reentrancy (R-01)

- Router ETH/token paths had no mutex. Added `lock` to all 9 state-changing
  entry points (Pair-style), internal `_removeLiquidity` to avoid
  double-locking, effects-before-interactions kept. Proven by
  `test_ReentrantTokenCannotReenterPair` (`Pair: LOCKED`) and
  `test_ReentrantRecipientCannotReenterRouter`.

### M-05: factory deployment checks (F-01/F-02)

- `createPair` ignored the CREATE2 result and accepted EOAs. Now requires
  token code + pair code (`INVALID_TOKEN`, `PAIR_DEPLOY_FAILED`), plus
  `computePairAddress` as the single prediction source (router reads
  `factory.getPair` instead of duplicating the formula). Tests in
  `test/Factory.t.sol`.

### Lowlights fixed

- P-01 dust first-mint panicked `0x11`; now `INSUFFICIENT_INITIAL_LIQUIDITY`.
- P-03 `initialize` one-time guard; R-02 `assert` → `require` (`NOT_WETH`,
  `OPTIMAL_A_EXCEEDS_DESIRED`); R-04 `getAmountIn` panics → `INSUFFICIENT_LIQUIDITY`;
  P-02 `uint112` pre-checks before `sqrt` multiplication; R-03 nonexistent
  pairs → `PAIR_NOT_FOUND`; O-08 period validation; `swap` flash-swap `data`
  param removed (no callbacks); `factory`/`WETH` immutable; O-09
  `consultScaledDecimals` for 6-decimal tokens; `getSpotPrice` consistently
  unsafe-named; `MINIMUM_LIQUIDITY` decimal caveat documented + tested.

### P-08 first-depositor: attempted, unprofitable (residual documented)

- Attack attempted end-to-end: dust first deposit, 500e18 single-sided
  donation + sync, victim deposit, attacker exit. Attacker recovered ~0.5e18
  on a 500e18 outlay (loss > 99.9%); victim recovered ~99.9% of deposit
  (remainder: rounding dust, bounded by test at 0.1%). Min-leg mint pricing
  shares the donation with later depositors instead of stealing from them.
  Residual: the 1000-unit lock is ~$0.001 on 6-decimal tokens, so dust
  protection is weaker there (same test on 6-decimal rails). Not silently
  changed by design.

## 7. Residual risks / accepted risks

1. Raw spot (`getSpotPriceUnsafe`) remains manipulable — never back credit.
2. TWAP lags real moves by design; protect with deviation limits + period choice.
3. Sandwich/MEV: profitable sandwich demonstrated (+3,032 A on 20k frontrun);
   mitigate with `amountOutMin`, deadlines, private mempools.
4. Fee-on-transfer/rebasing tokens unsupported (pinned failure modes in tests).
5. `MINIMUM_LIQUIDITY` decimal-dependence (above).
6. Keeper liveness: TWAP needs updates every ≤1h or consumers see STALE.

## 8. What was not found / out of scope

- No admin keys, upgradeability, or protocol fee exist to abuse (verified by
  absence in `src/`).
- No mainnet-fork differential vs canonical Uniswap V2 (no RPC available;
  math differentially tested against an independent reference instead).
- Slither/Aderyn not run locally (no Python toolchain in this environment);
  CI runs them; manual lint pre-triage in `docs/STATIC_ANALYSIS.md`.
- No formal verification; invariant suite (8/8) is the executable substitute.

## 9. Appendix

- PoC evidence: `docs/evidence/phase1-pre-fix-exploits.log` (7 secure-expectation
  tests fail pre-fix, 2 theft demos succeed), `docs/evidence/phase5-exploit-measurements.log`.
- Coverage: `src/` ~97% lines (Factory 95.5%, Oracle 95.7%, Pair 100%,
  Router 100%, WETH9 77.8%).
- Gas: `.gas-snapshot`; consult ~62k normal / ~105k under coverage instrumentation.
- Invariants: `docs/INVARIANTS.md`. Static analysis: `docs/STATIC_ANALYSIS.md`.
- Timeline: baseline → PoCs → Oracle rewrite → Pair/Factory → Router →
  deploy/CI → invariants/fuzz/adversarial → docs.

## 10. Disclaimer

Self-audit for portfolio purposes. Not a professional audit. The code is not
deployed on mainnet and is not production-ready without a professional review.

# Changelog

## Unreleased (post `audit-target`)

Security hardening for the portfolio self-audit. No commits published yet;
changes below are the working-tree diff, grouped for the planned per-finding
commits (`fix(oracle|pair|factory|router|deploy|tests|docs): ...`).

### Fixed (High)

- Oracle guard fails open → fail-closed + `isReady` (O-01).
- Oracle unbounded observations → 1024 ring + binary search + 5-min cadence (O-02).
- Oracle stale observations → 1h freshness enforcement (O-03).
- Oracle short-window silent shortening → `INSUFFICIENT_HISTORY` (O-04).
- Oracle fake-pair acceptance → factory provenance on all entries (O-05).

### Fixed (Medium)

- Router ETH paths unguarded → global mutex (R-01).
- `Pair.getReserves` mid-callback reads → `LOCKED` guard (P-06).
- `Factory.createPair` unchecked CREATE2 / junk tokens → result + code checks (F-01/F-02).
- Router duplicated CREATE2 formula → reads `factory.getPair` (F-04).
- `getSpotPrice` oracle misuse → renamed `getSpotPriceUnsafe` (O-06).

### Fixed (Low)

- Dust first-mint panic → `INSUFFICIENT_INITIAL_LIQUIDITY` (P-01).
- `initialize` re-init → `ALREADY_INITIALIZED` (P-03).
- `assert` → `require` in `receive`/`_addLiquidity` (R-02).
- `getAmountIn` underflow panic → `INSUFFICIENT_LIQUIDITY` (R-04).
- `uint112` overflow pre-checks in `mint` (P-02).
- Nonexistent pairs → `PAIR_NOT_FOUND` (R-03).
- `factory`/`WETH` immutable (R-06); `swap` flash-swap `data` removed (P-05).

### Added

- `test/exploits/`: OracleFailOpen, OracleStaleTwap, OracleShortWindow,
  OracleObservationDos, FakePairOracle, ReadOnlyReentrancy, DonationSync,
  FirstDepositor (+ `VictimLender` harnesses).
- `test/adversarial/`: NonStandardTokens (fee-on-transfer, no-return,
  6-decimal), SandwichProfit, `test/Reentrancy.t.sol`.
- `test/Factory.t.sol`, `test/Scripts.t.sol`; rebuilt invariants (8/8) and
  independent-math fuzz (`AmmMathRef`).
- `script/SeedLocal.s.sol` (guarded seeding); chain-aware `Deploy.s.sol`;
  Makefile; CI; Slither config; gas snapshot.
- Docs: audit report, threat model, invariants, security policy, this changelog.

### Residuals (documented, not changed)

- Spot misuse drainable by construction; TWAP lag; MEV/sandwich;
  fee-on-transfer unsupported; keeper liveness; 6-decimal lock scale.

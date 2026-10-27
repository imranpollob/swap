# Threat Model — Swap DEX

## Assets

1. Pooled tokens in each `Pair` (LP + trader funds).
2. LP shares (claim on reserves + accumulated fees).
3. TWAP integrity (any integrator pricing off the oracle).
4. Deployment correctness (right WETH, router, factory wiring).

## Actors

- **LPs**: add/remove liquidity; first depositor sets initial price.
- **Traders**: swap; set slippage/deadlines (or fail to).
- **Keeper**: anyone calling `Oracle.update` (permissionless, unincentivized).
- **Integrators**: lending protocols reading TWAP/spot (victim class).
- **MEV searchers**: sandwich/frontrun traders (demonstrated profitable).
- **Malicious token issuers**: fee-on-transfer, reverting, callback tokens.

## Trust boundaries / assumptions

- No admin keys, no upgradeability, no protocol fee, no multisig: the
  contracts are immutable; trust is in code + deployment parameters only.
- Solidity 0.8 checked arithmetic (not Solmate) provides overflow protection.
- Integrators must treat TWAP as manipulation-*resistant*, never
  manipulation-*proof*; spot as fully manipulable.
- Keeper liveness assumed: TWAP consumers must tolerate STALE reverts after
  1h without updates.

## Per-entry-point abuse cases

| Entry point | Abuse | Status |
|---|---|---|
| `Pair.mint` | Dust first-mint panic; overflow inputs | Fixed (reason + uint112 gate) |
| `Pair.swap` | K bypass via fee-on-input tokens | Documented unsupported (pinned revert) |
| `Pair.burn` / `skim` / `sync` | Mid-callback stale reads | Fixed (LOCKED guard); skim documents donation recovery |
| `Pair.getReserves` | Read-only reentrancy | Fixed (LOCKED guard) |
| `Factory.createPair` | Junk tokens; failed CREATE2 corrupting registry | Fixed (code + result checks) |
| `Router` ETH paths | Reentrant recipient / malicious token | Fixed (global mutex) |
| Router views (`pairFor`) | Nonexistent pair confusion | Fixed (`PAIR_NOT_FOUND`) |
| `Oracle.update` | Permissionless griefing (unbounded array) | Fixed (ring + 5-min cadence) |
| `Oracle.consult*` | Stale/short-window/fake-pair pricing | Fixed (freshness, window, provenance) |
| `isPriceManipulated` | Fail-open guard | Fixed (fail-closed + isReady) |
| `getSpotPriceUnsafe` | Oracle misuse | Residual: name + docs + pinned drain |
| `Deploy.s.sol` | Wrong WETH on mainnet; silent signer | Fixed (chain-aware WETH, required key, assertions) |
| `SeedLocal.s.sol` | Real-ETH seeding on mainnet | Fixed (mainnet + allowlist guards) |

## Economic attack scenarios (measured)

- **Donation + sync vs spot lender**: 90k donation into 10k/10k pool → 10x
  spot → 666k borrowed on 100k collateral (~476k attacker profit). TWAP
  lender unaffected (same test file).
- **Single-tx spot pump vs guarded lender (no history)**: 100k swap into
  10k/10k pool → guard fail-open pre-fix (drain); blocked post-fix.
- **Sandwich**: 20k frontrun / 10k victim / backrun → +3,032 attacker profit
  (~15%), victim gets less than on a clean pool (pinned both sides).
- **First depositor**: dust + 500e18 donation → attacker nets ~0.5e18
  (unprofitable by construction); victim whole. Weaker lock on 6-dec tokens
  (documented).
- **Oracle manipulation cost**: moving TWAP k× over period P costs
  ~sustained depth × P in locked capital + fees; quantified per-deployment,
  not in code.

## Accepted risks

MEV/sandwich (user-set slippage/deadlines); fee-on-transfer and rebasing
tokens (unsupported, pinned); read-only `balanceOf`/cumulative getters
mid-callback (integrators must use TWAP); keeper liveness; 6-decimal lock
scale; no professional audit (disclaimed).

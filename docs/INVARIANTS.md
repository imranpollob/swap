# Invariants — what is checked and why

Handler: `test/Invariant.t.sol::Handler`. It is the only minter, all LP goes
to itself, invalid inputs are skipped explicitly (never swallowed —
`fail_on_revert = true` in `foundry.toml`). Fuzz: 1,000 runs / 200 depth in
CI; 512/100 locally. Result: 8/8 green, ~51k calls, 0 reverts.

| Invariant | Why it matters |
|---|---|
| `reservesMatchBalances` (equality) | Any silent donation/theft breaks reserve accounting. Equality (not ≤) because no donation path exists in the handler. |
| `lpSupplyBacked` (`supply ≤ sqrt(k)+1`) | Fees grow k without minting; supply must never exceed sqrt(k). Catches mint-math bugs. |
| `kNonDecreasingOnSwap` | The 0.3% fee invariant: swaps must not drain value. Ghost k sampled around each swap. |
| `tokenConservation` | Total supply == pair + router + handler balances, cross-checked against ghost mint counters. Catches mint/burn accounting bugs. |
| `routerHoldsNoFunds` | Router must be a pass-through (tokens + ETH). Catches stuck-fund regressions. |
| `oracleBounded` | Observations capped at 1,024; never from the future. Pins O-02 structurally. |
| `cumulativeMonotonic` | Pair cumulatives never decrease (checked against per-action snapshots). TWAP math depends on it. |
| `factoryConsistency` | Pair symmetry, factory link, CREATE2 prediction match, no rogue pairs. Pins F-04 drift. |

Handler actions: `addLiquidity` (dust-guarded, mirrors router math),
`removeLiquidity` (pro-rata rounding guarded), `swap` (skips empty pools and
zero-quote outputs), `elapse` (1s–1h warp), `oracleUpdate`.

# Static Analysis Triage

> Slither/Aderyn run in CI (`.github/workflows/ci.yml`, config
> `slither.config.json` filtering `lib/`, `test/`, `script/`). They were not
> available in the local environment (no Python toolchain), so this file is a
> manual pre-triage of the `forge lint` findings plus the detector classes CI
> will raise. Every item below must be re-checked against real tool output;
> do not treat this file as a substitute for it.

## forge lint (local, verified)

- `inconsistent-type-names` (136, mostly pre-existing `uint` shorthand):
  accepted repo style; touched files use explicit `uint256` in new code.
- `block-timestamp` (2): TWAP/oracle + deadlines inherently use timestamps;
  manipulation resistance comes from the window, not the clock. Accepted.
- `calls-loop` (4): `updateMany` (bounded by caller, all-or-nothing by
  design), DoS-test fill loop (test-only), `_swap` path loop (caller-funded,
  path length bounded by caller gas). Accepted with documentation.
- `require-revert-in-loop` (8): input validation in loops; no state change
  before revert. Accepted.
- `divide-before-multiply` (2): TWAP division and deviation math; precision
  analyzed in report (Q112 intermediate, 1e18 output). Accepted.
- `unsafe-typecast` (6): `uint32(block.timestamp)` truncations (2106 horizon,
  documented), `uint16` ring indices (bounded < 1024). Accepted.
- `unused-return` (4): return values intentionally unused at call sites.
  Accepted.
- `solmate-safe-transfer-lib` (18): no-code-token silent success — known
  library property; relevant only for nonexistent pairs, which now revert
  with `PAIR_NOT_FOUND` before any transfer. Mitigated.
- `missing-zero-check` (8): `to`/`recipient` params are user-controlled
  destinations (burning to zero is user error, documented); `WETH`/`factory`
  set once in constructor + sanity-checked in deploy script. Accepted.
- `missing-events-access-control` (1, `balanceOf`): LP balances gate nothing;
  no access-control role exists. Not applicable.

## Expected Slither/Aderyn classes (for CI confirmation)

- `reentrancy-eth` (5, WETH withdraw + ETH sends): mutex-guarded; flagged
  sites are post-state-change sends with success checks. To confirm.
- `arbitrary-send-eth` (3): destinations are caller-specified (`to`) or
  refunds — by design; to confirm no fixed-address assumption.
- `reentrancy-no-eth` (8+1): pair lock + router mutex cover these; the
  Factory one is `initialize` (factory-only, one-time). To confirm each.
- `reentrancy-events` (4): events after external calls are logging only;
  no control flow depends on them. To confirm.
- `timestamp` / `tx-origin` (if any): no tx.origin use; timestamps as above.
  To confirm.

## Rule

No finding is hidden: each CI finding gets a row here (false positive with
reason, or fix + regression test) before release tagging.

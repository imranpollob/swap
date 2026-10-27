# Security Policy

## Scope

This repository is a **self-audit portfolio project**: a Uniswap V2-style AMM
plus TWAP oracle hardened with executable exploits, fixes, and verification.
It is **not production-ready** and has **not** had a professional audit.

## Reporting a vulnerability

If you find a security issue in this code, please report it via
[GitHub Security Advisories](https://docs.github.com/en/code-security/security-advisories)
on this repository. Do not open a public issue for undisclosed vulnerabilities.

- No bug bounty is offered (portfolio project, no mainnet deployment).
- Please include: affected contract/function, impact, and a Foundry PoC if
  possible — the repo's `test/exploits/` layout is the preferred format.

## Security properties (enforced by tests)

- Oracle: bounded ring, freshness ≤ 1h, full-window validation, fail-closed
  guard, factory provenance. See `docs/AUDIT_REPORT.md`.
- Pair/Router: reentrancy mutexes, read-only reentrancy guard on reserves,
  explicit errors instead of panics/asserts.
- Deploy: chain-aware WETH, explicit signer, mainnet seed refusal.

## Known residual risks

See `docs/AUDIT_REPORT.md` §7: spot misuse, TWAP lag, MEV/sandwich,
fee-on-transfer tokens, keeper liveness, 6-decimal lock scale.

# PortManager Reliability Implementation Plan

> Execute inline using superpowers:executing-plans and test-driven-development. The user approved all fixes and optimizations from the preceding audit; no further design approval is required.

**Goal:** Correct eject diagnostics, subprocess hangs, process targeting, network measurements, preset monitoring and history restoration; reduce unnecessary polling and bound caches.
**Architecture:** Keep SwiftUI views, MainActor stores and Sendable services. Share eject UI, use native process identity, serialize refresh requests, and retain bounded snapshot state.
**Tech Stack:** Swift 6 / SwiftPM / macOS 15 / CLT, no dependencies.
**Spec:** The audit and user's “전부다 진행해줘” in this conversation.

## Constraints
- Work in the current shared checkout; leave changes reviewable without automatic commit, push or merge.
- Tests use `make test` / in-binary `--selftest`. Never initialize notifications in bare-binary selftests.
- Keep separate environment objects and constant MenuBarExtra binding.
- Do not terminate real user processes or eject real disks during verification.

## Tasks
- [x] 1. Subprocess execution and blockers: add stderr flood, timeout/cancellation and live owned-file regression tests; drain both streams, bound execution and request command fields.
- [x] 2. Measurements: add fixtures for VPN columns, IPv6 DNS, full connection identity, zero socket rates and duplicate PID listeners; correct parsing and aggregation.
- [x] 3. History and presets: add multi-day/limit/clear and listener-only tests, initial snapshot and rule-change tests; restore recent history and evaluate rules independently of diff events.
- [x] 4. Safe actions: test protected/mismatched identities without sending signals and injected unmount/eject ordering; revalidate identity and share eject UI, with async blockers and whole-device unmount.
- [x] 5. Polling and caches: test coalesced refresh, option changes, cancellation, paused polling, idle bandwidth collection and disappeared counter keys; serialize refreshes, propagate cancellation, cache network metadata for 30s and bound icon caches.
- [x] 6. Review and verification: run `make test`, `make build`, inspect the diff, obtain a read-only code review, fix material findings and update relevant documentation.

## Review focus
- Timeout must work when either output pipe fills or descriptors remain inherited.
- Safety checks must fail closed when process identity cannot be verified.
- Data collected with old options must not replace a newer request.
- Zero measured traffic must not fall back to unrelated process traffic.
- Menu bar and main window must report eject failures consistently.

## Progress
Baseline: previous `make test` passed 30 checks. Working tree was clean at implementation start.

Implementation evidence: initial five regressions failed, then passed. Added shell timeout/cancellation, multi-day history, identity and eject-order checks, snapshot/rule-change checks, stale-options and metadata-cache checks. Paused-store regression caught init observers scheduling unwanted collectors; guarded initialization before re-running.

Independent read-only review found two important nettop parsing gaps (IPv6 dot-port syntax and blank idle-listener counters), plus cancel/restart overlap in RefreshGate. Four regression checks reproduced the failures before fixes. Parsing now preserves IPv6 scopes, spaced process names and idle zero measurements; cancelled collectors retain gate ownership until they return. Added an end-to-end parser/rate/alert zero check and malformed-connected-counter coverage.

Final verification: `make test` passed 81 checks with zero failures; `make build` completed the release build and app packaging; `git diff --check` passed. Logs are in `.build/reliability-final-tests.log` and `.build/reliability-final-build.log` (local ignored artifacts).

Native app QA: opened the release `.app` in a separate owned instance and inspected the real port table, Docker labels and refreshed data (54 listeners in the final snapshot). The owned instance used 0.4% CPU at the observed sample; this is an observation, not a benchmark. Screenshot/accessibility capture succeeded. Automated sidebar clicks were blocked by `window_not_focused` even after the supported restore retry, so navigation and action-dialog visual QA remain unverified. No real user process was terminated and no real disk was ejected; action safety was verified using identity checks and injected operations. Only owned QA instances were closed.

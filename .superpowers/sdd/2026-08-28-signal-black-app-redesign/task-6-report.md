# Task 6 report — Savings root and server-backed goal targets

## Outcome

Implemented Savings goal-target decoding and request bodies, redesigned the
Savings root and account management UI with Signal components, and carried the
account-request completion guard through the global and Activity presenters.
Existing savings entry and recurring endpoints and mutation flows remain in
place.

## Changes

- Extended `SavingsAccount` with optional `targetAmountCents`, `targetDate`,
  `goalStatus`, `progressPct`, and `remainingCents` fields. The progress field
  is `Double?` because the Server may return fractional percentages.
- Added optional target fields to account create and patch bodies. PATCH uses
  explicit JSON nulls so clearing a goal removes old target metadata rather
  than silently omitting it.
- Added `SavingsGoalTests` for target/flexible decoding and create/patch body
  encoding, registered in the test target.
- Rebuilt the Savings root around total balance, this-month movement, account
  objects, recent entries, cold-start pulse loading, and cached-data recovery
  messaging.
- Added `SavingsGoalCard` to display server-owned progress, remaining amount,
  target date, and funded state. Flexible accounts omit the progress track.
- Added optional target amount/date controls to account create/edit. A blank
  target amount sends a flexible-account update; clearing an existing target
  sends explicit nulls.
- Added account request generation/settled markers to `SavingsVM` and required
  them in Savings, Activity, and global quick-action entry presenters so
  retained same-workspace accounts cannot open an entry sheet before the
  current accounts request settles.
- Updated Signal redesign source checks for goal fields, card wiring,
  presenter guards, and test registration.

## TDD / verification

The requested XCTest file was written first. Direct XCTest execution and
Xcode type-checking are unavailable in this environment (`XCTest` is not
provided by the command-line Swift toolchain); the agreed manual Xcode gate
remains deferred. A standalone Foundation harness exercised the same decode
and request-body behavior and passed.

```text
Savings goal harness passed
```

| Command | Result |
| --- | --- |
| `swiftc -parse` on all changed Savings, presenter, and test Swift files | pass |
| `bash scripts/check-signal-redesign.sh` | pass |
| `bash scripts/check-app-source-regressions.sh` | pass |
| `ruby scripts/test-testflight-workflow.rb` | pass |
| `git diff --check` | pass |

## Scope notes

No Server files were modified. The pre-existing untracked
`.superpowers/brainstorm/` directory was preserved and not staged.

## Concerns

Full SwiftUI type-checking, XCTest execution, simulator verification, and
manual appearance/accessibility checks remain deferred to the agreed manual
build stage. The recurring and entry sheets already used Signal rows and were
left endpoint-compatible.

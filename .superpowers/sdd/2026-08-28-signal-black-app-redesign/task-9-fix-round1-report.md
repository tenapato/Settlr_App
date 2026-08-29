# Task 9 fix round 1 report

Addressed review findings without changing split endpoints or QR behavior.

## Fixes

- Result settlement actions now require an owner context, a closed split, and organizer-paid mode. Open organizer-paid results show finish-claiming/lock guidance instead.
- Result and detail mutation errors include an inline retry message.
- Each-own “everyone else” amount now sums guest participant shares, keeping unclaimed money separate.
- Unavailable payer results show review guidance only: no participant balances, monetary summary, unclaimed amount, or settlement/share footer.
- Scan-flow queued completion uses `Theme.buttonInk` for adaptive primary-button contrast.

## Checks

- `./scripts/check-signal-redesign.sh` — passed.
- `./scripts/check-app-source-regressions.sh` — passed.
- `swiftc -frontend -parse` on changed Swift sources/tests — passed.
- `git diff --check` — passed.

Per the task brief, no `xcodebuild` or XCTest invocation was run.

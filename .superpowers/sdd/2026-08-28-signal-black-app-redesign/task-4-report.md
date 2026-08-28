# Task 4 report — Home hierarchy and available balance

## Outcome

Implemented the Signal Home pass on the existing `feat/signal-black-redesign-spec` branch. Home now leads with the workspace header, available-this-month amount, income/spending/saved movement, the existing insight ticker, and compact recent activity. The existing ticker implementation and its interaction mechanics were left unchanged.

## Changes

- Added optional `SummaryResponse.savingsNetCents`, defaulting to zero for legacy payloads.
- Added `SummaryResponse.availableCents` as `netCents - savingsNetCents`.
- Preserved the last successful summary when a refresh fails, recording `lastUpdated` and showing an inline retry card over retained content.
- Selected `SettlrPulseLoadingView` only for a cold Home load and `SignalTraceLoadingView` during refresh with cached content.
- Replaced the previous dashboard card/gradient hierarchy with adaptive Signal tokens and the approved Home section order.
- Registered `DashboardSummaryTests.swift` in the App test target and added Task 4 source checks.

## TDD / verification

RED: added the decoding/arithmetic XCTest contract and Task 4 source checks before implementation; `bash scripts/check-signal-redesign.sh` exited 1 because `availableCents` and Task 4 wiring were absent.

GREEN and regression checks:

```text
swiftc Settlr/Models/DashboardSummary.swift /private/tmp/main.swift -o /private/tmp/dashboard-summary-harness && /private/tmp/dashboard-summary-harness
DashboardSummary harness passed

swiftc -parse (all changed Task 4 Swift files)   PASS
bash scripts/check-signal-redesign.sh            PASS
bash scripts/check-app-source-regressions.sh    PASS
ruby scripts/test-testflight-workflow.rb         PASS
git diff --check                                 PASS
```

Per task instructions, `xcodebuild` and XCTest were not run.

## Scope notes

Only Task 4 App source, test, script, project registration, and report files were changed. No Server files were touched, and the pre-existing untracked `.superpowers/brainstorm/` directory was not staged.

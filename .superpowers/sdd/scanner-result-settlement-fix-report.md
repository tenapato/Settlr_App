# Scanner result settlement-context fix

## RED

Added `scripts/check-scanner-result-settlement.sh` before the production fix.
Against the pre-fix source it exited `1` with:
`Scanner-created results must receive workspaceId, split ID, and the existing VM.`

## GREEN

Passed after wiring the existing scanner `BillSplitVM`, workspace ID, and
created split ID into `SplitResultView`:

- `sh scripts/check-scanner-result-settlement.sh`
- `swiftc -frontend -parse Settlr/Views/Main/Split/SplitScanFlow.swift Settlr/Views/Main/Split/SplitResultView.swift Settlr/ViewModels/BillSplitVM.swift`
- `sh scripts/check-category-feature-gate.sh`
- `sh scripts/check-dashboard-month-state.sh`
- `sh scripts/check-activity-stale-warning.sh`
- `sh scripts/check-signal-redesign.sh`
- `sh scripts/check-app-source-regressions.sh`
- `git diff --check`

The guard verifies that closed organizer-paid results alone expose settlement
controls, open organizer-paid results stay gated until claiming closes,
each-own/unavailable modes stay excluded, and mutation responses are adopted
through `vm.detail`. It also protects presentation-only pass-around and queued
offline results.

## Limitation

Xcode/XCTest were not run per task constraints. The focused regression is an
executable source guard because this checkout has no runnable non-Xcode SwiftUI
test harness; it checks the production call-site and capability contracts.

## Files

- `Settlr/Views/Main/Split/SplitScanFlow.swift`
- `scripts/check-scanner-result-settlement.sh`
- `.superpowers/sdd/scanner-result-settlement-fix-report.md`

# Home snapshot month rollback fix

## RED

Added `scripts/dashboard-month-state-regression.swift` and its no-Xcode runner
`scripts/check-dashboard-month-state.sh` before adding the production helper.
The runner failed as expected because `Settlr/Models/DashboardMonthState.swift`
did not yet exist. The regression specifies cached snapshot rollback, first-load
failure retention, and protection against superseded requests.

## GREEN

`bash scripts/check-dashboard-month-state.sh` passed after implementing the pure
transition helper and wiring it into `DashboardVM.load`.

Additional verification passed:

- `swiftc -parse Settlr/Models/DashboardMonthState.swift Settlr/ViewModels/DashboardVM.swift Settlr/Views/Main/Dashboard/DashboardView.swift scripts/dashboard-month-state-regression.swift`
- `bash scripts/check-signal-redesign.sh`
- `bash scripts/check-app-source-regressions.sh`
- `bash scripts/check-category-feature-gate.sh`
- `git diff --check`

Xcodebuild and XCTest were not run per task constraints. The standalone Swift
regression runner provides executable coverage without Xcode.

## Files

- `Settlr/Models/DashboardMonthState.swift`: pure failure-transition decision.
- `Settlr/ViewModels/DashboardVM.swift`: records the last successful month,
  restores it only for a current failed request with cached data, and suppresses
  the rollback-triggered reload.
- `Settlr/Views/Main/Dashboard/DashboardView.swift`: consumes the month-specific
  suppression token before starting month-change work.
- `Settlr.xcodeproj/project.pbxproj`: registers the helper in the app target.
- `scripts/dashboard-month-state-regression.swift` and
  `scripts/check-dashboard-month-state.sh`: focused executable regression check.

## Self-review

- Current and previous summaries remain committed together on successful loads.
- Failed cached loads restore the visible picker month; first-load failures keep
  the requested month.
- Existing generation and selected-month guards remain in both success and error
  paths, so stale requests cannot roll back newer selections.
- Rollback suppression is keyed to the restored month, avoiding an onChange
  reload loop and preventing a later different month from being swallowed.
- Only task files are intended for the commit; `.superpowers/brainstorm/` was
  left untouched.

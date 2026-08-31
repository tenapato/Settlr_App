# Activity stale-data warning fix report

## Status

Implemented and verified.

## Implementation

- Added one `SignalRefreshWarning` at the top of Activity's retained timeline content.
- The warning says saved Activity data remains visible but may be out of date and includes the aggregate underlying refresh error in its accessible message.
- Retry reruns the feature-aware `ActivityVM.load` with the current user and `refreshSession` callback.
- Timeline and attention content remain visible; the existing empty-data full error state is unchanged.

## RED/GREEN evidence

- RED: `sh scripts/check-activity-stale-warning.sh` exited `1` with `Activity timeline must render exactly one retained-data refresh warning.` against the pre-fix source.
- GREEN: `scripts/check-activity-stale-warning.sh` exited `0` with `Activity retained-data warning regression check passed.` after the implementation.
- `swiftc -frontend -parse Settlr/Views/Main/Activity/ActivityView.swift` passed.
- `scripts/check-category-feature-gate.sh` passed.
- `sh scripts/check-dashboard-month-state.sh` passed (the existing dashboard script is not executable, so it was invoked through `sh`).
- `scripts/check-signal-redesign.sh` passed.
- `scripts/check-app-source-regressions.sh` passed.
- `git diff --check` passed.

## Files

- `Settlr/Views/Main/Activity/ActivityView.swift`
- `scripts/check-activity-stale-warning.sh`

## Self-review and limitation

The source guard checks the single warning placement, retained-data/staleness copy, underlying error interpolation, feature-aware retry/session refresh path, and shared accessible warning label. A real XCTest or Xcode build was not run because the task explicitly disallows Xcode/XCTest execution; Swift frontend parsing and executable source guards cover the available verification boundary.

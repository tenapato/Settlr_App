# Task 5 report — Unified Activity Signal timeline

## Outcome

Implemented the unified Activity ledger on the existing
`feat/signal-black-redesign-spec` branch. Activity now composes expenses,
income, savings movement, and completed/open bill-split state into one
chronological Signal timeline while preserving existing endpoint paths and
feature gates.

## Changes

- Added `Settlr/Models/ActivityEvent.swift`:
  - `ActivityEventKind`, `ActivityEvent`, `ActivityFilter`, and
    `ActivityPeriodFilter`.
  - Pure `ActivityComposer` with stable event IDs, semantic amount signs,
    date ordering, open-split attention, and completed-split de-duplication.
- Added `Settlr/ViewModels/ActivityVM.swift`:
  - Uses independent `async let` fetches for expenses, income, savings
    entries/accounts, bill splits, categories, and cards.
  - Skips every resource whose feature is unavailable, retaining cached arrays
    during refresh and invoking the existing session refresh callback when a
    feature-bearing 403 is returned.
  - Exposes type/period/category/payment-source filtering and reset state.
- Replaced `ActivityView`'s segmented ledger with the Signal timeline:
  compact type/period chips, filter sheet, open-split attention, day groups,
  spine/nodes, newest-event pulse, adaptive loading/empty/error states, and
  detail routing for expenses, income, savings accounts, and splits.
- Updated `MainTabView` so bill-splits-only Activity users reach the unified
  Activity screen instead of the legacy split list.
- Added adaptive semantic tokens to `TransactionDetailSheet` while preserving
  its existing edit and endpoint behavior.
- Registered new app/test sources and added Task 5 source guards.
- Added `SettlrTests/ActivityEventTests.swift` for mixed ordering, split
  de-duplication, and open-split attention behavior.

## TDD / verification

RED: added the Activity test contract and source guards before production
implementation; `bash scripts/check-signal-redesign.sh` exited 2 because the
new files did not exist.

Foundation harness:

```text
CLANG_MODULE_CACHE_PATH=/private/tmp/swift-module-cache \
  swiftc ActivityEvent.swift Expense.swift Income.swift Savings.swift BillSplit.swift \
  /private/tmp/activity-stub.swift /private/tmp/main.swift \
  -o /private/tmp/activity-harness && /private/tmp/activity-harness
Activity composer harness passed
```

The App target XCTest suite and Xcode build were intentionally not run per the
task brief.

## Checks

| Command | Exit |
| --- | ---: |
| `swiftc -parse` (all changed Task 5 Swift files) | 0 |
| `bash scripts/check-signal-redesign.sh` | 0 |
| `bash scripts/check-app-source-regressions.sh` | 0 |
| `ruby scripts/test-testflight-workflow.rb` | 0 |
| `git diff --check` | 0 |

## Scope notes

No Server files were touched. The pre-existing untracked `.superpowers/brainstorm/`
directory remains untouched and unstaged.

## Concerns

Full Xcode type-check, XCTest execution, simulator verification, and VoiceOver
manual checks remain deferred to the agreed manual-build stage.

## Fix Round 1

- Activity now owns Expense, Income, and Savings form sheets while visible;
  category/account preloads run without switching tabs, and root presenters stay
  inactive on the Activity tab so a form is presented once.
- Feature revocation immediately clears gated cached arrays and invalid type,
  category, and payment-source selections before the replacement load.
- Generic Card filtering recognizes events whose payment source is a server
  card ID, including when the card list request fails; card-specific filters
  remain available when the list succeeds and disappear when credit cards are
  disabled.
- Timeline amounts now live on the context line, and split-derived expenses
  preserve their actual Cash/Card context.
- Workspace-keyed tasks reset Activity and Savings state so switching workspaces
  cannot display the prior workspace's events; stale load generations are
  ignored.
- Added coverage for split expense payment-source preservation and added
  structural guards for the fix-round wiring.

Fix Round 1 checks:

```text
swiftc -parse (changed Task 5 Swift files)          PASS
bash scripts/check-signal-redesign.sh               PASS
bash scripts/check-app-source-regressions.sh        PASS
ruby scripts/test-testflight-workflow.rb            PASS
git diff --check                                    PASS
```

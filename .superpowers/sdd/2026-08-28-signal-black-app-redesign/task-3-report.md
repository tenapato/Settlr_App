# Task 3 report — Signal amount forms and rows

## Outcome

Implemented the Task 3 forms pass on the existing `feat/signal-black-redesign-spec` branch. The shared hero amount control keeps its existing MXN / symbol / centered amount / underline composition while adding adaptive semantic color, focus treatment, long-value scaling, validation copy, and currency-aware VoiceOver value. Added the reusable `SignalFormRow` primitive and migrated the named expense, income, savings, recurring, card-payment, and split form surfaces to the Signal row treatment where applicable.

## Changes

- Enhanced `HeroAmountField` in `Settlr/Views/Components/FormControls.swift`:
  - Added optional `errorMessage` and `currencyCode` inputs.
  - Keeps the decimal keyboard, centered amount, MXN eyebrow, currency symbol, and underline.
  - Uses `Theme.ink` for entered digits, `Theme.faint` for the placeholder, caller tint for the symbol, and `Theme.accent` for focus/tint.
  - Adds `.minimumScaleFactor(0.45)`, `.monospacedDigit()`, a full-region focus target, and the explicit `Amount in Mexican pesos` accessibility label/value.
- Added generic `SignalFormRow<Trailing: View>` with a 44 pt minimum height, full-width hairline, leading label, trailing native control/value, and optional disclosure indicator/action.
- Replaced heavy `FormCard` wrappers beneath heroes in:
  - `ExpenseFormSheet`
  - `IncomeFormSheet`
  - `SavingsEntryFormSheet`
  - `IncomeRecurringFormSheet`
  - `SavingsRecurringFormSheet`
- Migrated the relevant merchant/date and card-selection controls in `SplitCreateSheet` to Signal rows while retaining split draft calculations, receipt reconciliation, payment selection, queue behavior, and request bodies.
- Replaced hard-coded legacy card-payment colors with adaptive `Theme` tokens in `CardPaymentsView`; removed its leaf dark override.
- Removed leaf `.preferredColorScheme(.dark)` overrides from all touched form sheets so the app-level Dark/Light/System preference remains authoritative.
- Added Task 3 structural checks to `scripts/check-signal-redesign.sh`.

## Behavior preserved

No endpoint, request body, validation rule, save callback, recurrence behavior, card lookup, split draft behavior, or dismissal callback was changed. Native `DatePicker`, `Menu`, segmented controls, recurrence toggles, and existing keyboard dismissal remain in place.

## TDD / verification

RED: the new Task 3 source checks were added before implementation and `bash scripts/check-signal-redesign.sh` exited 1 because `SignalFormRow` was absent.

GREEN and regression checks:

```text
bash scripts/check-signal-redesign.sh        PASS
bash scripts/check-app-source-regressions.sh PASS
ruby scripts/test-testflight-workflow.rb     PASS
git diff --check                             PASS
swiftc -parse (all 8 changed Swift files)    PASS
```

Per task instructions, `xcodebuild` and XCTest were not run.

## Fix Round 3 — feature revocation timing

- Added `ExpenseFormSheet` reaction to `canUseCreditCards` changes so a feature revocation while the sheet is visible immediately clears stale cards and normalizes the payment channel to cash.
- Added the same normalization immediately before `SplitCreateSheet.submitEdit` constructs its submission draft, closing the confirmation-dialog timing window while preserving non-card paths.
- Added structural checks for the Expense change observer and the exact Split submit-time ordering.

Fix Round 3 verification:

```text
bash scripts/check-signal-redesign.sh        PASS
bash scripts/check-app-source-regressions.sh PASS
ruby scripts/test-testflight-workflow.rb     PASS
git diff --check                             PASS
swiftc -parse (changed Swift files)           PASS
```

Per task instructions, `xcodebuild` and XCTest were not run.

## Fix Round 2 — remaining Important findings

- Added gated card-state normalization to Expense and Split. When `credit_cards` is unavailable, stale edit state is converted to cash with a nil card identifier before presentation and again immediately before request construction; card controls and card loading remain hidden/skipped.
- Restored the Hero total for a new, non-scanned by-item/manual split (`!isEditing && !hasScanned`) while retaining scanned receipt reconciliation and the existing even/by-item derived-total rules.
- Updated the Split item quantity badge to use `Theme.accentText` for light-mode readability.
- Added structural checks for normalization, effective request fields, manual-total eligibility, and the quantity token.

Fix Round 2 verification:

```text
bash scripts/check-signal-redesign.sh        PASS
bash scripts/check-app-source-regressions.sh PASS
ruby scripts/test-testflight-workflow.rb     PASS
git diff --check                             PASS
swiftc -parse (changed Swift files)           PASS
```

Per task instructions, `xcodebuild` and XCTest were not run.

## Scope notes

The pre-existing `.superpowers/brainstorm/` directory remains untracked and was not staged. No Server files were touched.

## Fix Round 1 — reviewer Important findings

Addressed all six Important findings without changing endpoint paths, request bodies, save callbacks, queue behavior, or dismissal semantics:

- Passed each form's existing `errorMessage` into `HeroAmountField` and removed the duplicate error copy below the row group.
- Made the hero editor width-bounded (`maxWidth: 320`) while keeping the centered editable amount composition and the large focus region, so `minimumScaleFactor(0.45)` can actually participate for long values.
- Added `SignalNativeFormRow`, which gives native `Menu` and `DatePicker` controls the complete row hit region and preserves their own accessibility labels. Migrated all corresponding named form call sites, including SplitCreateSheet's date/card rows.
- Added `credit_cards` feature checks to `ExpenseFormSheet` and `SplitCreateSheet`. Card options and card rows are hidden, and card loading is skipped, when unavailable. Existing edit state/request semantics remain intact.
- Replaced touched accent text/icon uses with `Theme.accentText` while retaining `Theme.accent` for fills and control tint where appropriate; toolbar `Done` labels now use the readable token.
- Completed SplitCreateSheet's remaining form migration: date is a native Signal row, and manual/even-split totals use the shared `HeroAmountField` binding while preserving derived totals, reconciliation, and draft calculation behavior.

Fix Round 1 verification:

```text
bash scripts/check-signal-redesign.sh        PASS
swiftc -parse (all 8 changed Swift files)    PASS
```

Per task instructions, `xcodebuild` and XCTest were not run.

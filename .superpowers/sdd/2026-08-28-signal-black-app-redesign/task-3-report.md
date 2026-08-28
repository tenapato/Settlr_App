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

## Scope notes

The pre-existing `.superpowers/brainstorm/` directory remains untracked and was not staged. No Server files were touched.

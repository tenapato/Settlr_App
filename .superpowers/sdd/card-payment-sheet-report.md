# Card payment sheet report

## Scope and files

- `Settlr/Models/CardPaymentsSummary.swift` — Foundation-only draft parser and monthly payment body.
- `Settlr/Network/Endpoints.swift` — `monthlyCardPayments` endpoint.
- `Settlr/Views/Main/CardPaymentsView.swift` — request method, tile hierarchy, and native record-payment sheet.
- `Settlr/Views/Main/CardsRootView.swift` — feature-gated sheet presentation and stale-workspace guards.
- `scripts/card-payment-draft-regression.swift` and `scripts/check-card-payment-draft.sh` — executable Foundation regression.
- `scripts/check-card-payment-sheet.sh` — focused endpoint/sheet wiring guard.

## RED evidence

`./scripts/check-card-payment-draft.sh` before production code:

```text
scripts/card-payment-draft-regression.swift:7:20: error: cannot find 'CardPaymentDraft' in scope
scripts/card-payment-draft-regression.swift:22:13: error: cannot find 'CardPaymentDraft' in scope
scripts/card-payment-draft-regression.swift:32:13: error: cannot find 'CardPaymentDraft' in scope
```

`./scripts/check-card-payment-sheet.sh` before production code:

```text
Endpoints must expose the monthly card-payment route.
```

## GREEN evidence

```sh
./scripts/check-card-payment-draft.sh && ./scripts/check-card-payment-sheet.sh && find Settlr -name '*.swift' -print0 | xargs -0 swiftc -parse && ./scripts/check-category-feature-gate.sh && sh ./scripts/check-dashboard-month-state.sh && sh ./scripts/check-activity-stale-warning.sh && sh ./scripts/check-scanner-result-settlement.sh && sh ./scripts/check-signal-redesign.sh && sh ./scripts/check-app-source-regressions.sh && git diff --check
```

Exact output:

```text
Card payment sheet source checks passed.
Category feature-gate regression check passed.
Dashboard month state regression passed.
Activity retained-data warning regression check passed.
Scanner result settlement regression check passed.
App source regression checks passed.
```

The Foundation regression, full Swift parse, Signal redesign guard, and diff check completed silently with exit status 0. No Xcode build or XCTest command was run, per task instruction. No project or plist files changed.

## Self-review

- Open cards expose `Record payment` as the primary action and retain `Mark as paid` as a secondary control; paid cards expose only `Undo paid status`.
- The sheet defaults to server-reported outstanding cents, names the card and resolved statement month, supplies native date entry, an optional trimmed note, keyboard Done, 44pt-or-larger controls, and inline failures.
- Saving disables controls and interactive dismissal; only a successful request followed by summary reload dismisses the sheet.
- The root clears selection on feature revocation or workspace changes and checks current workspace/feature state before and after the request. Paid state remains server-derived after reload.

## Endpoint compatibility

The app posts `MonthlyCardPaymentBody` with `month` from `FortnightCard.resolvedDueMonthKey`, `creditCardId`, positive integer `amountCents`, optional `note`, and `paidAt` formatted as `yyyy-MM-dd` to `POST /api/workspaces/:workspaceId/card-payments/monthly-payments`. `APIClient.send` intentionally ignores the response body and retains server error messages for inline display.

## Concern

Simulator and Xcode/XCTest verification were intentionally omitted by the no-Xcode/no-XCTest task constraint; the executable Foundation and source-level checks cover the changed contract and wiring.

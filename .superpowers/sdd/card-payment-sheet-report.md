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

## Fix round 1 — stale saves, refresh recovery, and amount grammar

### Fix summary

- Added a presentation lifecycle token to `CardPaymentsVM`; beginning a new record sheet or invalidating on workspace/feature changes retires all older save completions and in-flight loads.
- Record payment now distinguishes a successful POST from a successful summary refresh. A refresh failure keeps the sheet open with a clear recorded-but-not-refreshed error, and the only retry path is `Retry refresh`—never a second POST.
- Added a Foundation-only recovery state machine regression to prove that transition, and tightened the amount grammar for `.50` plus malformed separator rejection.
- Removed the generic `FormCard` wrapper below `HeroAmountField`; the native date and Note Signal rows are now borderless rows separated only by their hairlines.

### RED evidence

Parser behavior before the grammar correction:

```text
main/card-payment-draft-regression.swift:57: Fatal error: Regression failed: accepts a fractional amount without a leading zero
./scripts/check-card-payment-draft.sh: line 13: 63136 Trace/BPT trap: 5       "$binary"
```

Lifecycle state regression before its implementation:

```text
scripts/card-payment-draft-regression.swift:47:25: error: cannot find 'CardPaymentSaveLifecycle' in scope
```

No-duplicate-retry recovery regression before its implementation:

```text
scripts/card-payment-draft-regression.swift:56:24: error: cannot find 'CardPaymentRecordRecovery' in scope
```

Source guard before lifecycle wiring:

```text
Cards root must gate and present the record-payment sheet.
```

### GREEN evidence

```sh
find Settlr -name '*.swift' -print0 | xargs -0 swiftc -parse && ./scripts/check-card-payment-draft.sh && ./scripts/check-card-payment-sheet.sh && ./scripts/check-category-feature-gate.sh && sh ./scripts/check-dashboard-month-state.sh && sh ./scripts/check-activity-stale-warning.sh && sh ./scripts/check-scanner-result-settlement.sh && sh ./scripts/check-signal-redesign.sh && sh ./scripts/check-app-source-regressions.sh && git diff --check
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

The complete Swift parse, Foundation regression, Signal redesign guard, and diff check completed silently with exit status 0. No Xcode build or XCTest command was run.

### Round-1 self-review

- A save can mutate or dismiss only if its presentation token still belongs to the active sheet. Context revocation increments the token and invalidates pending loads before the view model is discarded.
- After POST success, a stale or failed refresh becomes refresh-only recovery; the sheet cannot send the append-only endpoint again.
- A successful refresh dismisses; a refresh failure remains inline with `Retry refresh`; a stale completion does neither.
- Signal Date and Note rows have no outer generic card/background, retain 44pt native hit targets, and keep their own hairline separators.

## Fix round 2 — final presentation dismissal gate

### Fix summary

- `CardPaymentRecordSheet` now receives a synchronous `isPresentationCurrent` closure and checks it immediately before recovery state changes or dismissal. There is no suspension between that check and `dismiss()`.
- The root identifies the active presentation by both generation and sheet identity, checks it before and after every awaited record/refresh operation, and returns `.stale` when ownership changed.
- `CardsRootView.onDisappear` invalidates the presentation lifecycle, covering teardown paths where workspace state destroys the parent before an `onChange` callback can run.
- Error and loading-state completions use the same synchronous gate, so a stale task cannot mutate an obsolete sheet.

### RED evidence

Pure completion-gate regression before the additional lifecycle argument:

```text
scripts/card-payment-draft-regression.swift:66:72: error: extra argument 'isPresentationCurrent' in call
```

Source guard before disappearance invalidation and sheet gate wiring:

```text
Cards root must gate and present the record-payment sheet.
```

### GREEN evidence

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

The Foundation regression, full Swift parse, Signal redesign guard, and diff check completed silently with exit status 0. No Xcode build or XCTest command was run.

### Round-2 self-review

- A superseded, revoked, or destroyed presentation ignores `.refreshed` in the pure recovery regression and in the sheet's final synchronous guard.
- Root ownership means: active sheet identity matches, workspace matches, card-payment access remains enabled, and the view model still owns the presentation generation.
- Root rechecks that ownership after every awaited record/refresh call; the sheet repeats the synchronous check immediately before any mutation or dismissal.

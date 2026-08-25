# Bill Split Payment Method Editing and Status Design

## Purpose

Let the organizer correct how they paid for a bill split while claims are open or after the split is closed or settled. Keep the bill split and its owned expense entry consistent, and stop describing an `each_own` split as `Collecting` when nobody owes the organizer.

The work spans:

- `App/`: payment-method presentation and editing, card selection, status copy, and conflict handling.
- `Server/`: organizer-only payment mutation, linked-expense synchronization, version checks, and payer-aware list data.

The public Panel and participant-facing claim routes do not expose workspace cards and require no UI change.

## Product Rules

1. The organizer can change `Cash / debit` versus `Credit card` while a split is open, locked, or settled.
2. Credit-card payment requires one active card from the split's workspace.
3. For `each_own`, the selection describes only the organizer's own share. Other participants' payment methods are private and are not stored in the organizer's workspace.
4. Changing payment method never reopens a split, clears claims, changes shares, or changes settlement state.
5. The split is the source of truth for ledger metadata. Every supported split edit that changes expense-backed data updates the owned expense in the same D1 batch.
6. A failed split or expense write rolls back both sides. The API never returns a state where the split says cash while its owned expense says credit card, or vice versa.
7. `each_own` closed splits display `Completed`, not `Collecting`.

## Status Language

Status presentation depends on both persisted status and payer mode:

- `open`: `Claiming`.
- `locked` or legacy `settled` with `payer = each_own`: `Completed`.
- `locked` with `payer = me`: retain the existing amount-owed presentation when money remains; otherwise use `Collecting`.
- `settled` with `payer = me`: `Settled`.

The bill-split list response adds `payer`. The iOS summary decoder treats an absent payer from an older response as unavailable rather than guessing `me`. The status helper is a pure, separately tested presentation helper.

## Organizer UI

Split detail shows a persistent `You paid with` row above the item/people content for every status. It displays:

- `Cash / debit`; or
- the selected credit-card label and last four digits.

Tapping the row presents a compact payment-method sheet using the existing segmented cash/card control and workspace card selector. Save is disabled until a card is selected for credit-card payment.

The row is available while the organizer is claiming items and after the split is locked or settled. It is not shown in public claiming or pass-the-phone participant screens, because those screens must not reveal the organizer's cards. The organizer can dismiss pass-the-phone and edit the method from split detail.

The sheet loads cached cards immediately, refreshes them from the server, excludes archived cards from new selection, and still renders the current stored card label when it can be resolved. Payment-method editing requires a connection and is never placed in the durable split-creation queue.

After Save, the returned split replaces the current view-model detail so the row updates immediately. A conflict refreshes the split, preserves the user's unsaved selection, and asks them to retry. Other failures leave the sheet open with an actionable error.

## API

Add an organizer-only mutation:

```http
PATCH /api/workspaces/:workspaceId/bill-splits/:splitId/payment-method
Content-Type: application/json

{
  "version": 7,
  "paymentChannel": "cash" | "credit_card",
  "creditCardId": null | "card-id"
}
```

Validation:

- `version` is a non-negative integer and must match the current split version.
- `paymentChannel` is exactly `cash` or `credit_card`.
- Cash always persists `creditCardId = null` even if a stale client sends an ID.
- Credit card requires an assignable, non-archived card in the same workspace.
- Only the split organizer may mutate the method.

The response returns the refreshed owner `BillSplit` DTO. A stale version returns `409` with code `stale_version` and the refreshed split. The endpoint remains valid for `open`, `locked`, and `settled` states.

## Atomic Expense Synchronization

The payment-method endpoint writes the split and its owned expense in one D1 batch guarded by the existing split version check.

- `payer = me`: the owned full-bill expense is updated for every status.
- Open `each_own`: no expense exists by design, so only the split preference changes. Locking later creates the organizer-share expense with that method.
- Locked or settled `each_own`: update only the organizer-share expense owned by the split.

If an expense is expected for the current payer/status but no owned expense exists, the mutation repairs the invariant by creating and linking the correct expense in the same batch. It uses the full bill for `me` and the frozen organizer share for closed `each_own`. It does not search for or modify unrelated expenses.

The same invariant applies to existing supported split-edit paths:

- complete open-draft edits synchronize payment channel, card, merchant, date, amount, currency, category, and payer-mode expense creation/deletion;
- lightweight split patches synchronize any supported merchant, date, or amount fields with the owned expense;
- locking `each_own` creates the organizer-share expense from the split's current ledger metadata;
- reopening `each_own` removes only the expense owned by that split, as it does today.

Shared helpers determine whether an expense should exist, its amount, and the ledger fields to write so the draft, payment-method, and lock paths cannot drift into different rules.

## Concurrency and Integrity

The mutation increments the split version without changing its status. Its conditional update requires both the expected version and current status, using the existing named version-check constraint so the whole D1 batch rolls back on a concurrent claim, edit, lock, or settlement.

Claims, participant shares, settlement timestamps, item rows, and reimbursement income rows are not written by this endpoint.

The split-owned-expense relationship is used to target the ledger entry. A card change consequently updates card due totals and expense filters through the existing expense queries; no separate aggregate record is maintained.

## Error Handling

- Missing or invalid card: keep the sheet open and explain that a valid workspace card is required.
- Archived or foreign-workspace card: reject without changing split or expense.
- Stale version: return the current split, refresh the UI, retain the pending selection, and ask for another Save.
- Missing expected expense: repair it atomically as described above.
- Offline: explain that payment-method changes require a connection; never queue card identifiers or overwrite later server state.

## Testing

### Server

- Open organizer-paid split changes cash/card on both split and owned expense.
- Locked and settled organizer-paid splits update both records without changing status, claims, shares, or settlements.
- Open `each_own` stores the method without creating an expense; locking later uses the stored method.
- Locked `each_own` updates only the organizer-share expense and preserves its amount.
- Cash clears a stale card ID.
- Missing, archived, and cross-workspace cards are rejected.
- A concurrent claim/version change returns `409` and rolls back the expense update.
- A missing expected owned expense is recreated and linked without touching unrelated expenses.
- Existing draft and lightweight edit paths keep all expense-backed fields synchronized.
- Bill-split summaries include payer mode.

### iOS

- Payment method request encodes version, channel, and nullable card ID.
- View-model mutation adopts the returned split and refreshes on `409` while retaining pending selection.
- Cash can save without a card; credit card cannot.
- The payment row resolves current card copy and is available for open, locked, and settled owner views.
- Legacy summary responses without payer decode safely.
- Status presentation returns `Claiming`, `Completed`, owed/`Collecting`, and `Settled` for the agreed payer/status combinations.
- Public and pass-the-phone participant screens do not expose the organizer's card list.

## Verification

Run Server tests and typechecking. Run the App's static Swift/source/project checks, but do not run `xcodebuild`; the user will build and manually test at the end.

Manual acceptance should cover changing cash to a card and card to cash in each of these states: open organizer-paid, locked organizer-paid, settled organizer-paid, open `each_own`, and completed `each_own`. Confirm the linked expense, card totals, split detail, and list status all update together.

## Delivery Constraints

All App and Server changes remain unstaged and uncommitted for the user to review and commit. No deployment, remote migration, or app build is part of implementation.

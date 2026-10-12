# Guided bill split and live Dashboard signal

## Purpose

The scanned bill editor currently asks the user to review receipt evidence, configure the split, edit every item, reconcile the total, choose a payment method, and create the split in one long form. The data and accounting behavior are sound. The presentation repeats receipt facts and gives every field equal weight, which makes the task hard to understand.

The approved redesign divides the task into three focused screens:

1. Setup
2. Items
3. Confirm

This spec also keeps the custom Dashboard signal carousel visible during months with no spending. It must use real monthly data and must not invent category insights.

This is a pending view-architecture migration. It is not an incremental restyle of the current `SplitCreateSheet` scroll view. The implementation must introduce explicit guided steps while keeping the current draft, accounting, and network behavior intact.

## Scope

This work changes:

- The scanned and manual bill creation experience.
- The existing split editor, which reuses the same draft and validation rules.
- The placement and disclosure of scan warnings, receipt metadata, payer choice, division mode, people, item editing, tax, tip, fee, reconciliation, and payment method.
- The Dashboard signal carousel's zero-spending behavior.
- The Signal Black component documentation and HTML preview for the affected components.

This work does not change:

- Server routes or request and response contracts.
- Split accounting rules.
- Payer semantics.
- Item claim semantics.
- Offline creation and idempotency behavior.
- Stale-version protection for editing.
- Settlement locks.
- Receipt parsing or parser preference behavior.
- Authentication, workspaces, tabs, or the floating launcher.
- The ranking of real spending insights.

## Product decisions

### One decision type per screen

Setup asks how the split works. Items asks what is on the receipt. Confirm asks which total is authoritative and whether the split is ready to create.

Receipt facts appear once in a compact header. The old scan banner, review table, repeated merchant and date rows, and long parser explanation do not remain in the primary scroll.

### The scanner Review remains the evidence checkpoint

Capture and Review keep their current roles. Review shows the parsed receipt before the user enters the guided split task. Setup does not reproduce the full Review table.

The compact receipt header shows:

- Merchant.
- Receipt total.
- Date.
- The current payment channel selected in the draft.
- A warning count when a scan produced unverified lines or parser warnings.

The date and payment channel are current draft values. They are not presented as facts parsed from the receipt because `ScannedReceipt` does not provide either field. Tapping the header opens receipt details. Its menu contains Edit receipt details, Scan again, and Receipt parsing settings. Scan again is no longer a full-width lime button.

### Lime marks the next action

Each screen has one sticky bottom action:

- Setup: `Review items` for by-item splits or `Check total` for even splits.
- Items: `Check total`.
- Confirm: `Create split`, `Save changes`, or `Save on this phone`, depending on the existing state.

Create does not appear disabled in the navigation bar from the start of the flow. Sticky actions remain tappable except while scanning or submitting. A tap first runs step validation. If a requirement is missing, the flow does not advance or submit. It exposes the specific problem and moves focus to the relevant control.

## Navigation

`Scan and split` remains a full-screen modal with its own `NavigationStack`.

The scanner path is:

```text
Capture -> Review -> Setup -> Items -> Confirm -> Result
                         \-> Confirm (even split)
```

The manual creation path starts at Setup. Editing an existing split also starts at Setup and uses `Save changes` on Confirm.

Back behavior:

- Setup back returns to scanner Review when the draft came from the scanner.
- Setup in manual or edit mode uses Close or Cancel.
- Items back returns to Setup.
- Confirm back returns to Items for by-item splits and Setup for even splits.
- Back preserves the same `SplitDraft`, `totalEdited`, scan evidence, selected card, participant names, and reconciliation decision.
- Cancel exits the full task. Manual and edit modes compare the submission-relevant draft with the snapshot captured after initial data is applied. Scanner mode also tracks whether a receipt has been imported, so leaving after Review asks before discarding the scan even if no field was edited. Opening an existing split and making no changes does not prompt.
- Native edge swipe remains available when no irreversible request is running.

Submission temporarily blocks dismissal and shows progress in the sticky action. Successful creation replaces the task with Result. Back must not re-enter a completed creation flow.

## Screen 1: Setup

Setup contains the compact receipt header followed by the decisions that define the split.

### Who paid

Two full-width rows remain because this choice changes the ledger meaning:

- `I paid it all`: the organizer owns the expense and tracks reimbursements.
- `Everyone paid their own`: Settlr records individual shares and no reimbursement state.

Each row has a short consequence statement. The selected row uses a lime check. This choice is required before continuing. Tapping Continue without it selected shows the explanation inline and moves accessibility focus to Who paid.

### Division mode

Use a native-feeling two-option segmented control:

- `By item`
- `Evenly`

By-item mode routes to Items. Even mode skips Items and shows the live per-person share on Confirm.

Switching modes keeps the draft data already entered. The request builder remains responsible for normalizing the submitted payload to the selected mode.

### People

The People row shows the headcount and opens a focused editor. Guest names remain optional. The editor uses the existing participant model and preserves the current minimum and maximum limits.

### Payment method

The Paid with row shows Cash / debit or the selected card. Credit-card controls appear only when the feature is enabled. Selecting Credit card requires a card before Setup can continue.

The app continues to load cached cards first and refresh them from the existing endpoint. Setup owns a small card-loading state with `idle`, `refreshing`, and `failed(message)` cases. A refresh failure keeps cached cards available and adds a compact Retry row below Paid with. It does not replace the screen with a generic error. If the feature is revoked while the flow is open, stale card state is normalized to Cash / debit before submission.

### Receipt details

Merchant and date remain editable through a compact receipt-details sheet. Validation that depends on merchant or total must return the user to the relevant control with a plain inline message.

Parser settings and scan recovery stay available, but they do not occupy permanent space in Setup.

## Screen 2: Items

Items is used only for by-item splits.

The top summary shows item count, participant count, and item subtotal. A compact filter switches between:

- `Needs review`, when unverified items exist.
- `All`.

There is no Unassigned filter during creation because public or pass-around claims happen after the split exists.

### Item rows

The resting row shows:

- Item name.
- Line amount.
- Quantity when greater than one.
- Allocation mode, either Shared or Individual units.
- A compact warning when the parser did not verify the line.

Rows do not repeat a 44-point menu, price field, remove button, allocation row, and warning at the same time. Tapping a row opens a form sheet for:

- Name.
- Quantity.
- Unit price.
- Shared or Individual units.
- Remove item.

The item form uses native controls, a decimal keyboard with Done, and a destructive confirmation only when removal could clear existing claims in edit mode.

`Add item` remains available below the list and opens the same editor with an empty item.

Unverified receipt lines are evidence warnings. They do not block creation by themselves because the current parser model has no separate verified-by-user state. A material total mismatch still requires an explicit reconciliation decision on Confirm.

## Screen 3: Confirm

Confirm is the only screen that creates or saves the split.

### Total

The receipt total is the display amount. It uses tabular numerals and the approved hero amount treatment. Tapping the amount makes it editable when the existing rules permit editing.

Below it, a compact math group shows:

- Item subtotal.
- Tax.
- Tip.
- Fee.
- Calculated total.
- Receipt total.
- Difference, only when nonzero.

Tax, tip, and fee rows open focused editors. Tip keeps the existing 10, 12, 15, and 20 percent shortcuts and retotaling behavior.

### Reconciliation

A material mismatch appears directly below the math group. It explains whether the scan probably missed a line or counted one twice. It offers the existing two decisions:

- Keep receipt total.
- Use calculated total.

Keeping the receipt total retains the existing confirmation alert. The Create action stays unavailable until the reconciliation no longer requires a decision.

### Split summary

A short read-only summary shows:

- Payer mode.
- Division mode and participant count.
- Payment method or selected card.
- Per-person share for even splits.
- Offline status when relevant.

Each summary row returns to the screen where the value is edited.

### Final action

The existing `canSave` rules remain authoritative for whether submission may run:

- Merchant is present.
- Even splits have a positive total and headcount.
- By-item splits have priced lines.
- Payer is selected.
- Credit-card payment has a selected card.
- Material reconciliation has a decision.
- Existing splits are edited only while online.
- No scan or submission is running.

The sticky action is not permanently disabled for missing input. On tap it evaluates these rules, surfaces the first actionable problem, and submits only when `canSave` is true. It is disabled only while scanning or submitting.

Offline creation keeps the current cache-first queue and stable idempotency key. The button says `Save on this phone`. Result must state that creation is queued, not complete.

## Loading, errors, and state restoration

- Loading cached credit cards does not block the rest of Setup.
- A card refresh failure keeps cached choices and shows a small retry message near Paid with.
- Parser recovery returns to the same step with the draft intact.
- Known local validation failures and stable server field identifiers map to their Setup, Items, or Confirm control. Generic server messages stay at the top of Confirm with Retry and do not guess a field.
- A stale edit response refreshes the current split and explains that the user must review before retrying.
- Draft state survives navigation between the three screens.
- Relaunch persistence remains limited to the existing durable offline creation queue. This redesign does not add general draft persistence.

## Accessibility and motion

- Every target is at least 44 by 44 points.
- Screen titles use native navigation titles.
- Selected payer and division controls expose selected traits.
- Item filters announce their count and selected state.
- Expanded sheets announce their purpose and preserve keyboard focus.
- Amounts use tabular digits and scale before truncating.
- Dynamic Type may stack receipt and summary rows vertically.
- Reduce Motion keeps native navigation transitions but removes decorative content movement.
- Error focus moves to the first blocking problem when Continue or Create is attempted.

## Dashboard signal carousel

The Dashboard always reserves the monthly signal section. A zero-spending month must not collapse the screen between Money flow and movement count.

### Real spending data

When `SpendingInsights.build` returns category or comparison insights, preserve the approved behavior:

- Existing ranking and five-item limit.
- About 30 points per second.
- Seamless loop.
- Touch pause.
- One-to-one drag.
- Resume after about 2.5 seconds.
- Tap opens Categories.
- Reduce Motion uses a static horizontal row.

### No spending data

When spending is zero or categories are empty, build a small set of monthly signals from fields already present in `SummaryResponse`. Examples include:

- Income received.
- Available this month.
- Savings movement when nonzero.
- No spending yet.
- Movement count.

These values are factual summaries, not category insights. Do not create fake category names, percentages, comparisons, or trends.

Formatting reuses the existing Dashboard conventions. Income is positive. Available uses `SummaryResponse.availableCents`, with expense color only when negative. Savings uses the existing money-flow sign, `-summary.savingsNetCents`, so deposits read as money moved aside and withdrawals read as money moved back.

The fallback rail is not a Categories link because there is no category insight to open. VoiceOver must not describe it as a button. If the user has Reduce Motion enabled, it becomes a static horizontal row. If the month has no movements at all, the section shows a quiet static signal rather than looping duplicate text.

When real spending data arrives, the section changes to the normal spending hero and ticker without changing its position in the Dashboard.

## Data and endpoint compatibility

The redesign uses the existing app models and endpoints. It does not need Server changes.

Bill creation and editing continue through the existing `BillSplitVM`, `SplitDraft`, and `PendingSplitQueue` paths. Receipt parsing, credit cards, public joining, claims, settlements, and QR sharing keep their current routes and payloads.

Dashboard fallback signals use the existing monthly summary response. They do not add a request.

## Implementation boundaries

The current `SplitCreateSheet` remains the owning container for loading, scanner recovery, submission, alerts, and offline behavior. It gains a typed step path and delegates presentation to focused Setup, Items, and Confirm views. The parent owns the shared draft so pushing and popping screens cannot reset it.

The item editor and receipt-details editor are sheets over the guided flow. The step views receive bindings and actions. They do not call endpoints directly.

`SpendingInsights.build` remains the spending-specific ranking engine. A separate fallback builder produces zero-spending monthly signals. `InsightTicker` must support a noninteractive fallback mode without adding button accessibility traits.

## Design system updates

Update both design-system artifacts after implementation:

- `docs/design-system/SETTLR_SIGNAL.md`
- `docs/design-system/settlr-signal-components.html`

Document:

- Guided-flow progress rail.
- Compact receipt header.
- Dense item row and item editor sheet.
- Sticky task action.
- Reconciliation decision block.
- Always-present Dashboard signal states.

## Verification

Static and automated checks must cover:

- Setup to Items to Confirm for by-item splits.
- Setup directly to Confirm for even splits.
- Back navigation preserving the draft.
- Scanner Review returning to the same Setup draft.
- Manual creation and existing split editing.
- Both payer modes and both division modes.
- Optional guest names.
- Cash and credit-card payment with feature gating.
- Unverified receipt warnings.
- Material mismatch decisions.
- Tip presets and retotaling.
- Offline queued creation and online-only editing.
- Stale-version and claim-clearing safeguards.
- Dashboard with zero spending, one real insight, and five real insights.
- Dashboard interaction, Reduce Motion, and noninteractive fallback accessibility.
- Dynamic Type, VoiceOver labels, dark appearance, safe areas, keyboard dismissal, and sticky-action clearance above the home indicator.

Use the signing-disabled generic iOS build for compiler verification. The user will perform the final Xcode Simulator and full-motion pass.

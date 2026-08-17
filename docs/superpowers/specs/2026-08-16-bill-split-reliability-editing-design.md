# Bill Split Reliability, Quantity Claims, and Editing Design

## Purpose

Make scanned bill splits trustworthy and fully correctable from the iOS app. The work covers receipt parsing, item-total reconciliation, quantity-aware claiming, participant setup for pass-the-phone flows, editing an existing split, `each_own` accounting presentation, and the 12% tip shortcut.

The implementation spans the three existing repositories:

- `App/`: capture, parser preference, draft creation/editing, pass-the-phone, and split/expense presentation.
- `Server/`: hosted AI parsing, participant and claim APIs, persisted allocation state, draft editing, and accounting invariants.
- `Panel/`: quantity-aware public claiming so the web link obeys the same rules as iOS.

## Success Criteria

1. `1 XX AMB 23 105.00` can never become `23x XX AMB`; quantity comes from the leading receipt column, not a model guess or a number inside the item name.
2. A parser cannot silently shift one row's price onto another row. Unverified rows remain visibly flagged for review.
3. Settings offers `Automatic`, `On device`, and `On server` receipt parsing. `Automatic` remains the default.
4. The review form clearly reconciles item lines with the printed total and requires an explicit decision for a material mismatch.
5. A participant can claim a chosen number of units from a quantity line without claiming the remaining units.
6. Unit claims cannot exceed the item's quantity, including under concurrent requests.
7. A genuinely shared plate can still be divided among multiple people through an explicit `Share item` action.
8. By-item splits can have named participants before anyone claims. Pass-the-phone never opens as `1 of 1` unless the organizer intentionally chose a one-person split.
9. An open split can return to the creation-style editor and change its full draft information.
10. `each_own` never displays reimbursement language or represents the organizer as having paid the entire bill.
11. Tip presets are `10%`, `12%`, `15%`, and `20%` and keep the explicit total in sync.

## Receipt Parsing

### Parser preference

Add a stored iOS preference with three values:

- `automatic`: try the on-device Foundation Model when available; parse on the server when the device model is unavailable, invalid, or unable to return any usable item rows.
- `onDevice`: use only the on-device Foundation Model. If unavailable or invalid, explain why and offer to switch to Automatic or On server; do not silently upload OCR text.
- `server`: send the locally recognized OCR text directly to the existing server receipt endpoint. The receipt image remains on the phone.

The setting belongs in the existing Receipts section. The scan result banner names the parser used and links back to Settings when review is needed.

### Deterministic receipt evidence

The language model identifies semantic item rows; it does not own quantity or money. Both iOS and Worker paths apply the same deterministic evidence rules after model output:

1. OCR keeps quantity, label, and rightmost money fragment on the same geometric row.
2. A row's quantity is parsed only from the leading quantity column. Trailing numbers remain part of the normalized item name.
3. The rightmost printed money token is the line total.
4. Model items are matched to unused printed rows with exact normalized matching first, then conservative containment matching. Short labels such as `MOZ` or `PZA` are never fuzzy-matched.
5. A matched row rebuilds `quantity` and `unitPriceCents` from the printed evidence. When a line total cannot divide evenly by the printed quantity, retain a quantity of one and the exact line total, with a warning.
6. An unmatched model item is marked unverified. It may remain editable in the draft but cannot be silently treated as verified money.
7. Repeated names consume distinct printed rows in receipt order.

Extract the shared concepts into small, separately tested helpers on each platform rather than leaving quantity inference embedded in view or model code.

### Server parser

Keep the existing Workers AI binding and text-only privacy boundary. The Worker path uses the more capable hosted model to classify rows, then applies the same deterministic money and quantity reconstruction used on device. Fix the legacy server fallback so decimal strings such as `145.00` cannot be interpreted as 145 cents when a row is unmatched.

The API response adds parser metadata and per-item verification information:

```ts
type ReceiptVerification = "verified" | "unverified";

type ScannedReceiptItem = {
  name: string;
  quantity: number;
  unitPriceCents: number;
  verification: ReceiptVerification;
};

type ScannedReceipt = {
  parser: "on_device" | "server";
  merchant: string | null;
  items: ScannedReceiptItem[];
  taxCents: number;
  tipCents: number;
  totalCents: number;
  warnings: string[];
};
```

Older responses remain decodable by treating missing verification as `unverified` and deriving the parser name from the selected route.

## Total Reconciliation

The printed total remains authoritative, but mismatches must be visible and intentional.

The draft editor shows:

- item subtotal;
- tax, tip, and fee;
- calculated total;
- printed/entered bill total;
- the signed difference.

When the difference is within one peso or 0.1% of the printed total, whichever is larger, treat it as receipt rounding. For larger differences:

- if lines are short, offer `Keep receipt total` and `Use calculated total`;
- if lines exceed the receipt total, require correction or an explicit `Keep receipt total` confirmation because a duplicate or bad quantity is likely;
- list every unverified item directly above the confirmation.

Saving never silently changes the user's selected total. The server continues to allocate a positive unexplained remainder proportionally, but rejects a draft whose item subtotal exceeds the selected total unless the request carries an explicit mismatch acknowledgement. The acknowledgement is stored only as audit metadata on the split, not as money.

## Quantity-Aware Claims

### Allocation modes

Every item has one of two allocation modes:

- `units`: exclusive unit ownership. This is the default for quantity greater than one.
- `shared`: the entire line total is divided evenly among its claimers. This preserves the existing shared-plate behavior and is the default for quantity one.

Changing modes is explicit. If claims already exist, the UI explains that changing mode clears that item's claims and asks for confirmation.

### Persisted model

Add `allocation_mode` to `bill_split_item` with allowed values `units` and `shared`. Add `quantity` to `bill_split_claim`, defaulting existing claims to one.

For `units`, each participant's item subtotal is `claimed quantity * unit price`; the sum of claim quantities may not exceed the item quantity. For `shared`, claim quantity is always one and the line total is divided among claimers with the existing stable remainder allocation.

A database trigger rejects inserts or updates that would oversubscribe a unit item. This makes the capacity rule true even when two devices claim the last unit concurrently. The API returns `409` with the refreshed split when capacity has changed, allowing the client to explain that another person just claimed the remaining unit.

### API and UI

Claim requests become desired-state mutations:

```ts
type ClaimBody = {
  itemId: string;
  quantity: number;
  participantId?: string;
};
```

`quantity = 0` removes the claim. For shared items, the UI sends zero or one. Organizer and public routes enforce the same core function and authorization rules.

For unit items, each claim row shows `Mine`, `Available`, and the total quantity, with minus/plus controls. Other participants cannot claim already allocated units. For shared items, the row uses `Share item`/`Remove share` and names the current sharers.

## Participants and Pass the Phone

By-item creation accepts `participantCount` and optional `participantNames`, using the existing even-split convention that the organizer is included in the count. Blank names become `Person 2`, `Person 3`, and so on.

The create editor displays `Who's at the table?` for by-item mode, not only even mode. Names remain optional. The saved participants are real server participants, so claims can be written immediately.

Add organizer-only participant endpoints for an open split:

- `POST /api/workspaces/:workspaceId/bill-splits/:splitId/participants` with a name;
- `PATCH /api/workspaces/:workspaceId/bill-splits/:splitId/participants/:participantId` with a name;
- keep the existing delete endpoint.

All endpoints enforce the participant quota and reject locked or settled splits. Public join behavior remains unchanged.

Before `SplitPassAroundView` starts claiming, it presents a compact `Who's at the table?` setup step. The organizer can add, rename, reorder locally for the pass sequence, or remove guests. Starting requires at least two participants unless the organizer explicitly chooses `Continue with just me`. The claim screens then cycle through the live participant array. An `Add person` action remains available before the results step while the split is open.

This setup applies equally to `me` and `each_own`; payer mode changes accounting, not who can participate.

## Editing an Existing Split

Refactor the creation view around a reusable `SplitDraft` state and two modes:

- create: initialized empty or from a scan;
- edit: initialized from an existing `BillSplit`.

An Edit button on split detail opens the same sections and controls used during creation. Editing is allowed while open. A locked split offers Reopen first when no participant is settled; otherwise it explains that settlements must be undone before editing.

The editor covers merchant, date, payer mode, split mode, participants, items, quantities, prices, allocation modes, tax, tip, fee, total, payment channel, and card.

Use stable item IDs in edit requests. Claims survive metadata-only changes and edits to unchanged items. Removing an item removes its claims. Changing an item's price, quantity, or allocation mode requires confirmation and clears only that item's claims. Reducing quantity below the number already claimed is rejected until claims are resolved or the user confirms clearing them.

Add one organizer draft-update route that validates the complete draft and executes related split, item, participant, expense, and claim changes in a D1 batch. This avoids a half-updated split if connectivity drops between separate patch calls. The existing idempotency approach is extended with an edit version so a stale editor receives `409` and refreshes rather than overwriting newer claims.

After a successful edit, dismiss back to split detail and replace the view model with the returned server DTO.

## `each_own` Accounting and Presentation

`payer` is required in new iOS request/response models and remains non-null in storage. Creation tests prove that selecting `each_own` survives the queued request, Worker validation, database write, and owner DTO.

For `each_own`:

- no full-bill organizer expense exists;
- locking records only the organizer's final share as their expense;
- no participant owes or repays the organizer;
- split detail and expense detail show `Your share` and the table's individual shares;
- copy never says `Paid back to you`, `Your net cost`, `Paid the bill`, `Owes you`, or `Nobody has joined yet` when named participants exist.

Legacy rows whose payer is `me` cannot be guessed safely. Open splits can be corrected through the new editor. Locked legacy splits keep their recorded accounting unless reopened, preventing a display-only change from rewriting ledger history.

The expense card must render from the persisted payer mode. If the returned payer is absent from an older server response, show `Split mode unavailable — open to review` instead of silently choosing the `me` reimbursement card.

## Tip Presets

Change the shared preset list to `[10, 12, 15, 20]`. Both chip rendering and active-chip detection consume that single list. Selecting 12% uses the existing rounded-cent calculation and replaces the previous tip inside an explicitly entered total rather than compounding it.

## Error Handling

- Parser failures name the attempted parser and preserve captured OCR text for a retry during the current editor session.
- Server parsing quota failures explain that manual entry and on-device parsing remain available.
- Participant and claim conflicts refresh the split and preserve the current pass-phone position by participant ID, not array index.
- Draft edit conflicts never auto-merge money fields. Refresh and show which server version superseded the draft.
- Offline creation retains the existing durable queue. Editing and participant mutations require a connection in the first version; the UI says so before accepting changes.

## Testing

### iOS

Add an XCTest target and test pure helpers/view models without invoking live Foundation Models or network services.

Required cases:

- leading quantity extraction preserves `XX AMB 23` as the name and quantity one;
- repeated names consume distinct rows and retain their own prices;
- short names remain unverified instead of fuzzy-matching another row;
- Automatic, On-device, and On-server routing obey preference and fallback rules;
- parser metadata and missing legacy metadata decode correctly;
- total reconciliation distinguishes rounding, shortfall, and overshoot;
- create and queued bodies preserve `payer = each_own` and by-item participants;
- edit draft round-trips every supported field;
- pass-phone retains the current participant after a refresh;
- tip preset math recognizes and retotals 12%;
- `each_own` presentation helpers contain no reimbursement language.

### Worker

Use Bun tests for:

- deterministic quantity and price reconstruction from the attached receipt pattern;
- decimal legacy amount fallback;
- participant creation for by-item splits;
- unit claim increments, decrements, capacity, authorization, and concurrent last-unit rejection;
- shared allocation and cent remainders;
- item-scoped claim clearing during edits;
- edit version conflicts and payer-mode expense transitions;
- exact share reconciliation against the selected bill total;
- `each_own` owner DTO and expense behavior.

### Panel

Test quantity controls, conflict refresh, shared-item copy, and public claim request bodies. Existing single-item shared claims remain compatible after migration.

### Verification

Run:

```bash
cd Server && npm run test && npm run typecheck
cd Panel && npm run typecheck && npm run build
cd App && xcodebuild -project Settlr.xcodeproj -scheme Settlr -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug -derivedDataPath build build
```

Then exercise the supplied receipt in the simulator or a physical iOS 26 device in all three parser modes, create an `each_own` by-item split with at least three named people, claim different units of one quantity line, edit the open split, and verify the expense card after locking.

## Rollout and Compatibility

Apply the Worker migration before releasing clients that send quantity claims. The Worker continues accepting the old `{ claimed: boolean }` body during one client transition window, translating `true` to one shared claim and `false` to zero. New DTO fields are additive until the iOS and Panel releases are live.

Release order:

1. Worker migration and backward-compatible APIs.
2. Panel public quantity claims.
3. iOS parser preference, participants, edit flow, quantity claims, accounting presentation, and tip chip.
4. Remove the legacy boolean claim body only after supported clients have moved to desired quantities.

No receipt image is uploaded as part of this design; only OCR text reaches the app server when the user selects or falls back to server parsing.

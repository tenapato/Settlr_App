# Bill Split Reliability and Editing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make receipt parsing, totals, quantity claims, pass-the-phone participation, editing, and `each_own` accounting reliable across the iOS app, Worker API, and public web claim page.

**Architecture:** The Worker remains the source of truth for splits and gains quantity-aware allocation plus organizer participant/draft mutations. iOS uses one reusable draft editor for create/edit, deterministic receipt evidence, and a user-facing On server parser option. Panel consumes the same desired-quantity claim contract. New fields are additive and the Worker temporarily accepts legacy boolean claims.

**Tech Stack:** Swift 5.10/SwiftUI/Foundation Models/Vision/XCTest, Cloudflare Workers/TypeScript/Drizzle/D1/Bun, React 18/TypeScript/Vite.

**Spec:** `docs/superpowers/specs/2026-08-16-bill-split-reliability-editing-design.md`

## Global Constraints

- Product copy says `On server` or `Server parsing`, never Cloudflare.
- Receipt images remain on device; only OCR text may reach the server.
- Existing clients using `{ claimed: boolean }` continue working during rollout.
- `each_own` never creates reimbursement debt or reimbursement copy.
- Unit capacity is enforced by the database under concurrent writes.
- Existing dirty work in any repository must be preserved.

---

### Task 1: Quantity-Aware Server Allocation Core

**Files:**
- Modify: `../Server/src/db/app.schema.ts`
- Create: `../Server/migrations/0039_bill_split_quantity_claims.sql`
- Modify: `../Server/migrations/meta/_journal.json`
- Modify: `../Server/src/lib/billSplit.ts`
- Modify: `../Server/src/lib/billSplitCore.ts`
- Modify: `../Server/src/lib/billSplit.test.ts`

**Interfaces:**
- Produces `BillSplitAllocationMode = "units" | "shared"`.
- Produces claim input `{ itemId: string; participantId: string; quantity: number }`.
- Produces `applyClaimQuantity(db, itemId, participantId, quantity)` and DTO claim quantities.
- Preserves `applyClaim(..., claimed)` as a transition wrapper.

- [ ] **Step 1: Write failing allocation tests**

Add cases proving one participant can take one of three units, two participants can take the remainder, oversubscription fails, shared lines retain even division, and legacy quantity-one claims retain current totals.

```ts
it("allocates only the claimed units", () => {
  const result = calculateSplit({
    items: [{ id: "taco", quantity: 3, unitPriceCents: 10_00, allocationMode: "units" }],
    claims: [
      { itemId: "taco", participantId: "p1", quantity: 1 },
      { itemId: "taco", participantId: "p2", quantity: 2 },
    ],
    participants: ["p1", "p2"],
    extrasCents: 0,
  });
  expect(result.shares.map((s) => s.itemsCents)).toEqual([10_00, 20_00]);
});
```

- [ ] **Step 2: Run the focused test and verify RED**

Run: `cd ../Server && bun test src/lib/billSplit.test.ts`
Expected: type/behavior failures because allocation mode and claim quantity do not exist.

- [ ] **Step 3: Add schema and migration**

Add `allocationMode` to items with default `shared`, `quantity` to claims with default `1`, and a trigger that aborts a `units` insert/update when aggregate claim quantity exceeds item quantity. Migration existing items to `units` only where `quantity > 1` and no multi-participant legacy claim exists; otherwise keep `shared` to preserve old bills.

- [ ] **Step 4: Implement quantity math and mutation**

For unit mode, calculate `claim.quantity * unitPriceCents`; for shared mode, ignore quantities beyond one and keep stable even distribution. Desired quantity zero deletes the claim. Convert trigger failures to a typed capacity conflict.

- [ ] **Step 5: Run allocation tests and typecheck**

Run: `cd ../Server && bun test src/lib/billSplit.test.ts && npm run typecheck`
Expected: PASS.

- [ ] **Step 6: Commit Server changes**

```bash
git -C ../Server add src/db/app.schema.ts migrations src/lib/billSplit.ts src/lib/billSplitCore.ts src/lib/billSplit.test.ts
git -C ../Server commit -m "feat: support quantity-aware split claims"
```

### Task 2: Server Receipt Evidence and Parser Metadata

**Files:**
- Modify: `../Server/src/lib/receiptParser.ts`
- Modify: `../Server/src/lib/receiptParser.test.ts`
- Modify: `../Server/src/routes/billSplits.ts`

**Interfaces:**
- Produces `verification: "verified" | "unverified"` per scanned item.
- Produces response `parser: "server"`.
- Deterministically reads only a leading quantity token and preserves trailing digits in item names.

- [ ] **Step 1: Add failing receipt regression tests**

Use the attached pattern and assert `1   XX AMB 23   105.00` becomes name `XX AMB 23`, quantity `1`, price `10500`. Add an unmatched legacy decimal test proving `"145.00"` is `14500`, not `145`.

- [ ] **Step 2: Verify RED**

Run: `cd ../Server && bun test src/lib/receiptParser.test.ts`
Expected: missing verification/parser fields and incorrect deterministic quantity behavior.

- [ ] **Step 3: Implement evidence extraction**

Extend printed rows with `leadingQuantity`; strip only that token from labels; rebuild matched items from printed quantity and line total. Mark exact/conservative matches verified and unmatched items unverified. Route adds `parser: "server"`.

- [ ] **Step 4: Fix legacy decimal fallback**

Route all string amounts through `printedMoneyToCents`; numeric `*Cents` remains integer cents for compatibility.

- [ ] **Step 5: Verify parser suite**

Run: `cd ../Server && bun test src/lib/receiptParser.test.ts && npm run typecheck`
Expected: PASS.

- [ ] **Step 6: Commit Server changes**

```bash
git -C ../Server add src/lib/receiptParser.ts src/lib/receiptParser.test.ts src/routes/billSplits.ts
git -C ../Server commit -m "fix: verify receipt quantity and money from OCR rows"
```

### Task 3: Participant and Complete Draft APIs

**Files:**
- Modify: `../Server/src/routes/billSplits.ts`
- Modify: `../Server/src/index.ts`
- Modify: `../Server/src/lib/billSplitCore.ts`
- Modify: `../Server/src/db/app.schema.ts`
- Create: `../Server/migrations/0040_bill_split_edit_version.sql`
- Create: `../Server/src/lib/billSplitDraft.test.ts`
- Modify: `../Server/ROUTES.md`
- Modify: `../Server/RULES.md`

**Interfaces:**
- Produces `POST/PATCH .../participants` organizer routes.
- Produces `PUT .../draft` with `version`, stable optional item IDs, all editable split fields, and returned owner DTO.
- Create accepts by-item `participantCount`/`participantNames`.

- [ ] **Step 1: Write failing core/handler tests**

Cover by-item named guest creation, participant quota/open checks, metadata-only claim preservation, item-scoped claim clearing, stale version `409`, `me -> each_own` expense deletion, and `each_own -> me` expense creation.

- [ ] **Step 2: Verify RED**

Run: `cd ../Server && bun test src/lib/billSplitDraft.test.ts`
Expected: new draft functions/routes missing.

- [ ] **Step 3: Add edit version and validation core**

Add non-negative `version` default zero. A full draft mutation conditionally increments the version, preserves stable unchanged items, deletes claims only for removed/financially changed items, updates participants by stable ID, and reconciles the mirrored expense to payer mode.

- [ ] **Step 4: Add participant routes**

Create/rename/delete remain open-only, quota-bound, encrypted, and return the refreshed owner DTO.

- [ ] **Step 5: Extend creation for by-item participants**

Honor count/names for all split modes. Keep organizer included in count and numbered blank guest names.

- [ ] **Step 6: Wire/document routes and verify**

Run: `cd ../Server && npm run test && npm run typecheck`
Expected: PASS.

- [ ] **Step 7: Commit Server changes**

```bash
git -C ../Server add src migrations ROUTES.md RULES.md
git -C ../Server commit -m "feat: edit open splits and manage participants"
```

### Task 4: Quantity Claims in Server Routes and Panel

**Files:**
- Modify: `../Server/src/routes/billSplits.ts`
- Modify: `../Server/src/routes/billSplitPublic.ts`
- Modify: `../Panel/src/lib/splitApi.ts`
- Modify: `../Panel/src/routes/split/PublicSplit.tsx`
- Modify: `../Panel/src/components/domain/SplitItemsCard.tsx`
- Modify: `../Panel/src/lib/splits.test.ts`

**Interfaces:**
- New clients send `{ itemId, quantity, participantId? }`.
- Old clients may send `{ itemId, claimed }`.
- DTO item exposes `allocationMode`, `claimedQuantity`, `availableQuantity`; participant exposes per-item claim quantities.

- [ ] **Step 1: Add failing Server compatibility tests and Panel helper tests**

Assert boolean bodies translate to zero/one and quantity bodies return `409` with refreshed split on capacity conflict. Add pure Panel tests for plus/minus limits and shared copy.

- [ ] **Step 2: Verify RED**

Run: `cd ../Server && npm run test`
Run: `cd ../Panel && npm test -- --run src/lib/splits.test.ts`
Expected: missing desired-quantity interfaces.

- [ ] **Step 3: Implement route compatibility**

Normalize both body shapes to desired quantity and call the shared mutation. Public participant identity continues to come only from `X-Split-Secret`.

- [ ] **Step 4: Implement Panel controls**

Render unit plus/minus controls with Mine/Available counts; render explicit Share item for shared mode. On `409`, replace state with returned split and show capacity copy.

- [ ] **Step 5: Verify Panel and Server**

Run: `cd ../Server && npm run test && npm run typecheck`
Run: `cd ../Panel && npm run typecheck && npm run build`
Expected: PASS.

- [ ] **Step 6: Commit both repositories**

```bash
git -C ../Server add src/routes && git -C ../Server commit -m "feat: expose desired quantity claims"
git -C ../Panel add src && git -C ../Panel commit -m "feat: claim individual item quantities"
```

### Task 5: iOS Test Target, Parser Preference, and Receipt Regressions

**Files:**
- Modify: `Settlr.xcodeproj/project.pbxproj`
- Modify: `Settlr/Views/Main/Settings/SettingsView.swift`
- Modify: `Settlr/ViewModels/BillSplitVM.swift`
- Modify: `Settlr/Views/Main/Split/OnDeviceReceiptParser.swift`
- Modify: `Settlr/Views/Main/Split/ReceiptReconciler.swift`
- Modify: `Settlr/Models/BillSplit.swift`
- Create: `SettlrTests/ReceiptEvidenceTests.swift`
- Create: `SettlrTests/ParserPreferenceTests.swift`

**Interfaces:**
- Produces `ReceiptParserPreference` raw values `automatic`, `onDevice`, `server`.
- Produces `ReceiptParserKind` values `onDevice`, `server`.
- `scanReceipt` routes according to preference and reports parser metadata.

- [ ] **Step 1: Add XCTest target and failing tests**

Test the `XX AMB 23` leading-quantity case, repeated names, short unverified names, legacy metadata decoding, and parser preference routing through injected parser closures.

- [ ] **Step 2: Verify RED**

Run the new test target with `xcodebuild test`; expect missing types/initializers.

- [ ] **Step 3: Implement preference and settings UI**

Add a Receipts picker labelled Automatic, On device, On server. Never display Cloudflare. On-device-only fails with actionable copy rather than uploading text.

- [ ] **Step 4: Implement deterministic receipt quantity evidence**

Parse the leading quantity before stripping it, preserve trailing item digits, and attach verification state. Both parser paths still pass through the reconciler.

- [ ] **Step 5: Verify iOS tests/build**

Run: `xcodebuild test -project Settlr.xcodeproj -scheme Settlr -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build`
Expected: PASS.

- [ ] **Step 6: Commit App changes**

```bash
git add Settlr.xcodeproj Settlr SettlrTests
git commit -m "fix: make receipt parsing selectable and deterministic"
```

### Task 6: Reusable iOS Draft Editor and Reconciliation Gate

**Files:**
- Create: `Settlr/Views/Main/Split/SplitDraft.swift`
- Modify: `Settlr/Views/Main/Split/SplitCreateSheet.swift`
- Modify: `Settlr/Views/Main/Split/SplitDetailView.swift`
- Modify: `Settlr/ViewModels/BillSplitVM.swift`
- Modify: `Settlr/Network/Endpoints.swift`
- Modify: `Settlr/Models/BillSplit.swift`
- Create: `SettlrTests/SplitDraftTests.swift`

**Interfaces:**
- Produces `SplitDraft.init(scan:)`, `SplitDraft.init(split:)`, `makeCreateBody()`, and `makeEditBody(version:)`.
- Produces VM `updateDraft(...)`.

- [ ] **Step 1: Add failing draft round-trip/reconciliation tests**

Test every editable field, mismatch tolerance, shortfall/overshoot decisions, stable item IDs, payer mode, participants, payment channel, and card.

- [ ] **Step 2: Verify RED**

Run the focused XCTest target and confirm missing `SplitDraft` failures.

- [ ] **Step 3: Extract draft state and reuse the form**

Replace scattered create-only state with `SplitDraft`. Edit mode changes title/button copy and calls `PUT .../draft`; success returns to detail.

- [ ] **Step 4: Add mismatch review UI**

Show calculated/selected totals, signed difference, unverified rows, and explicit Keep receipt total/Use calculated total actions. Send acknowledgement only after confirmation.

- [ ] **Step 5: Add Edit/Reopen entry points**

Open splits edit directly. Locked splits with no settlements offer Reopen; settled splits explain the prerequisite.

- [ ] **Step 6: Verify tests/build and commit**

Run iOS tests and build; commit as `feat: edit complete bill split drafts`.

### Task 7: iOS Participants, Pass-the-Phone, and Quantity Controls

**Files:**
- Modify: `Settlr/Views/Main/Split/SplitCreateSheet.swift`
- Modify: `Settlr/Views/Main/Split/SplitPassAroundView.swift`
- Modify: `Settlr/Views/Main/Split/SplitDetailView.swift`
- Modify: `Settlr/ViewModels/BillSplitVM.swift`
- Modify: `Settlr/Network/Endpoints.swift`
- Modify: `Settlr/Models/BillSplit.swift`
- Create: `SettlrTests/PassAroundStateTests.swift`

**Interfaces:**
- Produces participant add/rename/remove VM methods.
- Produces desired quantity claim method.
- Pass-around tracks `participantId`, never only an array index.

- [ ] **Step 1: Add failing participant/pass-state tests**

Test by-item create bodies with named guests, minimum setup behavior, current participant preservation after refresh, unit control bounds, and shared action state.

- [ ] **Step 2: Verify RED**

Run focused XCTest and confirm missing participant/quantity APIs.

- [ ] **Step 3: Show table participants for by-item create**

Reuse the existing guest-name card for all modes and send count/names for by-item splits.

- [ ] **Step 4: Add pass-around setup and live participant management**

Before claims, show Who's at the table, add/rename/remove, and require two people unless Continue with just me is chosen. Preserve current person by ID on every server refresh.

- [ ] **Step 5: Add unit/shared claim controls**

Unit rows expose plus/minus and remaining capacity; shared rows expose explicit sharing. Capacity conflicts refresh without moving to another participant.

- [ ] **Step 6: Verify tests/build and commit**

Run iOS tests/build; commit as `feat: add people and quantity claims to pass around`.

### Task 8: `each_own` Invariants and 12% Tip

**Files:**
- Modify: `Settlr/Views/Main/Split/ExpenseSplitSection.swift`
- Modify: `Settlr/Views/Main/Split/SplitDetailView.swift`
- Modify: `Settlr/Views/Main/Split/SplitCreateSheet.swift`
- Modify: `Settlr/Models/BillSplit.swift`
- Modify: `Settlr/Network/PendingSplitQueue.swift`
- Create: `SettlrTests/EachOwnPresentationTests.swift`
- Create: `SettlrTests/TipPresetTests.swift`

**Interfaces:**
- Produces shared `TipPreset.values = [10, 12, 15, 20]`.
- Produces pure presentation state that distinguishes `me`, `each_own`, and missing legacy payer.

- [ ] **Step 1: Add failing payer queue/presentation and tip tests**

Assert queued encode/decode preserves `each_own`, missing payer produces review copy rather than reimbursement copy, prohibited reimbursement phrases never occur for each-own, and 12% is recognized/retotaled.

- [ ] **Step 2: Verify RED**

Run focused XCTest and confirm failures for missing shared helpers/12%.

- [ ] **Step 3: Implement required payer state and safe legacy presentation**

Keep network decoding backward compatible but convert to a domain payer enum before rendering. Each-own cards show Your share and individual shares only.

- [ ] **Step 4: Centralize tip presets and add 12%**

Use one preset list for chips and active detection; preserve existing replacement arithmetic.

- [ ] **Step 5: Verify tests/build and commit**

Run iOS tests/build; commit as `fix: preserve each-own accounting and add 12 percent tip`.

### Task 9: Cross-Repository Verification and Luna Reviews

**Files:**
- Review all files changed in Tasks 1-8.

**Interfaces:** None; this is the release gate.

- [ ] **Step 1: Dispatch Luna code reviewers**

Use Luna with medium reasoning for all code-review passes. Hard implementation or analysis findings are handed to Sol with high reasoning. Review against the spec, not only the diff.

- [ ] **Step 2: Apply verified review findings test-first**

For every accepted defect, add/reproduce a failing test, implement the smallest correction, and rerun the focused suite.

- [ ] **Step 3: Run full verification**

```bash
cd ../Server && npm run test && npm run typecheck
cd ../Panel && npm run typecheck && npm run build
cd . && xcodebuild test -project Settlr.xcodeproj -scheme Settlr -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build
cd . && xcodebuild -project Settlr.xcodeproj -scheme Settlr -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug -derivedDataPath build build
```

- [ ] **Step 4: Check repository state and summarize commits**

Run `git status --short` and `git log -5 --oneline` in App, Server, and Panel. Confirm only intended changes remain.

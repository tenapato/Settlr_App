# Bill Split Payment Method and Status Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let organizers change cash/card payment metadata in any split state, synchronize every linked expense atomically, and label closed `each_own` splits as `Completed`.

**Architecture:** Add a small Server policy module that validates payment-method requests and determines when/for how much a split-owned expense must exist. A versioned organizer-only route batches split and owned-expense writes, while existing draft/lightweight edit paths reuse the same ledger rules. iOS adds payer-aware summary presentation and a reusable organizer payment sheet launched from split detail.

**Tech Stack:** Cloudflare Workers, TypeScript, Drizzle ORM/D1, Bun tests, Swift 6, SwiftUI, XCTest source tests.

**Spec:** `docs/superpowers/specs/2026-08-18-bill-split-payment-method-and-status-design.md`

## Global Constraints

- The payment selector changes only the organizer's own ledger metadata for `each_own`.
- Public and pass-the-phone participant screens must never expose workspace cards.
- Split and owned-expense writes succeed or roll back together.
- Payment editing works for `open`, `locked`, and `settled` without changing status, claims, frozen shares, or settlements.
- No schema migration is required.
- Do not run `xcodebuild`; the user will build and manually test the App.
- Keep all App and Server changes unstaged and uncommitted.
- Use no more than five subagents for execution and review.

---

## File Structure

### Server

- Create `src/lib/billSplitPaymentMethod.ts`: request validation and pure owned-expense policy.
- Create `src/lib/billSplitPaymentMethod.test.ts`: validation and expense-policy tests.
- Modify `src/routes/billSplits.ts`: payment-method handler, atomic writes, list payer field, and existing edit synchronization.
- Modify `src/index.ts`: route registration before the generic split route.
- Modify `src/lib/billSplitDraft.test.ts`: database-level atomicity and existing-edit invariant coverage.

### App

- Modify `Settlr/Models/BillSplit.swift`: summary payer decoding, status presentation, and payment mutation body.
- Modify `Settlr/Network/Endpoints.swift`: payment-method endpoint.
- Modify `Settlr/Views/Main/Split/SplitListView.swift`: consume payer-aware status presentation.
- Modify `Settlr/ViewModels/BillSplitVM.swift`: versioned mutation and conflict refresh.
- Create `Settlr/Views/Main/Split/SplitPaymentMethodSheet.swift`: reusable organizer-only payment editor.
- Modify `Settlr/Views/Main/Split/SplitDetailView.swift`: persistent `You paid with` row and sheet presentation.
- Modify `SettlrTests/EachOwnPresentationTests.swift`: payer-aware summary/status cases.
- Create `SettlrTests/SplitPaymentMethodTests.swift`: request and editor-state tests.
- Modify `Settlr.xcodeproj/project.pbxproj`: register the new App and test sources.
- Modify `scripts/check-app-source-regressions.sh`: static contract for payment row, endpoint, and participant privacy.

---

### Task 1: Server Payment Policy

**Files:**
- Create: `Server/src/lib/billSplitPaymentMethod.ts`
- Create: `Server/src/lib/billSplitPaymentMethod.test.ts`

**Interfaces:**
- Produces:

```ts
export type SplitPaymentMethod = {
  paymentChannel: "cash" | "credit_card";
  creditCardId: string | null;
};

export type ValidatedSplitPaymentMethod = SplitPaymentMethod & { version: number };

export function validateSplitPaymentMethodBody(
  raw: unknown,
): { value: ValidatedSplitPaymentMethod } | { error: string; status: 400 };

export function expectedOwnedExpense(input: {
  payer: "me" | "each_own";
  status: "open" | "locked" | "settled";
  totalCents: number;
  organizerShareCents: number;
}): { shouldExist: boolean; amountCents: number; notes: "Bill split" | "Bill split · your share" };
```

- Consumes no route/database state.

- [ ] **Step 1: Write failing validation tests**

Cover exact non-negative `version`, cash clearing a supplied card ID, credit card requiring a non-empty ID, and rejecting unknown channels.

```ts
expect(validateSplitPaymentMethodBody({
  version: 3,
  paymentChannel: "cash",
  creditCardId: "stale-card",
})).toEqual({ value: { version: 3, paymentChannel: "cash", creditCardId: null } });
```

- [ ] **Step 2: Run RED**

Run: `bun test src/lib/billSplitPaymentMethod.test.ts`

Expected: FAIL because the module/functions do not exist.

- [ ] **Step 3: Implement minimal request validation**

Use exact integer/string checks. Do not silently convert an invalid channel to cash.

- [ ] **Step 4: Write failing owned-expense policy tests**

Assert full total for `me` in every status, no expense for open `each_own`, and frozen organizer share for closed `each_own`.

```ts
expect(expectedOwnedExpense({
  payer: "each_own",
  status: "locked",
  totalCents: 10_000,
  organizerShareCents: 3_250,
})).toEqual({
  shouldExist: true,
  amountCents: 3_250,
  notes: "Bill split · your share",
});
```

- [ ] **Step 5: Implement the pure policy and run GREEN**

Run: `bun test src/lib/billSplitPaymentMethod.test.ts`

Expected: all focused tests pass.

- [ ] **Step 6: Leave changes unstaged**

Run: `git diff --check && git diff --cached --quiet`

Expected: clean diff check and empty index. Do not commit.

---

### Task 2: Atomic Server Mutation and Ledger Invariants

**Files:**
- Modify: `Server/src/routes/billSplits.ts`
- Modify: `Server/src/index.ts`
- Modify: `Server/src/lib/billSplitDraft.test.ts`
- Test: `Server/src/lib/billSplitPaymentMethod.test.ts`

**Interfaces:**
- Consumes `validateSplitPaymentMethodBody` and `expectedOwnedExpense` from Task 1.
- Produces:

```ts
export async function handlePatchBillSplitPaymentMethod(
  req: WorkspaceRequest,
  env: Env,
): Promise<Response>;
```

- Registers `PATCH /api/workspaces/:workspaceId/bill-splits/:splitId/payment-method` before `/:splitId`.
- Adds `payer` to each `handleListBillSplits` summary object.

- [ ] **Step 1: Write failing mutation/invariant tests**

Cover:

- open/locked/settled `me` updating split and owned expense;
- open `each_own` updating only the split;
- locked `each_own` preserving the frozen organizer expense amount;
- missing expected owned expense creation/linking;
- cash clearing card ID;
- foreign, archived, and missing card rejection;
- stale version rolling back both split and expense;
- claims, participant shares, settlements, and status remaining unchanged.

Use the existing in-memory SQLite helpers in `billSplitDraft.test.ts` for transaction/CAS assertions.

- [ ] **Step 2: Run RED**

Run: `bun test src/lib/billSplitPaymentMethod.test.ts src/lib/billSplitDraft.test.ts`

Expected: FAIL for the absent handler/atomic synchronization behavior.

- [ ] **Step 3: Implement the organizer-only route**

Load the split, apply `organizerOnlyResponse`, validate the body, validate an assigned card with `assertCardAssignable`, compute the organizer's frozen share, and build one D1 batch:

```ts
db.update(billSplit).set({
  paymentChannel: value.paymentChannel,
  creditCardId: value.creditCardId,
  version: sql`case when ${billSplit.version} = ${value.version}
    and ${billSplit.status} = ${loaded.split.status}
    then ${billSplit.version} + 1 else -1 end`,
  updatedAt: now,
});
```

Update/create the owned expense in the same batch according to `expectedOwnedExpense`. Convert the named version-check failure to `409 { code: "stale_version", split }`.

- [ ] **Step 4: Synchronize existing edit paths**

Ensure the complete draft route continues to update all expense-backed fields. Extend lightweight patch batching so supported merchant/date/amount changes update the owned expense in the same batch. Locking and reopening `each_own` must use the same expected-expense policy without touching unrelated expenses.

- [ ] **Step 5: Add payer to list summaries and register the endpoint**

Return `payer: r.payer === "each_own" ? "each_own" : "me"` and register the specific route before the generic split route.

- [ ] **Step 6: Run focused and full GREEN verification**

Run:

```bash
bun test src/lib/billSplitPaymentMethod.test.ts src/lib/billSplitDraft.test.ts
bun test
npm run typecheck
git diff --check
git diff --cached --quiet
```

Expected: zero failures, typecheck exit 0, empty index. Do not commit.

---

### Task 3: iOS Payer-Aware Status and Wire Models

**Files:**
- Modify: `App/Settlr/Models/BillSplit.swift`
- Modify: `App/Settlr/Network/Endpoints.swift`
- Modify: `App/Settlr/Views/Main/Split/SplitListView.swift`
- Modify: `App/SettlrTests/EachOwnPresentationTests.swift`
- Create: `App/SettlrTests/SplitPaymentMethodTests.swift`
- Modify: `App/scripts/check-app-source-regressions.sh`

**Interfaces:**
- Produces:

```swift
struct BillSplitPaymentMethodBody: Encodable {
    let version: Int
    let paymentChannel: String
    let creditCardId: String?
}

enum BillSplitSummaryStatusPresentation {
    static func label(for summary: BillSplitSummary) -> String
}

static func billSplitPaymentMethod(_ wsId: String, _ splitId: String) -> String
```

- `BillSplitSummary.payer` is optional/legacy-safe and exposes a derived payer mode without defaulting missing data to organizer-paid.

- [ ] **Step 1: Write failing status and encoding tests**

Cover open `Claiming`, closed `each_own` `Completed`, locked organizer-paid owed/`Collecting`, settled organizer-paid `Settled`, legacy missing payer, and nullable card encoding.

```swift
XCTAssertEqual(
    BillSplitSummaryStatusPresentation.label(for: completedEachOwn),
    "Completed"
)
```

- [ ] **Step 2: Verify RED without building the app**

Add focused static/source assertions first and run `./scripts/check-app-source-regressions.sh`; expect failure for missing types/endpoint. Do not run `xcodebuild`.

- [ ] **Step 3: Implement models and pure presentation**

Decode missing summary payer as unavailable, not `me`. Preserve existing amount-owed copy for locked organizer-paid summaries.

- [ ] **Step 4: Update SplitListView to consume the helper**

Remove the local status switch and use the tested payer-aware presentation for label/color.

- [ ] **Step 5: Run static GREEN checks**

Run:

```bash
./scripts/check-app-source-regressions.sh
swiftc -parse Settlr/Models/BillSplit.swift Settlr/Network/Endpoints.swift Settlr/Views/Main/Split/SplitListView.swift SettlrTests/EachOwnPresentationTests.swift SettlrTests/SplitPaymentMethodTests.swift
git diff --check
git diff --cached --quiet
```

Expected: exit 0 and empty index. Do not build or commit.

---

### Task 4: iOS Payment Method Editor

**Files:**
- Modify: `App/Settlr/ViewModels/BillSplitVM.swift`
- Create: `App/Settlr/Views/Main/Split/SplitPaymentMethodSheet.swift`
- Modify: `App/Settlr/Views/Main/Split/SplitDetailView.swift`
- Modify: `App/SettlrTests/SplitPaymentMethodTests.swift`
- Modify: `App/Settlr.xcodeproj/project.pbxproj`
- Modify: `App/scripts/check-app-source-regressions.sh`

**Interfaces:**
- Consumes the endpoint/body from Task 3.
- Produces:

```swift
@MainActor
func updatePaymentMethod(
    workspaceId: String,
    splitId: String,
    body: BillSplitPaymentMethodBody
) async -> Bool

struct SplitPaymentMethodSheet: View {
    let workspaceId: String
    let split: BillSplit
    let vm: BillSplitVM
    let onSaved: () -> Void
}
```

- [ ] **Step 1: Write failing editor-state tests**

Create a pure state helper proving cash needs no card, credit card requires a selection, changing to cash clears the card, current copy resolves from card data, and a stale refresh does not discard the pending selection.

- [ ] **Step 2: Run RED static/source checks**

Add regression assertions for the endpoint call, persistent detail row, owner-only sheet, and absence from `PublicSplitClaimView.swift` and `SplitPassAroundView.swift`. Run the source script and observe the intended failure.

- [ ] **Step 3: Implement the view-model mutation**

Use the existing `mutate` path for success. On `409`, fetch/adopt the latest split, set a retry message, and return false without mutating sheet-local channel/card state.

- [ ] **Step 4: Implement the compact sheet**

Reuse `SegmentedToggle`, `FormCard`, and `FormMenuRow`. Load cached cards first and refresh from `Endpoints.creditCards`. Filter archived cards for new choices. Disable Save for credit card without a selected card and while `vm.isSaving`.

- [ ] **Step 5: Add the persistent detail row**

Show `You paid with` for open, locked, and settled organizer detail views, resolving cash/debit or selected card copy. Tapping opens `SplitPaymentMethodSheet`. Do not add this row or card data to public/pass-around participant views.

- [ ] **Step 6: Register files and run static GREEN checks**

Run:

```bash
./scripts/check-app-source-regressions.sh
git diff --name-only -- '*.swift' | xargs swiftc -parse
plutil -lint Settlr.xcodeproj/project.pbxproj
git diff --check
git diff --cached --quiet
```

Expected: all exit 0, project file valid, index empty. Do not run `xcodebuild` and do not commit.

---

### Task 5: Cross-Repository Review and Verification

**Files:**
- Review every App/Server file changed by Tasks 1–4.

**Interfaces:**
- Consumes the complete feature.
- Produces no new interface unless a review finding requires a scoped fix.

- [ ] **Step 1: Requirements review**

Check every spec rule: all statuses, organizer-only access, `each_own` organizer share, atomic linked expense, payer-aware status, privacy, offline behavior, and empty indexes.

- [ ] **Step 2: Code-quality and concurrency review**

Review D1 batch ordering, version rollback, ownership targeting, card validation, legacy repair, SwiftUI state lifetime, 409 recovery, and card privacy. Critical/Important findings block completion.

- [ ] **Step 3: Fix findings with RED/GREEN evidence**

For each finding, add a failing focused test/static assertion, implement the smallest fix, and rerun the focused test before the full suites.

- [ ] **Step 4: Final Server verification**

Run:

```bash
cd Server
bun test
npm run typecheck
git diff --check
git diff --cached --quiet
```

- [ ] **Step 5: Final App verification without building**

Run:

```bash
cd App
./scripts/check-app-source-regressions.sh
git diff --name-only -- '*.swift' | xargs swiftc -parse
plutil -lint Settlr.xcodeproj/project.pbxproj
git diff --check
git diff --cached --quiet
```

- [ ] **Step 6: Handoff**

Report tests/checks, deferred `xcodebuild` and manual scenarios, and confirm every change remains unstaged and uncommitted.

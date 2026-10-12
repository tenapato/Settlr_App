# Guided bill split and live Dashboard signal implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the bloated bill-split form with the approved Setup, Items, and Confirm flow, and keep the custom Dashboard signal carousel visible when spending is zero.

**Architecture:** `SplitCreateSheet` remains the owner of draft, scanner recovery, card loading, alerts, and submission. Pure guided-flow policy and small step views make navigation and validation testable without moving endpoint calls into presentation code. The Dashboard keeps its spending insight engine and uses a separate factual fallback builder when real spending insights are unavailable.

**Tech stack:** Swift 6, SwiftUI, Observation, XCTest, the existing Settlr networking and offline queue, shell source checks, Xcode CLI generic iOS builds.

**Spec:** `docs/superpowers/specs/2026-09-01-guided-bill-split-and-live-dashboard-signal-design.md`

## Global constraints

- Use the existing `feat/signal-black-redesign-spec` branch. Do not create another branch or worktree.
- Do not change Server routes, DTOs, accounting rules, receipt parsing, settlement behavior, public claims, QR sharing, or feature gates.
- Keep the current `SplitCreateSheet` initializer so `SplitScanFlow` and `SplitDetailView` continue to compile.
- Preserve the offline queue, stable idempotency key, stale-edit version checks, claim-clearing confirmation, and payer-correct Result states.
- Do not launch Xcode, boot a simulator, or run simulator tests. The user owns the final simulator and motion pass.
- Compile with the signing-disabled generic iOS command at checkpoints:

```bash
xcodebuild -quiet -project Settlr.xcodeproj -scheme Settlr -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath /tmp/settlr-codex-derived CODE_SIGNING_ALLOWED=NO build
```

- Add XCTest coverage even though the agent will not run it. The generic build and source checks are the agent-side verification allowed by the user.
- Use Signal Black tokens, SF Symbols, 44-point minimum targets, tabular money, native navigation, and Reduce Motion behavior from the approved design system.
- Do not stage or commit `.superpowers/brainstorm/`.

---

## File structure

New production files:

- `Settlr/Views/Main/Split/GuidedSplitFlowState.swift`: typed steps, validation order, dirty snapshot, card-load state, and small presentation models.
- `Settlr/Views/Main/Split/SplitGuidedComponents.swift`: progress rail, compact receipt header, and sticky task action.
- `Settlr/Views/Main/Split/SplitEditorSheets.swift`: receipt, people, item, and money editors with sheet-local copies.
- `Settlr/Views/Main/Split/SplitSetupStepView.swift`: payer, division, people, payment, and receipt-detail entry point.
- `Settlr/Views/Main/Split/SplitItemsStepView.swift`: dense receipt line list and Needs review filter.
- `Settlr/Views/Main/Split/SplitConfirmStepView.swift`: total, extras, reconciliation, summary, and final action.
- `Settlr/Models/DashboardFallbackSignal.swift`: factual low-data Dashboard signals and section mode resolution.

New test files:

- `SettlrTests/GuidedSplitFlowStateTests.swift`
- `SettlrTests/GuidedSplitPresentationTests.swift`

Modified production files:

- `Settlr/Views/Main/Split/SplitDraft.swift`
- `Settlr/Views/Main/Split/SplitCreateSheet.swift`
- `Settlr/Views/Main/Split/SplitScanFlow.swift`
- `Settlr/Views/Main/Dashboard/SpendingInsightsStrip.swift`
- `SettlrTests/DashboardSummaryTests.swift`
- `Settlr.xcodeproj/project.pbxproj`
- `scripts/check-signal-redesign.sh`
- `docs/design-system/SETTLR_SIGNAL.md`
- `docs/design-system/settlr-signal-components.html`

---

### Task 1: Add the pure guided-flow contract

**Files:**

- Create: `Settlr/Views/Main/Split/GuidedSplitFlowState.swift`
- Create: `SettlrTests/GuidedSplitFlowStateTests.swift`
- Modify: `Settlr/Views/Main/Split/SplitDraft.swift`
- Modify: `Settlr.xcodeproj/project.pbxproj`

**Interfaces:**

- Consumes: `SplitDraft`, `BillSplitPayerMode`, `NetworkMonitor` values supplied by the coordinator.
- Produces: `GuidedSplitStep`, `GuidedSplitField`, `GuidedSplitValidationIssue`, `GuidedSplitFlowPolicy`, `GuidedSplitSubmissionSnapshot`, and `SplitCardLoadState`.

- [ ] **Step 1: Add failing policy tests**

Create `GuidedSplitFlowStateTests.swift` with concrete cases for routing, validation, and dirty state:

```swift
import XCTest
@testable import Settlr

final class GuidedSplitFlowStateTests: XCTestCase {
    func testByItemSetupRoutesThroughItems() {
        XCTAssertEqual(GuidedSplitFlowPolicy.nextStep(splitMode: "by_item"), .items)
        XCTAssertEqual(GuidedSplitFlowPolicy.backStep(from: .confirm, splitMode: "by_item"), .items)
    }

    func testEvenSetupSkipsItems() {
        XCTAssertEqual(GuidedSplitFlowPolicy.nextStep(splitMode: "even"), .confirm)
        XCTAssertEqual(GuidedSplitFlowPolicy.backStep(from: .confirm, splitMode: "even"), .setup)
    }

    func testUnverifiedPricedItemDoesNotBlockButMismatchDoes() {
        var draft = SplitDraft()
        draft.merchant = "Cafe"
        draft.items = [.init(name: "Lunch", quantity: 1, unitPriceCents: 1_000, verification: .unverified)]
        draft.selectedTotalCents = 2_000

        XCTAssertNil(GuidedSplitFlowPolicy.firstIssue(on: .items, draft: draft, totalEdited: true, isEditing: false, isOnline: true))
        XCTAssertEqual(
            GuidedSplitFlowPolicy.firstIssue(on: .confirm, draft: draft, totalEdited: true, isEditing: false, isOnline: true)?.field,
            .reconciliation
        )
    }

    func testScannerImportIsDirtyWithoutAFieldEdit() {
        let draft = SplitDraft()
        let snapshot = GuidedSplitSubmissionSnapshot(draft: draft, totalEdited: false)
        XCTAssertTrue(snapshot.hasUnsavedChanges(draft: draft, totalEdited: false, importedReceipt: true))
        XCTAssertFalse(snapshot.hasUnsavedChanges(draft: draft, totalEdited: false, importedReceipt: false))
    }
}
```

- [ ] **Step 2: Register the test and production files in the Xcode project**

Add `PBXFileReference`, `PBXBuildFile`, group, and Sources entries following the existing explicit entries for `SplitDraft.swift` and `SplitDraftTests.swift`. Do not rely on filesystem synchronization because this project uses explicit groups.

- [ ] **Step 3: Implement the policy types**

Make `SplitDraft` equatable and add the following concrete contract in `GuidedSplitFlowState.swift`:

```swift
enum GuidedSplitStep: Hashable { case setup, items, confirm }

enum GuidedSplitField: Equatable {
    case merchant, payer, paymentMethod, total, items, reconciliation, onlineEdit
}

struct GuidedSplitValidationIssue: Equatable {
    let step: GuidedSplitStep
    let field: GuidedSplitField
    let message: String
}

enum SplitCardLoadState: Equatable {
    case idle
    case refreshing
    case failed(String)
}

struct GuidedSplitSubmissionSnapshot: Equatable {
    let draft: SplitDraft
    let totalEdited: Bool

    func hasUnsavedChanges(draft: SplitDraft, totalEdited: Bool, importedReceipt: Bool) -> Bool {
        importedReceipt || self.draft != draft || self.totalEdited != totalEdited
    }
}
```

Implement `GuidedSplitFlowPolicy.nextStep(splitMode:)`, `backStep(from:splitMode:)`, and `firstIssue(on:draft:totalEdited:isEditing:isOnline:)`. Use the validation order from the spec. On Confirm, check merchant, by-item lines or even total, payer, selected card, reconciliation, then online editing. Do not treat `draft.unverifiedItems` as a blocker.

- [ ] **Step 4: Run static and compiler checks**

Run:

```bash
git diff --check
./scripts/check-app-source-regressions.sh
xcodebuild -quiet -project Settlr.xcodeproj -scheme Settlr -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath /tmp/settlr-codex-derived CODE_SIGNING_ALLOWED=NO build
```

Expected: all commands exit 0. The XCTest file is registered for the user's later runtime test pass.

- [ ] **Step 5: Commit**

```bash
git add Settlr/Views/Main/Split/GuidedSplitFlowState.swift Settlr/Views/Main/Split/SplitDraft.swift SettlrTests/GuidedSplitFlowStateTests.swift Settlr.xcodeproj/project.pbxproj
git commit -m "Add guided split flow policy"
```

---

### Task 2: Extract endpoint-free editor sheets

**Files:**

- Create: `Settlr/Views/Main/Split/SplitEditorSheets.swift`
- Create: `SettlrTests/GuidedSplitPresentationTests.swift`
- Modify: `Settlr.xcodeproj/project.pbxproj`

**Interfaces:**

- Consumes: `SplitDraft.Item`, `SplitDraft.Participant`, `TipPreset`, and callbacks owned by `SplitCreateSheet`.
- Produces: `SplitReceiptDetailsSheet`, `SplitPeopleEditorSheet`, `SplitItemEditorSheet`, `SplitMoneyEditorSheet`, and `SplitMoneyField`.

- [ ] **Step 1: Add presentation tests for commit-on-Done behavior**

Create `GuidedSplitPresentationTests.swift`. Keep mutation rules in pure helper values so XCTest can cover them without rendering SwiftUI:

```swift
func testItemEditorPreservesIdentityAndNormalizesQuantity() {
    let source = SplitDraft.Item(serverID: "item-1", name: "Soup", quantity: 2, unitPriceCents: 900, allocationMode: "units")
    let result = SplitItemEditDraft(item: source).committed(name: "Soup", quantity: 0, unitPriceCents: 950, allocationMode: "shared")
    XCTAssertEqual(result.serverID, "item-1")
    XCTAssertEqual(result.quantity, 1)
    XCTAssertEqual(result.unitPriceCents, 950)
    XCTAssertEqual(result.allocationMode, "shared")
}

func testGuestEditorKeepsBlankNamesForRequestNormalization() {
    var draft = SplitPeopleEditDraft(participants: SplitDraft().participants)
    draft.setHeadcount(2)
    draft.participants[1].name = "   "
    XCTAssertEqual(draft.participants[1].name, "   ")
}
```

- [ ] **Step 2: Add pure sheet-local edit values**

Define:

```swift
enum SplitMoneyField: Hashable { case total, tax, tip, fee }

struct SplitItemEditDraft {
    private let original: SplitDraft.Item
    init(item: SplitDraft.Item) { original = item }
    func committed(name: String, quantity: Int, unitPriceCents: Int, allocationMode: String) -> SplitDraft.Item
}

struct SplitPeopleEditDraft {
    var participants: [SplitDraft.Participant]
    mutating func setHeadcount(_ count: Int)
}
```

`committed` must preserve `localID`, `serverID`, `verification`, and `clearClaims`. `setHeadcount` must keep the organizer and use the existing `Person N` ordering semantics without normalizing blank display names early.

- [ ] **Step 3: Implement the four sheets**

Use these endpoint-free initializers:

```swift
SplitReceiptDetailsSheet(merchant:occurredAt:onCommit:)
SplitPeopleEditorSheet(participants:onCommit:)
SplitItemEditorSheet(item:onCommit:onRemove:)
SplitMoneyEditorSheet(kind:cents:tipBaseCents:onCommit:)
```

Each sheet owns a local copy, uses a native navigation title, Cancel, and Done, and calls its commit callback only from Done. `SplitItemEditorSheet` exposes removal only when `onRemove` is non-nil. The money sheet uses decimal input, tabular digits, keyboard Done, and the existing tip presets for `.tip`.

- [ ] **Step 4: Register files and verify**

Add the new production and test files to `project.pbxproj`, then run the generic build and `git diff --check` command from Task 1. Expected: exit 0.

- [ ] **Step 5: Commit**

```bash
git add Settlr/Views/Main/Split/SplitEditorSheets.swift SettlrTests/GuidedSplitPresentationTests.swift Settlr.xcodeproj/project.pbxproj
git commit -m "Add focused split editor sheets"
```

---

### Task 3: Build the shared guided components and Setup screen

**Files:**

- Create: `Settlr/Views/Main/Split/SplitGuidedComponents.swift`
- Create: `Settlr/Views/Main/Split/SplitSetupStepView.swift`
- Modify: `SettlrTests/GuidedSplitPresentationTests.swift`
- Modify: `Settlr.xcodeproj/project.pbxproj`

**Interfaces:**

- Consumes: bindings and actions from `SplitCreateSheet`; no endpoint clients.
- Produces: `SplitProgressRail`, `SplitReceiptHeader`, `SplitStickyAction`, `SplitReceiptHeaderPresentation`, and `SplitSetupStepView`.

- [ ] **Step 1: Add failing presentation tests**

Add:

```swift
func testReceiptHeaderUsesDraftValuesAndCountsWarnings() {
    var draft = SplitDraft()
    draft.merchant = "DEICO RAMEN CONDESA"
    draft.paymentChannel = "cash"
    draft.items = [.init(name: "Soda", quantity: 1, unitPriceCents: 8_300, verification: .unverified)]
    draft.scanWarnings = ["Check total"]
    let value = SplitReceiptHeaderPresentation(draft: draft, totalCents: 8_300)
    XCTAssertEqual(value.merchant, "DEICO RAMEN CONDESA")
    XCTAssertEqual(value.paymentLabel, "Cash / debit")
    XCTAssertEqual(value.warningCount, 2)
}

func testSetupActionCopyFollowsDivisionMode() {
    XCTAssertEqual(GuidedSplitFlowPolicy.setupActionTitle(splitMode: "by_item", itemCount: 7), "Review 7 items")
    XCTAssertEqual(GuidedSplitFlowPolicy.setupActionTitle(splitMode: "even", itemCount: 0), "Check total")
}
```

- [ ] **Step 2: Implement the shared components**

`SplitReceiptHeader` shows the current merchant, draft date, payment label, total, and warning count. Its menu exposes exactly `Edit receipt details`, `Scan again`, and `Receipt parsing settings`. `SplitProgressRail` has Setup, Items, Confirm and announces `Step N of 3`. `SplitStickyAction` clears the home indicator, uses one 52-point lime action, and swaps its label for an inline progress indicator only while submitting.

- [ ] **Step 3: Implement Setup**

Use this interface:

```swift
struct SplitSetupStepView: View {
    @Binding var draft: SplitDraft
    let totalCents: Int
    let cards: [CreditCard]
    let cardLoadState: SplitCardLoadState
    let validationIssue: GuidedSplitValidationIssue?
    let onEditReceipt: () -> Void
    let onEditPeople: () -> Void
    let onScanAgain: () -> Void
    let onOpenParserSettings: () -> Void
    let onRetryCards: () -> Void
    let onContinue: () -> Void
}
```

Render the two payer rows, a two-option segmented control, People, and Paid with. Use `appState.currentUser?.has(.creditCards)` only in the parent to decide which options and cards are passed in. A `.failed(message)` card state keeps cached cards and adds a Retry row. Continue stays tappable and calls the parent validator.

- [ ] **Step 4: Register files and verify**

Add file references and Sources entries. Run `git diff --check`, both source-check scripts, and the generic build. Expected: exit 0.

- [ ] **Step 5: Commit**

```bash
git add Settlr/Views/Main/Split/SplitGuidedComponents.swift Settlr/Views/Main/Split/SplitSetupStepView.swift SettlrTests/GuidedSplitPresentationTests.swift Settlr.xcodeproj/project.pbxproj
git commit -m "Build guided split setup"
```

---

### Task 4: Build the dense Items screen

**Files:**

- Create: `Settlr/Views/Main/Split/SplitItemsStepView.swift`
- Modify: `SettlrTests/GuidedSplitPresentationTests.swift`
- Modify: `Settlr.xcodeproj/project.pbxproj`

**Interfaces:**

- Consumes: the shared draft, selected filter, editor callbacks, validation issue, and sticky action.
- Produces: `SplitItemFilter`, `SplitItemsPresentation`, and `SplitItemsStepView`.

- [ ] **Step 1: Add failing item-list tests**

```swift
func testItemsPresentationSeparatesReviewLinesWithoutInventingClaims() {
    var draft = SplitDraft()
    draft.participants.append(.init(id: nil, name: "Ana", isOrganizer: false))
    draft.items = [
        .init(name: "Soda", quantity: 1, unitPriceCents: 8_300, verification: .unverified),
        .init(name: "Soup", quantity: 2, unitPriceCents: 10_000, allocationMode: "units")
    ]
    let value = SplitItemsPresentation(draft: draft)
    XCTAssertEqual(value.itemCount, 2)
    XCTAssertEqual(value.participantCount, 2)
    XCTAssertEqual(value.reviewCount, 1)
    XCTAssertEqual(value.subtotalCents, 28_300)
    XCTAssertEqual(SplitItemFilter.allCases, [.needsReview, .all])
}
```

- [ ] **Step 2: Implement the presentation and filters**

Define `SplitItemFilter: CaseIterable` with only `.needsReview` and `.all`. `SplitItemsPresentation` derives counts and subtotal from `draft.filledItems`. The selected filter returns unverified items for Needs review and all filled items for All. When no unverified item exists, hide Needs review and select All.

- [ ] **Step 3: Implement the Items screen**

Use:

```swift
SplitItemsStepView(
    draft: $draft,
    filter: $itemFilter,
    validationIssue: validationIssue,
    onEditItem: presentItemEditor,
    onAddItem: presentNewItemEditor,
    onContinue: validateItemsAndContinue
)
```

Resting rows show name, line amount, quantity when greater than one, allocation mode, and the compact unverified warning. Do not show inline price fields, remove icons, or a creation-time Unassigned filter. Row taps open `SplitItemEditorSheet`. `Add item` opens the same sheet with a new stable item.

- [ ] **Step 4: Register and verify**

Update `project.pbxproj`. Run the generic build, source checks, and `git diff --check`. Expected: exit 0.

- [ ] **Step 5: Commit**

```bash
git add Settlr/Views/Main/Split/SplitItemsStepView.swift SettlrTests/GuidedSplitPresentationTests.swift Settlr.xcodeproj/project.pbxproj
git commit -m "Build guided split item review"
```

---

### Task 5: Build Confirm and preserve reconciliation

**Files:**

- Create: `Settlr/Views/Main/Split/SplitConfirmStepView.swift`
- Modify: `SettlrTests/GuidedSplitPresentationTests.swift`
- Modify: `SettlrTests/TipPresetTests.swift`
- Modify: `Settlr.xcodeproj/project.pbxproj`

**Interfaces:**

- Consumes: draft and total bindings, cards, network/edit state, reconciliation actions, and the final submit callback.
- Produces: `SplitConfirmPresentation`, `GuidedSplitPrimaryAction`, and `SplitConfirmStepView`.

- [ ] **Step 1: Add failing Confirm tests**

```swift
func testConfirmPresentationIncludesEvenShareAndMaterialDifference() {
    var draft = SplitDraft()
    draft.merchant = "Cafe"
    draft.splitMode = "even"
    draft.participants.append(.init(id: nil, name: "Ana", isOrganizer: false))
    draft.items = [.init(name: "Bill", quantity: 1, unitPriceCents: 8_000)]
    draft.selectedTotalCents = 10_000
    let value = SplitConfirmPresentation(draft: draft, totalEdited: true)
    XCTAssertEqual(value.effectiveTotalCents, 10_000)
    XCTAssertEqual(value.evenShareCents, 5_000)
    XCTAssertEqual(value.differenceCents, 2_000)
}

func testPrimaryActionCopyMatchesOutcome() {
    XCTAssertEqual(GuidedSplitPrimaryAction.create.title, "Create split")
    XCTAssertEqual(GuidedSplitPrimaryAction.saveChanges.title, "Save changes")
    XCTAssertEqual(GuidedSplitPrimaryAction.saveOnPhone.title, "Save on this phone")
}
```

- [ ] **Step 2: Implement the Confirm presentation**

`SplitConfirmPresentation` exposes item subtotal, tax, tip, fee, calculated total, effective receipt total, optional difference, payer label, division summary, payment label, and even share. It must read `SplitDraft.reconciliation` instead of reproducing tolerance math.

- [ ] **Step 3: Implement Confirm**

Use:

```swift
struct SplitConfirmStepView: View {
    @Binding var draft: SplitDraft
    @Binding var totalEdited: Bool
    let presentation: SplitConfirmPresentation
    let primaryAction: GuidedSplitPrimaryAction
    let validationIssue: GuidedSplitValidationIssue?
    let isSubmitting: Bool
    let onEditSetupValue: (GuidedSplitField) -> Void
    let onEditMoney: (SplitMoneyField) -> Void
    let onKeepReceiptTotal: () -> Void
    let onUseCalculatedTotal: () -> Void
    let onSubmit: () -> Void
}
```

Use the approved hero amount, compact math rows, material mismatch decision block, and tappable summary rows. Keep `confirmKeepReceiptTotal`, `useCalculatedTotal`, `TipPreset`, and `TipPreset.retotal` as the only money decision logic. The sticky action stays tappable for validation guidance but is disabled during submission.

- [ ] **Step 4: Register and verify**

Update `project.pbxproj`. Run the generic build, source checks, and `git diff --check`. Expected: exit 0.

- [ ] **Step 5: Commit**

```bash
git add Settlr/Views/Main/Split/SplitConfirmStepView.swift SettlrTests/GuidedSplitPresentationTests.swift SettlrTests/TipPresetTests.swift Settlr.xcodeproj/project.pbxproj
git commit -m "Build guided split confirmation"
```

---

### Task 6: Convert the editor into the guided coordinator

**Files:**

- Modify: `Settlr/Views/Main/Split/SplitCreateSheet.swift`
- Modify: `Settlr/Views/Main/Split/SplitScanFlow.swift`
- Modify: `SettlrTests/GuidedSplitFlowStateTests.swift`
- Modify: `scripts/check-signal-redesign.sh`

**Interfaces:**

- Consumes: every type and view from Tasks 1 through 5.
- Produces: a working scanner, manual, and edit flow using the existing `SplitCreateSheet` initializer and save callback.

- [ ] **Step 1: Add navigation and source regression tests**

Extend `GuidedSplitFlowStateTests` with draft-preserving mode switches and correct back targets. Add source checks that require the three step views and forbid the old navigation-bar save button:

```sh
split_editor=Settlr/Views/Main/Split/SplitCreateSheet.swift
grep -Fq 'SplitSetupStepView' "$split_editor"
grep -Fq 'SplitItemsStepView' "$split_editor"
grep -Fq 'SplitConfirmStepView' "$split_editor"
if rg -q 'ToolbarItem\(placement: \.confirmationAction\)' "$split_editor"; then
    echo "Guided split must keep Create in the sticky Confirm action." >&2
    exit 1
fi
```

Redirect every earlier split-form assertion in `check-signal-redesign.sh` to the file that now owns the behavior. In particular, `HeroAmountField`, payer labels, division labels, item allocation, receipt warnings, `SignalNativeFormRow`, and DatePicker must be checked in the new Setup, Items, Confirm, or sheet files. Remove the old checks for the deleted Review table and permanent scan banner. Keep the submit-time `normalizeCardPaymentState()` assertion on `SplitCreateSheet`.

- [ ] **Step 2: Replace the monolithic scroll with typed navigation**

Keep all existing initializer arguments. Add:

```swift
@State private var path: [GuidedSplitStep] = []
@State private var validationIssue: GuidedSplitValidationIssue?
@State private var itemFilter: SplitItemFilter = .all
@State private var presentedEditor: SplitPresentedEditor?
@State private var cardLoadState: SplitCardLoadState = .idle
@State private var initialSnapshot: GuidedSplitSubmissionSnapshot?
@State private var showDiscardConfirmation = false
```

The root renders Setup. Setup appends either `.items` or `.confirm`. Items appends `.confirm`. Confirm summary rows pop to Setup. Native back mutates the path and leaves the parent-owned draft untouched.

- [ ] **Step 3: Move existing behavior into coordinator actions**

Retain and call the existing logic for:

- `applyInitialDraftOnce`
- scan/photo recovery and `applyScan`
- cache-first card loading and feature normalization
- tip retotaling and total bindings
- mismatch alerts
- claim-impact confirmation
- `save`, queued creation, `submitEdit`, and stale response copy

Change card loading to set `.refreshing`, then `.idle` on success or `.failed(error.localizedDescription)` on failure while preserving cached cards. Map local validation issues to the owning step. Keep generic server errors at the top of Confirm.

- [ ] **Step 4: Implement cancellation and scanner handoff**

Capture `GuidedSplitSubmissionSnapshot` only after initial draft application and card-state normalization. Scanner mode also treats imported receipt state as dirty. `onBackToReview` passes the same draft and `totalEdited`. Cancel asks only when the snapshot reports unsaved work. `.interactiveDismissDisabled` blocks only while scanning or submitting.

Successful creation continues to set `SplitScanStage.result`. A queued outcome keeps the existing `Waiting to upload` Result and cannot be mistaken for completed creation.

- [ ] **Step 5: Remove obsolete form sections**

Delete the old permanent `scanBanner`, duplicated `receiptReviewSection`, repeated merchant/date block, inline item editor, inline extras form, and navigation-bar Create. Keep reusable pure helpers only when the new views call them.

- [ ] **Step 6: Verify and commit**

Run both source-check scripts, `git diff --check`, and the generic build. Expected: exit 0.

```bash
git add Settlr/Views/Main/Split/SplitCreateSheet.swift Settlr/Views/Main/Split/SplitScanFlow.swift SettlrTests/GuidedSplitFlowStateTests.swift scripts/check-signal-redesign.sh
git commit -m "Wire the guided bill split flow"
```

---

### Task 7: Keep the Dashboard signal alive

**Files:**

- Create: `Settlr/Models/DashboardFallbackSignal.swift`
- Modify: `Settlr/Views/Main/Dashboard/SpendingInsightsStrip.swift`
- Modify: `SettlrTests/DashboardSummaryTests.swift`
- Modify: `Settlr.xcodeproj/project.pbxproj`
- Modify: `scripts/check-signal-redesign.sh`

**Interfaces:**

- Consumes: `SummaryResponse` and existing `SpendingInsights.build` output.
- Produces: `DashboardFallbackSignal`, `DashboardFallbackSignalSet`, `DashboardFallbackSignals.build(summary:)`, and `DashboardSignalSectionMode`.

- [ ] **Step 1: Add fallback-signal tests**

Add tests covering the real low-data states:

```swift
func testIncomeOnlyMonthBuildsAnimatedFactualSignals() throws {
    let data = Data(#"{"incomeCents":100000,"expenseCents":0,"netCents":100000,"savingsNetCents":0,"incomeCount":1,"expenseCount":0,"transactionCount":1}"#.utf8)
    let summary = try JSONDecoder().decode(SummaryResponse.self, from: data)
    let result = DashboardFallbackSignals.build(summary: summary)
    XCTAssertFalse(result.isQuiet)
    XCTAssertEqual(result.signals.map(\.kind), [.income, .available, .noSpending, .movementCount])
}

func testAllZeroMonthBuildsOneQuietSignal() throws {
    let summary = try JSONDecoder().decode(SummaryResponse.self, from: Data(#"{}"#.utf8))
    let result = DashboardFallbackSignals.build(summary: summary)
    XCTAssertTrue(result.isQuiet)
    XCTAssertEqual(result.signals.map(\.kind), [.noMovement])
}

func testSavingsUsesMoneyFlowSign() throws {
    let data = Data(#"{"savingsNetCents":75000}"#.utf8)
    let summary = try JSONDecoder().decode(SummaryResponse.self, from: data)
    XCTAssertEqual(DashboardFallbackSignals.build(summary: summary).signals.first(where: { $0.kind == .savings })?.signedCents, -75_000)
}
```

Also test negative Available, positive spending with empty categories, the five-item cap, one real insight without a duplicate rail, and five real insights with four ticker entries.

- [ ] **Step 2: Implement factual fallback data**

Create:

```swift
struct DashboardFallbackSignal: Identifiable, Equatable {
    enum Kind: Equatable { case income, spending, available, savings, noSpending, movementCount, noMovement }
    let id: String
    let kind: Kind
    let signedCents: Int?
    let count: Int?
}

struct DashboardFallbackSignalSet: Equatable {
    let signals: [DashboardFallbackSignal]
    let isQuiet: Bool
    var shouldAnimate: Bool { !isQuiet && signals.count > 1 }
}

enum DashboardSignalSectionMode: Equatable {
    case spending(primaryIndex: Int, tickerIndices: [Int])
    case fallback(animated: Bool)
}
```

`DashboardFallbackSignals.build` uses income, expense, `availableCents`, `-savingsNetCents`, and transaction count. It returns at most five facts. It never creates category names, percentages, comparisons, or trends.

Add `DashboardFallbackSignal.tickerInsight` in `SpendingInsightsStrip.swift` to map each factual kind to the existing `SpendingInsight` rendering model. Use the existing dashboard money formatter for `signedCents`, preserve the sign, set `swatch` to nil, and choose semantic tone from the kind and sign. This mapping is presentation-only; the pure fallback model remains free of `Color`.

- [ ] **Step 3: Remove the disappearing and duplicate branches**

In `SpendingInsightsTicker`, remove the zero-expense `EmptyView`. Prefer real spending insights. With one real insight, render its hero and no ticker rail. With two to five, render the first as hero and the remainder in the existing ticker. When real insights are empty, render fallback signals in the same section position.

Change `InsightTicker` to accept `var onTap: (() -> Void)?`. A nil action keeps drag and pause for a multi-item fallback but does not fire tap, add `.isButton`, or add a default accessibility action. Reduce Motion uses the static row. A quiet all-zero signal never creates a `TimelineView`.

- [ ] **Step 4: Extend source gates**

Require `DashboardFallbackSignals.build`, the optional ticker action, and the absence of the old duplicate expression:

```sh
grep -Fq 'DashboardFallbackSignals.build' Settlr/Views/Main/Dashboard/SpendingInsightsStrip.swift
grep -Fq 'var onTap: (() -> Void)?' Settlr/Views/Main/Dashboard/SpendingInsightsStrip.swift
if grep -Fq 'secondary.isEmpty ? insights : secondary' Settlr/Views/Main/Dashboard/SpendingInsightsStrip.swift; then
    echo "Dashboard must not duplicate its only real insight in the ticker." >&2
    exit 1
fi
```

- [ ] **Step 5: Verify and commit**

Run both source-check scripts, `git diff --check`, and the generic build. Expected: exit 0.

```bash
git add Settlr/Models/DashboardFallbackSignal.swift Settlr/Views/Main/Dashboard/SpendingInsightsStrip.swift SettlrTests/DashboardSummaryTests.swift Settlr.xcodeproj/project.pbxproj scripts/check-signal-redesign.sh
git commit -m "Keep the Dashboard signal alive"
```

---

### Task 8: Update the design system and complete verification

**Files:**

- Modify: `docs/design-system/SETTLR_SIGNAL.md`
- Modify: `docs/design-system/settlr-signal-components.html`
- Modify: `scripts/check-signal-redesign.sh`

**Interfaces:**

- Consumes: the final production component names and behavior from Tasks 1 through 7.
- Produces: the final documented design system and a preview matching the shipping SwiftUI structure.

- [ ] **Step 1: Update the Markdown design system**

Document Setup, Items, Confirm, progress behavior, compact receipt header, dense item row, editor sheets, sticky action labels, mismatch decision, and the live, fallback, and quiet Dashboard signal states. State that unverified items warn but do not block, while material reconciliation blocks submission.

- [ ] **Step 2: Update the HTML preview**

Replace the bloated bill editor example with the approved three-screen guided flow. Add the Dashboard carousel fallback shown in the companion. Keep the existing Signal Black tokens and component navigation. Do not add a fourth design language or new accent.

- [ ] **Step 3: Lock the new artifacts in the source check**

Add exact checks for:

```sh
grep -Fq 'Setup → Items → Confirm' docs/design-system/SETTLR_SIGNAL.md
grep -Fq 'guided-split-flow' docs/design-system/settlr-signal-components.html
grep -Fq 'dashboard-signal-fallback' docs/design-system/settlr-signal-components.html
grep -Fq 'SplitSetupStepView' Settlr/Views/Main/Split/SplitCreateSheet.swift
grep -Fq 'SplitItemsStepView' Settlr/Views/Main/Split/SplitCreateSheet.swift
grep -Fq 'SplitConfirmStepView' Settlr/Views/Main/Split/SplitCreateSheet.swift
```

- [ ] **Step 4: Run the final agent-side verification**

```bash
./scripts/check-signal-redesign.sh
./scripts/check-app-source-regressions.sh
git diff --check
xcodebuild -quiet -project Settlr.xcodeproj -scheme Settlr -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath /tmp/settlr-codex-derived CODE_SIGNING_ALLOWED=NO build
git status --short
```

Expected: source checks, whitespace check, and generic iOS build exit 0. `git status --short` shows only `.superpowers/brainstorm/` plus any intentionally uncommitted App Store image work that belongs to a later task.

- [ ] **Step 5: Record the user's runtime pass**

Hand the user this exact simulator checklist:

- Capture, Review, Setup, Items, Confirm, Result.
- Even split skipping Items.
- Both payer modes.
- Item add, edit, remove, quantity, and allocation.
- Material mismatch decisions and tip presets.
- Cash and credit-card payment.
- Offline queued creation and online-only editing.
- Back, edge swipe, dirty Cancel, keyboard dismissal, and home-indicator clearance.
- Zero-spend moving signal, all-zero quiet signal, one real insight, and five real insights.
- VoiceOver, Reduce Motion, Dynamic Type XL, and both appearances.

- [ ] **Step 6: Commit**

```bash
git add docs/design-system/SETTLR_SIGNAL.md docs/design-system/settlr-signal-components.html scripts/check-signal-redesign.sh
git commit -m "Document the guided split flow"
```

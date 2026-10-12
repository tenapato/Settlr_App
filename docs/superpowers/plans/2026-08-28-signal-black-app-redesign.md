# Settlr Signal Black App Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild Settlr's signed-in iOS experience around the approved Signal Black design while preserving existing endpoints, feature gates, accounting rules, offline behavior, and the dashboard insight ticker.

**Architecture:** Add semantic appearance and component primitives first, then replace the root navigation and migrate each product area in ordered commits on one feature branch. Keep financial state in existing models and view models or in small pure presentation models. Server responses remain authoritative. Each phase ends in a runnable, reviewable App commit and does not modify the Server repository.

**Tech Stack:** SwiftUI, Observation, XCTest, SF Symbols, existing `APIClient`, existing Swift models and view models, shell source-regression checks.

**Spec:** `docs/superpowers/specs/2026-08-28-signal-black-app-redesign-design.md`

## Global Constraints

- Keep all App redesign work on the existing `feat/signal-black-redesign-spec` branch. Do not create another App branch or worktree.
- Do not merge, push, deploy, or run a remote migration.
- Do not run `xcodebuild`; the user will build and manually test at the final stage.
- Run `bash scripts/check-app-source-regressions.sh`, `bash scripts/check-signal-redesign.sh`, `ruby scripts/test-testflight-workflow.rb`, and `git diff --check` after every task.
- Dark is the default appearance. Light and System are user-selectable.
- Minimum interactive target is 44 by 44 pt.
- Use SwiftUI system fonts and SF Symbols. Keep the existing Settlr logo asset.
- Use one brand accent: `#CAFF3A` in dark appearance, with the approved olive mapping for readable light-mode text.
- Preserve `SpendingInsights.build`, its five-item limit, 30 pt/s loop, touch pause, drag, 2.5 second resume, tap behavior, and Reduce Motion static row.
- Preserve bill-split payer modes, settlement rules, version conflicts, pending queue, public join, pass-the-phone, receipt parsing, and payment-method behavior.
- Savings goal UI consumes the existing savings account routes and the approved Server fields. Do not add a separate goal endpoint.
- Hide unavailable tabs, actions, filters, and requests before calling a feature-gated route.
- A production QR must be generated with the current share URL and scan-tested on device. The HTML gallery QR is not an implementation asset.

## File structure and phase boundaries

| Phase commit | Responsibility | Main files |
| --- | --- | --- |
| `feat: add Signal Black design foundation` | Adaptive tokens, appearance, loading primitives, component checks | `DesignSystem.swift`, new `AppearancePreference.swift`, new `SignalLoadingViews.swift` |
| `feat: add Signal navigation and quick actions` | Four-tab shell, feature availability, C6 launcher | `FloatingTabBar.swift`, `FeatureAccess.swift`, `MainTabView.swift`, new `QuickActionLauncher.swift` |
| `feat: add Signal amount forms` | Hero amount preservation and Signal rows | `FormControls.swift` and existing form sheets |
| `feat: redesign Signal home` | Home hierarchy and available balance | `DashboardSummary.swift`, `DashboardView.swift`, `DashboardVM.swift` |
| `feat: add unified Signal activity` | Unified Signal timeline and filters | new `ActivityEvent.swift`, new `ActivityVM.swift`, `ActivityView.swift` |
| `feat: add Signal savings goals` | Savings root, account details, server-backed goals | `Savings.swift`, `SavingsVM.swift`, `SavingsView.swift`, account sheets |
| `feat: redesign Signal cards and payments` | Cards root and quiet fortnight navigator | `CardPaymentFortnight.swift`, `CardsView.swift`, `CardPaymentsView.swift`, new `CardsRootView.swift` |
| `feat: redesign Signature Scanner creation` | Capture, review, payer choice, assignment | existing files under `Views/Main/Split/` |
| `feat: redesign split settlement and QR handoff` | Payer-correct results, settlement, QR | existing files under `Views/Main/Split/` |
| `feat: finish Signal Black app redesign` | Auth, workspaces, settings, empty/error states, final checks | Auth views, workspace views, settings, `ContentView.swift` |

Do not start a later phase until the previous phase's commit is reviewed. Keep the working tree clean between phases.

---

### Task 1: Adaptive tokens, appearance preference, and loading primitives

**Files:**

- Create: `Settlr/Models/AppearancePreference.swift`
- Create: `Settlr/Views/Components/SignalLoadingViews.swift`
- Create: `SettlrTests/AppearancePreferenceTests.swift`
- Create: `scripts/check-signal-redesign.sh`
- Modify: `Settlr/Views/Components/DesignSystem.swift`
- Modify: `Settlr/SettlrApp.swift`
- Modify: `Settlr/Views/Main/Settings/SettingsView.swift`
- Modify: `Settlr.xcodeproj/project.pbxproj`

**Interfaces:**

- Produces: `SettlrAppearance: String, CaseIterable, Identifiable` with `.dark`, `.light`, `.system`, and `colorScheme: ColorScheme?`.
- Produces: adaptive `Theme.bg`, `surface`, `surface2`, `line`, `ink`, `muted`, `faint`, `accent`, `accentText`, `income`, `expense`, and `warning`.
- Produces: `SignalTraceLoadingView(lastUpdated: Date?)`, `SettlrPulseLoadingView(message: String)`, and `ActivityShapeLoadingView()`.
- Later tasks consume all three interfaces and must not introduce duplicate color hex values.

- [ ] **Step 1: Add failing source checks and appearance tests**

Create `scripts/check-signal-redesign.sh` with executable source assertions:

```sh
#!/bin/sh
set -eu

grep -Fq 'enum SettlrAppearance' Settlr/Models/AppearancePreference.swift
grep -Fq 'static let accentText' Settlr/Views/Components/DesignSystem.swift
grep -Fq 'struct SignalTraceLoadingView' Settlr/Views/Components/SignalLoadingViews.swift
grep -Fq 'struct SettlrPulseLoadingView' Settlr/Views/Components/SignalLoadingViews.swift
grep -Fq 'struct ActivityShapeLoadingView' Settlr/Views/Components/SignalLoadingViews.swift
grep -Fq '@AppStorage("settlr.appearance")' Settlr/SettlrApp.swift
```

Create `AppearancePreferenceTests.swift`:

```swift
import SwiftUI
import XCTest
@testable import Settlr

final class AppearancePreferenceTests: XCTestCase {
    func testColorSchemeMapping() {
        XCTAssertEqual(SettlrAppearance.dark.colorScheme, .dark)
        XCTAssertEqual(SettlrAppearance.light.colorScheme, .light)
        XCTAssertNil(SettlrAppearance.system.colorScheme)
    }

    func testDefaultRawValueIsDark() {
        XCTAssertEqual(SettlrAppearance(rawValue: "unknown") ?? .dark, .dark)
    }
}
```

- [ ] **Step 2: Run the new source check to verify it fails**

Run: `bash scripts/check-signal-redesign.sh`

Expected: FAIL because `AppearancePreference.swift` and the loading primitives do not exist.

- [ ] **Step 3: Add the appearance model and apply it at the app root**

Implement:

```swift
import SwiftUI

enum SettlrAppearance: String, CaseIterable, Identifiable {
    case dark, light, system
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var colorScheme: ColorScheme? {
        switch self {
        case .dark: .dark
        case .light: .light
        case .system: nil
        }
    }
}
```

In `SettlrApp`, store the raw value with `@AppStorage("settlr.appearance")`, fall back to `.dark`, and apply `.preferredColorScheme(appearance.colorScheme)` once above `ContentView`. Remove leaf-level `.preferredColorScheme(.dark)` as each later task touches those screens.

- [ ] **Step 4: Replace the palette with adaptive semantic colors**

Add a private dynamic-color helper:

```swift
private extension Color {
    static func settlr(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}
```

If `UIColor(hex:)` does not exist, implement it in the same file from the three RGB bytes. Map the exact spec values and keep `categoryPalette` semantic rather than appearance-hard-coded.

- [ ] **Step 5: Add the three loading primitives**

Implement these rules:

```swift
struct SignalTraceLoadingView: View {
    let lastUpdated: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // Keep content outside this view visible. Animate one 34% lime trace only
    // when reduceMotion is false; otherwise pin a 42% static trace to leading.
}

struct SettlrPulseLoadingView: View {
    let message: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // Render Image("SettlrLogo") or the existing three-bar mark treatment.
    // Sequence three bar opacities only when motion is allowed.
}

struct ActivityShapeLoadingView: View {
    // Four neutral timeline nodes and two text bars per row.
    // No generic full-screen shimmer.
}
```

Add a Dark, Light, and System control in Settings using `SettlrAppearance.allCases` and the same `@AppStorage` key.

- [ ] **Step 6: Register files and run checks**

Add both Swift files and the test file to the existing App and test targets in `project.pbxproj`.

Run:

```bash
bash scripts/check-signal-redesign.sh
bash scripts/check-app-source-regressions.sh
ruby scripts/test-testflight-workflow.rb
git diff --check
```

Expected: all commands exit 0. Do not run XCTest yet.

- [ ] **Step 7: Commit the phase**

```bash
git add Settlr SettlrTests scripts Settlr.xcodeproj/project.pbxproj
git commit -m "feat: add Signal Black design foundation"
```

---

### Task 2: Four-tab navigation and C6 launcher

**Files:**

- Create: `Settlr/Views/Components/QuickActionLauncher.swift`
- Create: `SettlrTests/FeatureAccessTests.swift`
- Modify: `Settlr/Views/Components/FloatingTabBar.swift`
- Modify: `Settlr/Models/FeatureAccess.swift`
- Modify: `Settlr/Views/Main/MainTabView.swift`
- Modify: `Settlr.xcodeproj/project.pbxproj`
- Modify: `scripts/check-signal-redesign.sh`

**Interfaces:**

- Produces: `Tab.home`, `.activity`, `.savings`, `.cards` in that order.
- Produces: `QuickActionItem` and `QuickActionLauncher(items:isOpen:onSetOpen:)`.
- Consumes: adaptive `Theme` and `SettlrPulseLoadingView` from Task 1.

- [ ] **Step 1: Write failing availability tests**

Create `FeatureAccessTests.swift` with a fixture helper for `MeUser`, then assert:

```swift
private func user(disabled: [String]) -> MeUser {
    MeUser(
        id: "user",
        name: "User",
        email: "user@example.com",
        emailVerified: true,
        role: "user",
        disabledFeatures: disabled
    )
}

func testSignalTabsRespectFeatures() {
    XCTAssertEqual(Tab.available(for: user(disabled: [])), [.home, .activity, .savings, .cards])
    XCTAssertEqual(
        Tab.available(for: user(disabled: ["expenses", "income", "bill_splits", "savings", "credit_cards"])),
        [.home]
    )
    XCTAssertFalse(Tab.activity.isAvailable(for: user(disabled: ["expenses", "income", "bill_splits"])))
    XCTAssertFalse(Tab.cards.isAvailable(for: user(disabled: ["credit_cards"])))
}
```

Append source checks for `case home, activity, savings, cards`, `struct QuickActionLauncher`, and the `Scan and split` label.

- [ ] **Step 2: Run the source check and confirm failure**

Run: `bash scripts/check-signal-redesign.sh`

Expected: FAIL because the tab enum still includes Payments and the launcher file is absent.

- [ ] **Step 3: Replace the tab model and availability rules**

Implement:

```swift
enum Tab: CaseIterable {
    case home, activity, savings, cards
}
```

Map labels and SF Symbols to Home, Activity, Savings, and Cards. `Tab.activity` is available when any of expenses, income, or bill splits is enabled. `Tab.savings` requires savings. `Tab.cards` requires credit cards. Card payment content remains additionally gated by both credit-card features.

- [ ] **Step 4: Extract the C6 launcher**

Define:

```swift
struct QuickActionItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let systemImage: String
    let role: QuickActionRole
    let action: () -> Void
}

enum QuickActionRole { case signature, standard }
```

`QuickActionLauncher` renders the 52 pt lime circle in a 58 pt hit target, transforms to a charcoal close control, dims the app, and opens a bottom-right satellite menu. The signature item is `Scan and split`; standard items are Expense, Income, and Savings. Use `accessibilityHidden`, focus order, Escape dismissal, selection haptic, and Reduce Motion fade.

- [ ] **Step 5: Rebuild `MainTabView` around feature-aware tab stacks**

Keep form and scanner presentation state in `MainTabView`, but remove forced tab switches from `openLedgerForm`. Saving or cancelling dismisses back to the originating tab. Route:

```swift
switch selectedTab {
case .home: DashboardView(...)
case .activity: ActivityView(...)
case .savings: SavingsView(...)
case .cards: CardsRootView(...)
}
```

Until `CardsRootView` arrives in Task 7, add a private adapter that hosts `CardsView` and conditionally exposes `CardPaymentsView`. Do not call payment endpoints unless both features are enabled.

- [ ] **Step 6: Register, check, and commit**

Run the four global check commands. Expected: exit 0.

```bash
git add Settlr SettlrTests scripts Settlr.xcodeproj/project.pbxproj
git commit -m "feat: add Signal navigation and quick actions"
```

---

### Task 3: Hero amount fields and Signal rows

**Files:**

- Modify: `Settlr/Views/Components/FormControls.swift`
- Modify: `Settlr/Views/Main/Expenses/ExpenseFormSheet.swift`
- Modify: `Settlr/Views/Main/Income/IncomeFormSheet.swift`
- Modify: `Settlr/Views/Main/Savings/SavingsEntryFormSheet.swift`
- Modify: `Settlr/Views/Main/Income/IncomeRecurringSheet.swift`
- Modify: `Settlr/Views/Main/Savings/SavingsRecurringSheet.swift`
- Modify: `Settlr/Views/Main/CardPaymentsView.swift`
- Modify: `Settlr/Views/Main/Split/SplitCreateSheet.swift`
- Modify: `scripts/check-signal-redesign.sh`

**Interfaces:**

- Produces: enhanced `HeroAmountField` and reusable `SignalFormRow`.
- Consumes: Task 1 tokens and Task 2 dismissal behavior.

- [ ] **Step 1: Add failing form source checks**

Append checks that require `struct SignalFormRow`, `.monospacedDigit()`, `accessibilityLabel("Amount in Mexican pesos")`, and use of `SignalFormRow` in the expense, income, and savings entry sheets.

- [ ] **Step 2: Verify the checks fail**

Run: `bash scripts/check-signal-redesign.sh`

Expected: FAIL because `SignalFormRow` does not exist.

- [ ] **Step 3: Refine `HeroAmountField` without changing its composition**

Keep `MXN`, centered `$0.00`, and the underline. Add:

```swift
var errorMessage: String? = nil
var currencyCode: String = "MXN"
```

Entered digits use `Theme.ink`; placeholder digits use `Theme.faint`; the symbol uses the caller's semantic tint; focus changes the underline to `Theme.accent`. Apply `.minimumScaleFactor(0.45)`, `.monospacedDigit()`, a currency-aware accessibility value, and a full-region tap target.

- [ ] **Step 4: Implement Signal rows**

Use one generic row for picker and disclosure content:

```swift
struct SignalFormRow<Trailing: View>: View {
    let label: String
    let action: (() -> Void)?
    @ViewBuilder let trailing: Trailing
}
```

Render no outer card, one full-width hairline, a 44 pt minimum height, leading label, trailing value, and optional disclosure indicator. Do not place the primary button inside the row group.

- [ ] **Step 5: Migrate the amount-entry sheets**

Replace `FormCard` wrappers beneath each hero amount with Signal rows. Keep native `DatePicker`, category picker, credit-card picker, recurrence toggles, validation, and existing request bodies. The save button remains a separate 52 pt action after the rows or in a safe-area inset.

- [ ] **Step 6: Check and commit**

Run the four global check commands. Expected: exit 0.

```bash
git add Settlr scripts/check-signal-redesign.sh
git commit -m "feat: add Signal amount forms"
```

---

### Task 4: Home hierarchy and available balance

**Files:**

- Create: `SettlrTests/DashboardSummaryTests.swift`
- Modify: `Settlr/Models/DashboardSummary.swift`
- Modify: `Settlr/ViewModels/DashboardVM.swift`
- Modify: `Settlr/Views/Main/Dashboard/DashboardView.swift`
- Modify: `Settlr/Views/Main/Dashboard/SpendingInsightsStrip.swift`
- Modify: `Settlr.xcodeproj/project.pbxproj`
- Modify: `scripts/check-signal-redesign.sh`

**Interfaces:**

- Produces: `SummaryResponse.savingsNetCents` and `availableCents`.
- Preserves: `SpendingInsights.build` and all ticker interaction values.

- [ ] **Step 1: Add failing decoding and arithmetic tests**

```swift
final class DashboardSummaryTests: XCTestCase {
    func testAvailableSubtractsSavingsFromNet() throws {
        let data = Data(#"{"incomeCents":30000,"expenseCents":10000,"netCents":20000,"savingsNetCents":5000}"#.utf8)
        let summary = try JSONDecoder().decode(SummaryResponse.self, from: data)
        XCTAssertEqual(summary.availableCents, 15_000)
    }

    func testLegacySummaryDefaultsSavingsToZero() throws {
        let data = Data(#"{"netCents":20000}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(SummaryResponse.self, from: data).availableCents, 20_000)
    }
}
```

Append source checks for `availableCents` and verify that `SpendingInsights.build` remains present.

- [ ] **Step 2: Run the source check to confirm failure**

Run: `bash scripts/check-signal-redesign.sh`

Expected: FAIL because `availableCents` is absent.

- [ ] **Step 3: Decode savings and expose available balance**

Add `savingsNetCents` to `CodingKeys`, decode it with `decodeIfPresent ?? 0`, and define:

```swift
var availableCents: Int { netCents - savingsNetCents }
```

- [ ] **Step 4: Reorder Home without touching ticker mechanics**

Render workspace/profile header, available hero, income/spending/saved summary, the existing ticker, then compact recent activity. Remove gradients and nested summary cards. Use `SignalTraceLoadingView` during refresh and `SettlrPulseLoadingView(message: "Getting your workspace")` only when no cached summary exists.

Keep the exact ticker speed, duplicate-loop measurement, drag, tap, resume delay, and Reduce Motion branch. Only update its surrounding spacing and tokens.

- [ ] **Step 5: Preserve cached summary on refresh failure**

In `DashboardVM.load`, do not set `summary = nil` when a refresh fails and a value already exists. Store `lastUpdated` after a successful response and show the inline recovery card over retained content.

- [ ] **Step 6: Register, check, and commit**

Run the four global checks. Expected: exit 0.

```bash
git add Settlr SettlrTests scripts Settlr.xcodeproj/project.pbxproj
git commit -m "feat: redesign Signal home"
```

---

### Task 5: Unified Activity Signal timeline

**Files:**

- Create: `Settlr/Models/ActivityEvent.swift`
- Create: `Settlr/ViewModels/ActivityVM.swift`
- Create: `SettlrTests/ActivityEventTests.swift`
- Modify: `Settlr/Views/Main/Activity/ActivityView.swift`
- Modify: `Settlr/Views/Components/TransactionDetailSheet.swift`
- Modify: `Settlr/Models/FeatureAccess.swift`
- Modify: `Settlr.xcodeproj/project.pbxproj`
- Modify: `scripts/check-signal-redesign.sh`

**Interfaces:**

- Produces: `ActivityEvent`, `ActivityFilter`, and `ActivityVM`.
- Consumes: existing expense, income, savings entry, and bill-split DTOs.

- [ ] **Step 1: Write failing composition tests**

Define the core model in the test contract:

```swift
enum ActivityEventKind: String, CaseIterable { case expense, income, savings, split }

struct ActivityEvent: Identifiable, Equatable {
    let id: String
    let occurredAt: Date
    let kind: ActivityEventKind
    let title: String
    let context: String
    let amountCents: Int
    let destinationID: String
}
```

Test that mixed fixtures sort newest first, completed splits do not duplicate their owned expense, and open splits are returned through `attentionEvents` rather than the completed timeline.

- [ ] **Step 2: Add source checks and confirm failure**

Require `struct ActivityEvent`, `final class ActivityVM`, `SignalTimelineRow`, and `attentionEvents`. Run the source script. Expected: FAIL.

- [ ] **Step 3: Implement the pure composer**

Add:

```swift
enum ActivityComposer {
    static func compose(
        expenses: [Expense],
        income: [Income],
        savings: [SavingsEntry],
        splits: [BillSplitSummary]
    ) -> (timeline: [ActivityEvent], attention: [BillSplitSummary])
}
```

Use stable prefixes such as `expense:`, `income:`, and `savings:` in IDs. Exclude an expense only when its owning completed split is represented by that same expense with a `Split` marker. Do not emit a second completed-split row.

- [ ] **Step 4: Add feature-aware loading in `ActivityVM`**

Fetch only enabled resources with `async let`. Missing features contribute empty arrays. Keep cached timeline data while refreshing. A `403` with a feature field triggers session refresh through the existing app-state path and recomposes available content.

- [ ] **Step 5: Build the Signal timeline and filters**

Replace the segmented ledger switch with:

- Compact type and period chips.
- A filter sheet for categories and payment sources.
- Optional attention item for open splits.
- Day groups with a thin spine.
- One lime pulse on the newest event.
- No row card and no detached amount column.

Route expense and income to `TransactionDetailSheet`, savings to account detail, and splits to `SplitDetailView`.

- [ ] **Step 6: Register, check, and commit**

Run the four global checks. Expected: exit 0.

```bash
git add Settlr SettlrTests scripts Settlr.xcodeproj/project.pbxproj
git commit -m "feat: add unified Signal activity"
```

---

### Task 6: Savings root and server-backed goal targets

**Files:**

- Create: `SettlrTests/SavingsGoalTests.swift`
- Modify: `Settlr/Models/Savings.swift`
- Modify: `Settlr/Views/Main/Savings/SavingsVM.swift`
- Modify: `Settlr/Views/Main/Savings/SavingsView.swift`
- Modify: `Settlr/Views/Main/Savings/SavingsAccountsSheet.swift`
- Modify: `Settlr/Views/Main/Savings/SavingsEntryFormSheet.swift`
- Modify: `Settlr/Views/Main/Savings/SavingsRecurringSheet.swift`
- Modify: `Settlr.xcodeproj/project.pbxproj`
- Modify: `scripts/check-signal-redesign.sh`

**Interfaces:**

- Consumes existing `/savings/accounts`, `/entries`, and `/recurring` routes.
- Produces optional goal fields on `SavingsAccount` and create/update request bodies.

- [ ] **Step 1: Write failing additive-decoding tests**

```swift
final class SavingsGoalTests: XCTestCase {
    func testTargetAccountDecodesServerProgress() throws {
        let account = try decodeAccount(#"{"id":"a","name":"Trip","currency":"MXN","color":null,"sortOrder":0,"balanceCents":2500,"targetAmountCents":10000,"targetDate":"2027-01-01","goalStatus":"in_progress","progressPct":25,"remainingCents":7500}"#)
        XCTAssertEqual(account.targetAmountCents, 10_000)
        XCTAssertEqual(account.progressPct, 25)
        XCTAssertEqual(account.goalStatus, "in_progress")
    }

    func testFlexibleAccountKeepsGoalFieldsNil() throws {
        let account = try decodeAccount(#"{"id":"a","name":"Flexible","currency":"MXN","color":null,"sortOrder":0,"balanceCents":2500}"#)
        XCTAssertNil(account.targetAmountCents)
        XCTAssertNil(account.goalStatus)
    }

    private func decodeAccount(_ json: String) throws -> SavingsAccount {
        try JSONDecoder().decode(SavingsAccount.self, from: Data(json.utf8))
    }
}
```

- [ ] **Step 2: Add source checks and confirm failure**

Require `targetAmountCents`, `targetDate`, `goalStatus`, `progressPct`, `remainingCents`, and `SavingsGoalCard`. Expected: FAIL.

- [ ] **Step 3: Extend models and request bodies additively**

Decode all five fields with `decodeIfPresent`. Add `targetAmountCents: Int?` and `targetDate: String?` to create and patch bodies. Do not compute goal status or progress in the App.

- [ ] **Step 4: Redesign Savings root and account management**

Render total saved, this-month movement, account objects, and recent entries. `SavingsGoalCard` shows server progress, remaining amount, target date, and funded state. Flexible accounts omit the progress track rather than showing zero.

Account creation and editing expose optional target amount and target date. Clearing both fields converts the account back to flexible. Reuse `HeroAmountField` and Signal rows.

- [ ] **Step 5: Preserve current entry and recurring behavior**

Keep add, withdraw, edit, delete, account filtering, and recurring rules on their existing endpoints. Successful mutations adopt the returned account or reload once. A failed refresh keeps the previous accounts visible with a Signal trace recovery message.

- [ ] **Step 6: Register, check, and commit**

Run the global checks. Confirm the Server branch `feat/savings-goal-targets` still reports its 450-test and typecheck result before manual integration, without modifying or deploying it.

```bash
git add Settlr SettlrTests scripts Settlr.xcodeproj/project.pbxproj
git commit -m "feat: add Signal savings goals"
```

---

### Task 7: Cards root and quiet fortnight navigator

**Files:**

- Create: `Settlr/Views/Main/CardsRootView.swift`
- Create: `SettlrTests/CardFortnightPresentationTests.swift`
- Modify: `Settlr/Utils/CardPaymentFortnight.swift`
- Modify: `Settlr/Views/Main/CardsView.swift`
- Modify: `Settlr/Views/Main/CardPaymentsView.swift`
- Modify: `Settlr/Views/Main/CardDetailSheet.swift`
- Modify: `Settlr/Views/Components/VirtualCardFace.swift`
- Modify: `Settlr/Views/Main/MainTabView.swift`
- Modify: `Settlr.xcodeproj/project.pbxproj`
- Modify: `scripts/check-signal-redesign.sh`

**Interfaces:**

- Produces: `CardsRootView(workspaceId:canUsePayments:)`.
- Produces: `FortnightNavigatorState` with previous, current, next, and all modes.
- Consumes existing `CardPaymentsVM`, `CardPaymentFortnight`, and card routes.

- [ ] **Step 1: Write failing navigator tests**

Test pure presentation state:

```swift
func testExactRangeLabels() {
    XCTAssertEqual(FortnightNavigatorState.current(reference: day("2026-08-20")).label, "16–31 Aug")
    XCTAssertEqual(FortnightNavigatorState.previous(reference: day("2026-08-20")).label, "1–15 Aug")
    XCTAssertEqual(FortnightNavigatorState.next(reference: day("2026-08-20")).label, "1–15 Sep")
}

func testCrossMonthSelectionKeepsResolvedDueMonth() {
    XCTAssertEqual(FortnightNavigatorState.next(reference: day("2026-08-20")).monthKeys, ["2026-09"])
}
```

Keep the current `CardPaymentFortnight` cutoff and due-month tests intact.

- [ ] **Step 2: Add source checks and confirm failure**

Require `struct CardsRootView`, `FortnightNavigator`, and `All cards` inside a `Menu`. Expected: FAIL.

- [ ] **Step 3: Build the Cards root**

Show due summary first, then swipeable `VirtualCardFace` objects and payment status. Card management remains available through overflow. If `canUsePayments` is false, omit payment content and never instantiate the payment view model.

- [ ] **Step 4: Replace the period card with the approved B control**

Implement `FortnightNavigator` with two borderless 44 pt arrows, centered exact range, and a 34 pt lime underline. Put `All cards` in overflow. Selection uses light haptic feedback. Keep previous, current, next, and all behavior.

- [ ] **Step 5: Preserve server month and paid-state behavior**

Use `resolvedDueMonthKey` when calling mark-paid and unmark-paid. Keep `paidInFull` authoritative. Rename the undo label to `Undo paid status` without changing the endpoint call. During refresh, retain cards and show `SignalTraceLoadingView`.

- [ ] **Step 6: Register, check, and commit**

Run the global checks. Expected: exit 0.

```bash
git add Settlr SettlrTests scripts Settlr.xcodeproj/project.pbxproj
git commit -m "feat: redesign Signal cards and payments"
```

---

### Task 8: Signature Scanner capture, review, and split choices

**Files:**

- Modify: `Settlr/Views/Main/Split/SplitScanFlow.swift`
- Modify: `Settlr/Views/Main/Split/ReceiptCaptureView.swift`
- Modify: `Settlr/Views/Main/Split/ScanningOverlay.swift`
- Modify: `Settlr/Views/Main/Split/SplitCreateSheet.swift`
- Modify: `Settlr/Views/Main/Split/SplitDraft.swift`
- Modify: `SettlrTests/SplitDraftTests.swift`
- Modify: `scripts/check-signal-redesign.sh`

**Interfaces:**

- Preserves: `SplitScanFlow.Outcome`, `SplitDraft.makeCreateBody`, receipt parsing, reconciliation, and pending queue creation.
- Produces: full-screen Capture, Review, Split, Result navigation inside `SplitScanFlow`.

- [ ] **Step 1: Extend payer-mode regression tests before UI changes**

Add a table test covering all four request combinations:

```swift
for payer in ["me", "each_own"] {
    for splitMode in ["by_item", "even"] {
        var draft = makeDraft(itemTotal: 1_000, selectedTotal: 1_000)
        draft.payer = payer
        draft.splitMode = splitMode
        let body = draft.makeCreateBody()
        XCTAssertEqual(body.payer, payer)
        XCTAssertEqual(body.splitMode, splitMode)
    }
}
```

Append source checks for `How was it paid?`, `I paid it all`, `Each paid their own`, `By item`, and `Evenly`.

- [ ] **Step 2: Run the source check and confirm failure**

Expected: FAIL because the approved headings are not yet present.

- [ ] **Step 3: Refine Capture and processing states**

Use a full-screen dark camera, four signal corners, a native capture control, photo picker, and explicit Close. Show scanner movement only while analysis is active. Reduce Motion holds the scanner cue static. Keep camera permissions and `ReceiptPhotoUpload` unchanged.

- [ ] **Step 4: Refine Review around uncertainty**

Show merchant, printed total, date, payment method, category, parser confidence, items, and current reconciliation warnings. Only unverified rows and mismatches receive signal attention. Keep Retake, manual edit, `confirmKeepReceiptTotal`, and `useCalculatedTotal`.

- [ ] **Step 5: Place payer choice before division choice**

Use two explicit selectable rows for `me` and `each_own`, followed by a native segmented control for `by_item` and `even`. Keep headcount, optional guest names, tips, tax, fee, card choice, shared quantities, and pass-the-phone data in the draft.

- [ ] **Step 6: Check and commit**

Run the global checks and existing parser/receipt source checks. Expected: exit 0.

```bash
git add Settlr SettlrTests scripts/check-signal-redesign.sh
git commit -m "feat: redesign Signature Scanner creation"
```

---

### Task 9: Split result, settlement states, and branded QR handoff

**Files:**

- Modify: `Settlr/Views/Main/Split/SplitResultView.swift`
- Modify: `Settlr/Views/Main/Split/SplitDetailView.swift`
- Modify: `Settlr/Views/Main/Split/ExpenseSplitSection.swift`
- Modify: `Settlr/Views/Main/Split/SplitQRSheet.swift`
- Modify: `Settlr/Views/Main/Split/SplitPassAroundView.swift`
- Modify: `Settlr/Views/Main/Split/PublicSplitClaimView.swift`
- Modify: `SettlrTests/EachOwnPresentationTests.swift`
- Modify: `SettlrTests/PassAroundStateTests.swift`
- Modify: `scripts/check-signal-redesign.sh`

**Interfaces:**

- Consumes: existing `SplitAccountingPresentation`, settle endpoint, share URL, and versioned mutations.
- Preserves: owner-only settlement controls, public claim permissions, and stale-version refresh.

- [ ] **Step 1: Add result and QR source checks**

Require `Ready to settle.`, `Show QR`, `Scan to join`, `Share split`, `Mark paid`, and `Undo`. Keep the existing prohibited-copy assertions for `each_own`.

- [ ] **Step 2: Verify source checks fail on the new result copy**

Run the Signal source script. Expected: FAIL until the result and QR copy is present.

- [ ] **Step 3: Render payer-correct result states**

For `.organizerPaid`, show total, organizer share, amount to collect, participant status, mark-paid, Undo, and Share reminder. For `.eachOwn`, show total, organizer share, everyone else's shares, and no settlement control. `.unavailable` keeps its review-required path.

- [ ] **Step 4: Keep editing and concurrency safeguards visible**

If any participant is settled, keep money editing locked and explain that settlements must be undone. A `409` replaces the local split with the server response, retains safe pending selection, and presents a retry message. Queued creation says `Waiting to upload`, not created.

- [ ] **Step 5: Redesign `SplitQRSheet`**

Keep the current share URL as QR payload. Place `Image("SettlrLogo")` in a protected center plate only if the QR generator reserves a sufficient clear area and high error correction. Outside the code show merchant context, Copy link, and system Share. Add a text `Show QR` action on result and detail screens.

- [ ] **Step 6: Preserve public and pass-the-phone behavior**

Apply tokens and accessibility only. Do not expose organizer cards or owner settlement controls to participants. Keep item availability, shared claims, unit steppers, join, and claim endpoints unchanged.

- [ ] **Step 7: Check and commit**

Run the global checks. Expected: exit 0.

```bash
git add Settlr SettlrTests scripts/check-signal-redesign.sh
git commit -m "feat: redesign split settlement and QR handoff"
```

---

### Task 10: Authentication, workspaces, settings, and final system-state polish

**Files:**

- Modify: `Settlr/ContentView.swift`
- Modify: `Settlr/Views/Auth/LoginView.swift`
- Modify: `Settlr/Views/Auth/SignupView.swift`
- Modify: `Settlr/Views/Auth/AccountDeactivatedView.swift`
- Modify: `Settlr/Views/WorkspacePickerView.swift`
- Modify: `Settlr/Views/Main/Settings/SettingsView.swift`
- Modify: `Settlr/Views/Main/Settings/TelegramSettingsSection.swift`
- Modify: `Settlr/Views/Components/TransactionDetailSheet.swift`
- Modify: all redesigned root views that still hard-code `.preferredColorScheme(.dark)` or legacy hex tokens
- Modify: `scripts/check-signal-redesign.sh`

**Interfaces:**

- Consumes: appearance and loading primitives from Task 1.
- Preserves: current authentication, workspace bootstrap, workspace selection, Telegram, and settings endpoint behavior.

- [ ] **Step 1: Add final source checks**

Require every redesigned root to use `Theme.bg`, and reject leaf-level `.preferredColorScheme(.dark)`:

```sh
if rg -n '\.preferredColorScheme\(\.dark\)' Settlr/Views; then
  echo "leaf views must inherit the app appearance" >&2
  exit 1
fi
```

Also require `SettlrPulseLoadingView(message: "Getting your workspace")` in workspace bootstrap and all three appearance choices in Settings.

- [ ] **Step 2: Confirm the checks fail**

Run: `bash scripts/check-signal-redesign.sh`

Expected: FAIL while legacy hard-coded dark appearance remains.

- [ ] **Step 3: Visually align auth and workspace screens**

Use the existing fields, validation, keyboard behavior, and calls. Apply Signal Black tokens, the existing logo, one primary action, and specific inline errors. Workspace bootstrap uses the Settlr pulse. Workspace selection uses object cards only for actual workspaces.

- [ ] **Step 4: Finish Settings and appearance behavior**

Keep profile, workspace, Telegram, sign-out, and account behavior. Add the approved Dark, Light, and System selector. Remove per-screen forced dark mode. Use native destructive roles for sign-out and account actions.

- [ ] **Step 5: Audit empty, loading, error, and accessibility states**

For every root screen, record which approved pattern it uses:

- Refresh with cached data: Signal trace.
- Cold start or workspace switch: Settlr pulse.
- First Activity geometry: Activity-shaped skeleton.
- Empty: compact glyph, direct explanation, one resolving action.
- Error: keep valid content, explain impact, provide Retry.

Check 44 pt targets, Dynamic Type, VoiceOver values for money, color-independent status, Increase Contrast separators, Reduce Motion, keyboard dismissal, and origin-preserving modal dismissal.

- [ ] **Step 6: Run the complete non-build verification**

Run:

```bash
bash scripts/check-signal-redesign.sh
bash scripts/check-app-source-regressions.sh
ruby scripts/test-testflight-workflow.rb
git diff --check
git status --short
```

Expected: all checks exit 0. `git status` shows only the intended Task 10 files before commit.

- [ ] **Step 7: Commit final polish**

```bash
git add Settlr scripts/check-signal-redesign.sh
git commit -m "feat: finish Signal Black app redesign"
```

---

### Task 11: User-run build and manual acceptance

**Files:**

- No source changes unless this acceptance pass finds a defect.
- Reference: `docs/design-system/SETTLR_SIGNAL.md`
- Reference: `docs/superpowers/specs/2026-08-28-signal-black-app-redesign-design.md`

**Interfaces:**

- Consumes all previous phases.
- Produces the final acceptance record and any narrowly scoped bug-fix commits.

- [ ] **Step 1: Ask the user to run the App build**

User command:

```bash
xcodebuild -project Settlr.xcodeproj -scheme Settlr -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug -derivedDataPath build build
```

Expected: `BUILD SUCCEEDED`. If the simulator name differs, the user selects an installed iPhone simulator in Xcode.

- [ ] **Step 2: Ask the user to run the XCTest target**

User command:

```bash
xcodebuild test -project Settlr.xcodeproj -scheme Settlr -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build
```

Expected: all existing and new tests pass.

- [ ] **Step 3: Complete the visual matrix**

On one compact and one large iPhone, verify Dark, Light, and System; default Dark; Dynamic Type; VoiceOver; Reduce Motion; Increase Contrast; keyboard behavior; offline mode; stale split version; and feature combinations.

- [ ] **Step 4: Complete product acceptance**

Verify:

- Home retains the approved insight ticker and correct available balance.
- Activity has no duplicate completed split events.
- Savings handles flexible, partial, funded, past-due, and legacy accounts.
- Cards handles previous, current, next, cross-month, all cards, mark paid, and Undo with the resolved month.
- Scanner covers all four payer/division combinations.
- Split close, reopen, mark paid, Undo, QR scan, public join, pass-the-phone, and queued creation remain correct.
- Auth and workspace behavior are unchanged.

- [ ] **Step 5: Fix only observed defects and re-run the affected gate**

Stay on `feat/signal-black-redesign-spec`. For each independent defect, add a regression test or source check first, reproduce the failure, implement the minimum correction, rerun the affected checks, and make a separate fix commit.

## Self-review record

- Spec coverage: identity, tokens, navigation, launcher, Home, Activity, Savings, Cards, scanner, payer modes, settlement, QR, forms, loading, empty/error states, appearance, accessibility, endpoint compatibility, and verification each map to a task above.
- Placeholder scan: no `TBD`, `TODO`, `implement later`, or unspecified error-handling steps remain.
- Type consistency: `SettlrAppearance`, `QuickActionItem`, `QuickActionLauncher`, `ActivityEvent`, `ActivityComposer`, `ActivityVM`, `CardsRootView`, and `FortnightNavigatorState` are introduced before later tasks consume them.
- Scope: every task yields an independently reviewable App commit on the single approved App feature branch. Server work stays untouched on its existing feature branch.

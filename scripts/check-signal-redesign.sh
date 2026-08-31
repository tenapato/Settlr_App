#!/bin/sh
set -eu

grep -Fq 'enum SettlrAppearance' Settlr/Models/AppearancePreference.swift
grep -Fq 'static let accentText' Settlr/Views/Components/DesignSystem.swift
grep -Fq 'struct SignalTraceLoadingView' Settlr/Views/Components/SignalLoadingViews.swift
grep -Fq 'struct SettlrPulseLoadingView' Settlr/Views/Components/SignalLoadingViews.swift
grep -Fq 'struct ActivityShapeLoadingView' Settlr/Views/Components/SignalLoadingViews.swift
grep -Fq '@AppStorage("settlr.appearance")' Settlr/SettlrApp.swift
grep -Fq '.fill(Theme.surface)' Settlr/Views/Components/SectionCard.swift
grep -Fq '.strokeBorder(Theme.line' Settlr/Views/Components/SectionCard.swift
grep -Fq 'static let buttonInk' Settlr/Views/Components/DesignSystem.swift
grep -Fq '.foregroundStyle(Theme.buttonInk)' Settlr/Views/Components/DesignSystem.swift
grep -Fq 'presentation.isSelected ? Theme.accentText' Settlr/Views/Components/DesignSystem.swift
grep -Fq 'case home, activity, savings, cards' Settlr/Views/Components/FloatingTabBar.swift
grep -Fq 'struct QuickActionLauncher' Settlr/Views/Components/QuickActionLauncher.swift
grep -Fq 'Scan and split' Settlr/Views/Components/QuickActionLauncher.swift
launcher=Settlr/Views/Components/QuickActionLauncher.swift
grep -Fq 'VStack(alignment: .leading, spacing: 8)' "$launcher"
grep -Fq '.frame(width: 30, height: 30)' "$launcher"
grep -Fq '.frame(width: 200, alignment: .leading)' "$launcher"
grep -Fq '.frame(minHeight: 44)' "$launcher"
grep -Fq '.padding(10)' "$launcher"
grep -Fq 'colorScheme == .dark ? 0.55 : 0.12' "$launcher"
grep -Fq '.font(.caption)' "$launcher"
if grep -Fq '.padding(.trailing, 8)' "$launcher"; then
    echo "Quick action menu must share the launcher right edge." >&2
    exit 1
fi
if grep -Fq '.font(.system(size: isSignature' "$launcher"; then
    echo "Quick action row typography must scale with Dynamic Type." >&2
    exit 1
fi
if grep -Fq 'minWidth: isSignature ?' "$launcher"; then
    echo "Quick action rows must share one symmetric width." >&2
    exit 1
fi
if grep -Fq '.frame(width: 200, minHeight:' "$launcher"; then
    echo "Quick action rows must use valid SwiftUI frame overloads." >&2
    exit 1
fi
grep -Fq 'same row and column geometry' docs/design-system/SETTLR_SIGNAL.md
grep -Fq 'class="sat-ico"' docs/design-system/settlr-signal-components.html
grep -Fq '.satellite{border-radius:16px;padding:10px}' docs/design-system/settlr-signal-components.html
grep -Fq '.sat-action.heroaction{height:45px;background:transparent' docs/design-system/settlr-signal-components.html
grep -Fq '@State private var showCategories = false' Settlr/Views/Main/MainTabView.swift
grep -Fq '.sheet(isPresented: categoriesPresentation)' Settlr/Views/Main/MainTabView.swift
grep -Fq 'CategoriesView(workspaceId: appState.activeWorkspace?.id ?? "")' Settlr/Views/Main/MainTabView.swift
grep -Fq 'await expensesVM.loadCategories' Settlr/Views/Main/MainTabView.swift
grep -Fq 'await incomeVM.loadCategories' Settlr/Views/Main/MainTabView.swift
grep -Fq '.background(Theme.bg)' Settlr/Views/Main/MainTabView.swift
grep -Fq 'Theme.accentText : Theme.muted' Settlr/Views/Components/FloatingTabBar.swift
if rg -q '\.onExitCommand' Settlr/Views/Components/QuickActionLauncher.swift; then
    echo "QuickActionLauncher must use iOS-supported dismissal APIs." >&2
    exit 1
fi

# Task 3: Signal amount forms and reusable border-light rows.
grep -Fq 'struct SignalFormRow' Settlr/Views/Components/FormControls.swift
grep -Fq '.monospacedDigit()' Settlr/Views/Components/FormControls.swift
grep -Fq 'accessibilityLabel("Amount in Mexican pesos")' Settlr/Views/Components/FormControls.swift
grep -Fq 'SignalFormRow' Settlr/Views/Main/Expenses/ExpenseFormSheet.swift
grep -Fq 'SignalFormRow' Settlr/Views/Main/Income/IncomeFormSheet.swift
grep -Fq 'SignalFormRow' Settlr/Views/Main/Savings/SavingsEntryFormSheet.swift

# Task 3 fix round 1: validation, bounded hero layout, native row ownership,
# feature-gated card controls, and the remaining split form migration.
grep -Fq 'errorMessage: errorMessage' Settlr/Views/Main/Expenses/ExpenseFormSheet.swift
grep -Fq 'errorMessage: errorMessage' Settlr/Views/Main/Income/IncomeFormSheet.swift
grep -Fq 'errorMessage: errorMessage' Settlr/Views/Main/Savings/SavingsEntryFormSheet.swift
grep -Fq 'errorMessage: errorMessage' Settlr/Views/Main/Income/IncomeRecurringSheet.swift
grep -Fq 'errorMessage: errorMessage' Settlr/Views/Main/Savings/SavingsRecurringSheet.swift
grep -Fq '.frame(maxWidth: .infinity)' Settlr/Views/Components/FormControls.swift
grep -Fq 'struct SignalNativeFormRow' Settlr/Views/Components/FormControls.swift
grep -Fq 'SignalNativeFormRow' Settlr/Views/Main/Expenses/ExpenseFormSheet.swift
grep -Fq 'SignalNativeFormRow' Settlr/Views/Main/Income/IncomeFormSheet.swift
grep -Fq 'SignalNativeFormRow' Settlr/Views/Main/Savings/SavingsEntryFormSheet.swift
grep -Fq 'SignalNativeFormRow' Settlr/Views/Main/Income/IncomeRecurringSheet.swift
grep -Fq 'SignalNativeFormRow' Settlr/Views/Main/Savings/SavingsRecurringSheet.swift
grep -Fq 'canUseCreditCards' Settlr/Views/Main/Expenses/ExpenseFormSheet.swift
grep -Fq 'canUseCreditCards' Settlr/Views/Main/Split/SplitCreateSheet.swift
grep -Fq 'SignalNativeFormRow' Settlr/Views/Main/Split/SplitCreateSheet.swift
grep -Fq 'DatePicker("Date"' Settlr/Views/Main/Split/SplitCreateSheet.swift
grep -Fq 'HeroAmountField' Settlr/Views/Main/Split/SplitCreateSheet.swift
grep -Fq 'Theme.accentText' Settlr/Views/Main/CardPaymentsView.swift

# Task 3 fix round 2: normalize gated state before presenting/saving and keep
# manual by-item totals editable.
grep -Fq 'normalizeCardPaymentState()' Settlr/Views/Main/Expenses/ExpenseFormSheet.swift
grep -Fq 'normalizeCardPaymentState()' Settlr/Views/Main/Split/SplitCreateSheet.swift
grep -Fq 'paymentChannel: effectivePaymentChannel' Settlr/Views/Main/Expenses/ExpenseFormSheet.swift
grep -Fq 'creditCardId: effectiveCreditCardId' Settlr/Views/Main/Expenses/ExpenseFormSheet.swift
grep -Fq 'if !isEditing && !hasScanned' Settlr/Views/Main/Split/SplitCreateSheet.swift
grep -Fq 'quantity > 1 ? Theme.accentText' Settlr/Views/Main/Split/SplitCreateSheet.swift

# Task 3 fix round 3: react to feature revocation and close the submit-time
# normalization window opened by the claims confirmation dialog.
grep -Fq '.onChange(of: canUseCreditCards)' Settlr/Views/Main/Expenses/ExpenseFormSheet.swift
grep -Fq 'normalizeCardPaymentState()' Settlr/Views/Main/Expenses/ExpenseFormSheet.swift
if ! rg -U -q 'private func submitEdit\(clearClaimsFor: Set<String>\) \{\n[[:space:]]+guard let editingSplit else \{ return \}\n[[:space:]]+normalizeCardPaymentState\(\)\n[[:space:]]+let bodyDraft = submissionDraft' Settlr/Views/Main/Split/SplitCreateSheet.swift; then
    echo "Split submitEdit must normalize gated card state immediately before building its request draft." >&2
    exit 1
fi

# Task 4: available balance, retained dashboard data, and the existing ticker.
grep -Fq 'var availableCents: Int' Settlr/Models/DashboardSummary.swift
grep -Fq 'savingsNetCents' Settlr/Models/DashboardSummary.swift
grep -Fq 'SpendingInsights.build' Settlr/Views/Main/Dashboard/SpendingInsightsStrip.swift
grep -Fq 'SignalTraceLoadingView' Settlr/Views/Main/Dashboard/DashboardView.swift
grep -Fq 'SettlrPulseLoadingView' Settlr/Views/Main/Dashboard/DashboardView.swift
grep -Fq 'lastUpdated' Settlr/ViewModels/DashboardVM.swift
grep -Fq 'SpendingBreakdownCard(summary: summary)' Settlr/Views/Main/Dashboard/DashboardView.swift
grep -Fq '.accessibilityValue(displayMonth)' Settlr/Views/Main/Dashboard/DashboardView.swift

# Task 5: unified Activity composer, feature-aware VM, and Signal timeline.
grep -Fq 'struct ActivityEvent' Settlr/Models/ActivityEvent.swift
grep -Fq 'final class ActivityVM' Settlr/ViewModels/ActivityVM.swift
grep -Fq 'struct SignalTimelineRow' Settlr/Views/Main/Activity/ActivityView.swift
grep -Fq 'attentionEvents' Settlr/ViewModels/ActivityVM.swift
activity_view=Settlr/Views/Main/Activity/ActivityView.swift
grep -Fq 'private var activityFilters: some View' "$activity_view"
grep -Fq 'SectionEyebrow("ACTIVITY TYPE")' "$activity_view"
grep -Fq 'private var activityPeriodMenu: some View' "$activity_view"
grep -Fq 'Image(systemName: "calendar")' "$activity_view"
grep -Fq 'Text("Time range")' "$activity_view"
if grep -Fq 'ForEach(ActivityPeriodFilter.allCases) { period in chip' "$activity_view"; then
    echo "Activity type and period controls must not share one chip row." >&2
    exit 1
fi

# Task 5 fix round 1: leaf form ownership, gate revocation, card-source
# semantics, and workspace-safe reloads.
grep -Fq '.sheet(isPresented: $showExpenseForm)' Settlr/Views/Main/Activity/ActivityView.swift
grep -Fq '.sheet(isPresented: $showIncomeForm)' Settlr/Views/Main/Activity/ActivityView.swift
grep -Fq 'activitySavingsFormPresentation' Settlr/Views/Main/Activity/ActivityView.swift
grep -Fq 'selectedTab != .activity' Settlr/Views/Main/MainTabView.swift
grep -Fq 'reconcileFeatures(for user: MeUser?)' Settlr/ViewModels/ActivityVM.swift
grep -Fq 'source == "credit_card"' Settlr/ViewModels/ActivityVM.swift
grep -Fq 'if !cardsEnabled || !expensesEnabled' Settlr/ViewModels/ActivityVM.swift
grep -Fq 'return' Settlr/ViewModels/ActivityVM.swift
grep -Fq 'resetForWorkspace()' Settlr/ViewModels/ActivityVM.swift
grep -Fq '.task(id: workspaceId)' Settlr/Views/Main/Activity/ActivityView.swift
grep -Fq 'reloadActivityIfCurrentWorkspace' Settlr/Views/Main/Activity/ActivityView.swift
grep -Fq 'SavingsAccountsSheet(workspaceId: workspaceId, vm: savingsVM)' Settlr/Views/Main/Activity/ActivityView.swift
grep -Fq 'reload: false' Settlr/Views/Main/Activity/ActivityView.swift
if ! rg -U -q 'body: CreateRecurringIncomeBody\(\n[[:space:]]+amountCents: body\.amountCents,\n[[:space:]]+description: body\.description,\n[[:space:]]+frequency: repeatEvery\.rawValue,\n[[:space:]]+startDate: body\.occurredAt,\n[[:space:]]+categoryId: body\.categoryId\n[[:space:]]+\),\n[[:space:]]+reload: false,\n[[:space:]]+expectedGeneration: generation' Settlr/Views/Main/Activity/ActivityView.swift; then
    echo "Activity recurring income must close its body at categoryId and pass reload/generation to createRecurring." >&2
    exit 1
fi

# Task 5 fix round 3: workspace-safe Activity mutations, account-gated global
# Savings quick actions, independent account loading, and duplicate-submit
# protection in the account-management form.
grep -Fq 'workspaceMutationGeneration(for workspaceId: String)' Settlr/ViewModels/ExpensesVM.swift
grep -Fq 'workspaceMutationGeneration(for workspaceId: String)' Settlr/ViewModels/IncomeVM.swift
grep -Fq 'expectedGeneration: Int? = nil' Settlr/ViewModels/ExpensesVM.swift
grep -Fq 'expectedGeneration: Int? = nil' Settlr/ViewModels/IncomeVM.swift
grep -Fq 'expectedGeneration: Int? = nil' Settlr/Views/Main/Savings/SavingsVM.swift
grep -Fq 'if generation == loadGeneration, activeWorkspaceID == workspaceId {' Settlr/Views/Main/Savings/SavingsVM.swift
grep -Fq 'showRootSavingsAccounts' Settlr/Views/Main/MainTabView.swift
grep -Fq 'prepareGlobalSavingsForm()' Settlr/Views/Main/MainTabView.swift
grep -Fq 'savingsVM.hasLoadedAccounts' Settlr/Views/Main/MainTabView.swift
grep -Fq '@State private var isSavingAccount = false' Settlr/Views/Main/Savings/SavingsAccountsSheet.swift
grep -Fq 'isSaving: isSavingAccount' Settlr/Views/Main/Savings/SavingsAccountsSheet.swift

# Task 5 fix round 4: Activity-owned Savings handoff, workspace-safe detail
# mutations, and non-dismissible in-flight account forms.
grep -Fq 'if selectedTab == .activity' Settlr/Views/Main/MainTabView.swift
grep -Fq 'onDeleted:' Settlr/Views/Main/Activity/ActivityView.swift
grep -Fq 'isWorkspaceCurrent:' Settlr/Views/Main/Activity/ActivityView.swift
grep -Fq 'guard isWorkspaceCurrent() else { return nil }' Settlr/Views/Components/TransactionDetailSheet.swift
grep -Fq '.interactiveDismissDisabled(isSaving)' Settlr/Views/Main/Savings/SavingsAccountsSheet.swift

# Task 5 fix round 5: Activity's Savings entry presenter must use the same
# current-workspace, successful-account guards as the root presenter.
grep -Fq 'savingsVM.loadedWorkspaceID == workspaceId' Settlr/Views/Main/Activity/ActivityView.swift
grep -Fq 'savingsVM.accountsErrorMessage == nil' Settlr/Views/Main/Activity/ActivityView.swift

# Activity body type-check regression: keep navigation, detail sheets, form
# sheets, and lifecycle handlers in separately type-checked view layers.
activity_view=Settlr/Views/Main/Activity/ActivityView.swift
for layer in \
  'private var activityBaseNavigation: some View' \
  'private var activityDetailSheets: some View' \
  'private var activityFormSheets: some View' \
  'private var activityLifecycle: some View'; do
  if ! grep -Fq "$layer" "$activity_view"; then
    echo "ActivityView must define the separately type-checked layer: $layer" >&2
    exit 1
  fi
done
if ! grep -Fq 'activityLifecycle' "$activity_view"; then
  echo "ActivityView.body must terminate at the lifecycle view layer." >&2
  exit 1
fi
if ! grep -Fq 'private func savingsDestinationView' "$activity_view"; then
  echo "Activity savings destination content must be isolated in a helper view function." >&2
  exit 1
fi

# Task 6: additive server-backed Savings goals and settled account presenters.
for field in targetAmountCents targetDate goalStatus progressPct remainingCents; do
  grep -Fq "$field" Settlr/Models/Savings.swift
done
grep -Fq 'struct SavingsGoalCard' Settlr/Views/Main/Savings/SavingsView.swift
grep -Fq 'SavingsGoalCard(account: account, isSelected: vm.selectedAccountId == account.id)' Settlr/Views/Main/Savings/SavingsView.swift
grep -Fq 'YOUR GOALS' Settlr/Views/Main/Savings/SavingsView.swift
grep -Fq 'FLEXIBLE SAVINGS' Settlr/Views/Main/Savings/SavingsView.swift
grep -Fq 'accountsErrorMessage' Settlr/Views/Main/Savings/SavingsVM.swift
grep -Fq 'entriesErrorMessage' Settlr/Views/Main/Savings/SavingsVM.swift
grep -Fq 'parseSavingsTargetAmount' Settlr/Models/Savings.swift
grep -Fq 'Savings accounts unavailable' Settlr/Views/Main/Savings/SavingsView.swift
grep -Fq 'if vm.isLoading && vm.loadedWorkspaceID == workspaceId' Settlr/Views/Main/Savings/SavingsView.swift
grep -Fq 'guard vm.accountsRequestIsSettled(for: workspaceId), vm.hasLoadedAccounts' Settlr/Views/Main/Savings/SavingsView.swift
grep -Fq 'Target amount' Settlr/Views/Main/Savings/SavingsAccountsSheet.swift
grep -Fq 'accountsRequestIsSettled' Settlr/Views/Main/Savings/SavingsVM.swift
grep -Fq 'accountsRequestIsSettled(for: workspaceId)' Settlr/Views/Main/Activity/ActivityView.swift
grep -Fq 'accountsRequestIsSettled(for: rootWorkspaceID)' Settlr/Views/Main/MainTabView.swift
grep -Fq 'SavingsGoalTests.swift' Settlr.xcodeproj/project.pbxproj
savings_view=Settlr/Views/Main/Savings/SavingsView.swift
account_chips=$(sed -n '/private var accountChips: some View {/,/^    private var accountObjects:/p' "$savings_view")
if printf '%s\n' "$account_chips" | grep -Fq '.padding(.horizontal, 24)'; then
    echo "Savings account chips must not add a second horizontal inset inside the padded root." >&2
    exit 1
fi
if [ "$(grep -Fc '.frame(maxWidth: .infinity, alignment: .leading)' "$savings_view")" -lt 4 ]; then
    echo "Savings root and object sections must claim the full content width before centering child states." >&2
    exit 1
fi
if ! rg -U -q 'private var noEntriesState: some View \{(?s).*\.frame\(maxWidth: \.infinity\)(?s).*\.padding\(\.horizontal, 32\)' "$savings_view"; then
    echo "Savings empty entries state must center against the full screen content width." >&2
    exit 1
fi

# Task 7: Cards root and quiet fortnight navigator.
grep -Fq 'struct CardsRootView' Settlr/Views/Main/CardsRootView.swift
grep -Fq 'struct FortnightNavigator' Settlr/Views/Main/CardsRootView.swift
grep -Fq 'Button("All cards")' Settlr/Views/Main/CardsRootView.swift
grep -Fq 'FortnightNavigatorState' Settlr/Utils/CardPaymentFortnight.swift
grep -Fq 'resolvedDueMonthKey' Settlr/Views/Main/CardPaymentsView.swift
grep -Fq 'Undo paid status' Settlr/Views/Main/CardPaymentsView.swift
grep -Fq 'SignalTraceLoadingView' Settlr/Views/Main/CardsRootView.swift
grep -Fq 'CardsRootView(' Settlr/Views/Main/MainTabView.swift
grep -Fq 'CardFortnightPresentationTests.swift' Settlr.xcodeproj/project.pbxproj
cards_root=Settlr/Views/Main/CardsRootView.swift
if ! rg -U -q '\.padding\(\.top, 8\)\n[[:space:]]+\.frame\(maxWidth: \.infinity, alignment: \.leading\)\n[[:space:]]+\}' "$cards_root"; then
    echo "Cards root scroll content must claim the full screen width." >&2
    exit 1
fi
if rg -q '\.preferredColorScheme\(\.dark\)' Settlr/Views/Main/CardsView.swift Settlr/Views/Main/CardDetailSheet.swift; then
    echo "Cards views must follow the app appearance preference." >&2
    exit 1
fi

# Task 9: payer-correct result states, settlement safeguards, and branded QR.
grep -Fq 'Ready to settle.' Settlr/Views/Main/Split/SplitResultView.swift
grep -Fq 'Show QR' Settlr/Views/Main/Split/SplitResultView.swift
grep -Fq 'Scan to join' Settlr/Views/Main/Split/SplitQRSheet.swift
grep -Fq 'Share split' Settlr/Views/Main/Split/SplitResultView.swift
grep -Fq 'Mark paid' Settlr/Views/Main/Split/SplitResultView.swift
grep -Fq 'Undo' Settlr/Views/Main/Split/SplitResultView.swift
grep -Fq 'Waiting to upload' Settlr/Views/Main/Split/SplitScanFlow.swift
grep -Fq 'reservesCenterBranding' Settlr/Views/Main/Split/SplitQRSheet.swift
grep -Fq 'protectedCenter' Settlr/Views/Main/Split/SplitQRSheet.swift
grep -Fq 'showSettledEditExplanation' Settlr/Views/Main/Split/SplitDetailView.swift
grep -Fq 'Everyone paid their own share' Settlr/Views/Main/Split/SplitResultView.swift
grep -Fq 'Amount to collect' Settlr/Views/Main/Split/SplitResultView.swift
grep -Fq 'retry' Settlr/ViewModels/BillSplitVM.swift
grep -Fq 'testResultPresentationKeepsSettlementCopyPayerCorrect' SettlrTests/EachOwnPresentationTests.swift
grep -Fq 'func showsSettlementControls' Settlr/Views/Main/Split/SplitResultView.swift
grep -Fq 'static func aggregateOtherShares' Settlr/Views/Main/Split/SplitResultView.swift
grep -Fq 'showsParticipantBalances' Settlr/Views/Main/Split/SplitResultView.swift
grep -Fq 'Finish claiming to settle.' Settlr/Views/Main/Split/SplitResultView.swift
grep -Fq 'Retry when you'\''re ready.' Settlr/Views/Main/Split/SplitResultView.swift
grep -Fq 'Retry when you'\''re ready.' Settlr/Views/Main/Split/SplitDetailView.swift
grep -Fq 'currentSplit.isOpen' Settlr/Views/Main/Split/SplitResultView.swift
grep -Fq 'currentSplit.guests.map' Settlr/Views/Main/Split/SplitResultView.swift
grep -Fq 'Theme.buttonInk' Settlr/Views/Main/Split/SplitScanFlow.swift

# Task 10: app appearance is owned by SettlrApp. Redesigned roots inherit it,
# and the workspace bootstrap uses the cold-start Settlr pulse.
if rg -n '\.preferredColorScheme\(\.dark\)' Settlr/Views; then
    echo "Leaf views must inherit the app appearance preference." >&2
    exit 1
fi

for signal_root in \
  Settlr/ContentView.swift \
  Settlr/Views/Auth/LoginView.swift \
  Settlr/Views/Auth/SignupView.swift \
  Settlr/Views/Auth/AccountDeactivatedView.swift \
  Settlr/Views/WorkspacePickerView.swift \
  Settlr/Views/Main/Settings/SettingsView.swift \
  Settlr/Views/Main/Dashboard/DashboardView.swift \
  Settlr/Views/Main/Activity/ActivityView.swift \
  Settlr/Views/Main/Savings/SavingsView.swift \
  Settlr/Views/Main/CardsRootView.swift \
  Settlr/Views/Main/CategoriesView.swift \
  Settlr/Views/Main/Split/SplitScanFlow.swift \
  Settlr/Views/Main/Split/SplitResultView.swift \
  Settlr/Views/Main/Split/SplitDetailView.swift; do
  if ! grep -Fq 'Theme.bg' "$signal_root"; then
    echo "Signal root must use Theme.bg: $signal_root" >&2
    exit 1
  fi
done

grep -Fq 'message: "Getting your workspace"' Settlr/ContentView.swift

# The production cold-start loader and bottom navigation must retain the
# approved Signal preview geometry. These are wiring guards only; the user-run
# simulator pass remains the visual proof.
loading_view=Settlr/Views/Components/SignalLoadingViews.swift
grep -Fq '.frame(width: 65, height: 65)' "$loading_view"
grep -Fq '.frame(width: 31, height: 5)' "$loading_view"
grep -Fq '.offset(x: index == 1 ? 5 : 0)' "$loading_view"
grep -Fq 'Theme.muted.opacity(0.38)' "$loading_view"
grep -Fq 'Loading balances and account access.' Settlr/ContentView.swift
grep -Fq 'Loading balances and account access.' Settlr/Views/Main/Dashboard/DashboardView.swift
if grep -Fq 'Image("SettlrLogo")' Settlr/ContentView.swift; then
    echo "Cold-start loader must not render a duplicate logo above the pulse mark." >&2
    exit 1
fi

tab_bar=Settlr/Views/Components/FloatingTabBar.swift
grep -Fq 'VStack(spacing: 3)' "$tab_bar"
grep -Fq 'Text(tab.title)' "$tab_bar"
grep -Fq '.frame(maxWidth: .infinity, minHeight: 49)' "$tab_bar"
if grep -Fq 'matchedGeometryEffect' "$tab_bar"; then
    echo "Signal tabs must not expand into a selected pill." >&2
    exit 1
fi
grep -Fq '.padding(.trailing, quickActionItems.isEmpty ? 0 : 64)' Settlr/Views/Main/MainTabView.swift
grep -Fq 'colorScheme == .dark ? 0.48 : 0.12' Settlr/Views/Main/MainTabView.swift

grep -Fq 'ForEach(SettlrAppearance.allCases)' Settlr/Views/Main/Settings/SettingsView.swift
grep -Fq 'case dark' Settlr/Models/AppearancePreference.swift
grep -Fq 'case light' Settlr/Models/AppearancePreference.swift
grep -Fq 'case system' Settlr/Models/AppearancePreference.swift

# Task 10 fix round 1: shared destructive confirmation inherits adaptive
# Signal colors, and manual workspace creation cannot race bootstrap loading.
delete_dialog=Settlr/Views/Components/DeleteConfirmDialog.swift
for token in Theme.scrim Theme.expense Theme.destructiveButtonInk Theme.surface Theme.surface2 Theme.line Theme.ink Theme.muted; do
  grep -Fq "$token" "$delete_dialog"
done
if grep -Fq 'Color(hex:' "$delete_dialog"; then
    echo "DeleteConfirmDialog must not retain forced-dark literal colors." >&2
    exit 1
fi
grep -Fq 'if (vm.errorMessage == nil || !vm.workspaces.isEmpty) && !vm.isLoading {' Settlr/Views/WorkspacePickerView.swift
grep -Fq 'guard !isLoading else { return nil }' Settlr/ViewModels/WorkspacePickerVM.swift

# Task 8: Signature Scanner capture, review, and payer/division ordering.
grep -Fq 'How was it paid?' Settlr/Views/Main/Split/SplitCreateSheet.swift
grep -Fq 'I paid it all' Settlr/Views/Main/Split/SplitCreateSheet.swift
grep -Fq 'Each paid their own' Settlr/Views/Main/Split/SplitCreateSheet.swift
grep -Fq 'By item' Settlr/Views/Main/Split/SplitCreateSheet.swift
grep -Fq 'Evenly' Settlr/Views/Main/Split/SplitCreateSheet.swift
grep -Fq 'enum SplitScanStage' Settlr/Views/Main/Split/SplitScanFlow.swift
grep -Fq 'case capture, review, split, result' Settlr/Views/Main/Split/SplitScanFlow.swift
grep -Fq 'accessibilityReduceMotion' Settlr/Views/Main/Split/ScanningOverlay.swift
grep -Fq 'Review' Settlr/Views/Main/Split/SplitCreateSheet.swift
grep -Fq 'Parser confidence' Settlr/Views/Main/Split/SplitCreateSheet.swift
grep -Fq 'Unverified rows' Settlr/Views/Main/Split/SplitCreateSheet.swift
grep -Fq 'SplitDraftTests.swift' Settlr.xcodeproj/project.pbxproj

# Task 8 fix round 1: safe flash, navigable scanner stages, and privacy-safe
# acceptance of meaningful on-device rows.
grep -Fq 'flashEnabled' Settlr/Views/Main/Split/ReceiptCaptureView.swift
grep -Fq 'func setTorch(enabled:' Settlr/Views/Main/Split/ReceiptCaptureView.swift
grep -Fq 'NavigationStack' Settlr/Views/Main/Split/SplitScanFlow.swift
grep -Fq 'testAutomaticUsesMeaningfulUnverifiedOnDeviceRowsWithoutCallingServer' SettlrTests/ParserPreferenceTests.swift
grep -Fq 'testExplicitOnDeviceUsesMeaningfulUnverifiedRowsWithoutCallingServer' SettlrTests/ParserPreferenceTests.swift
grep -Fq 'hasUsableRows(result)' Settlr/Views/Main/Split/ReceiptReconciler.swift

# Task 8 fix round 2: manual flow origin and total tracking survive navigation.
grep -Fq 'struct SplitScanFlowMetadata' Settlr/Views/Main/Split/SplitDraft.swift
grep -Fq 'flowOrigin = .manual' Settlr/Views/Main/Split/SplitScanFlow.swift
grep -Fq 'initialTotalEdited' Settlr/Views/Main/Split/SplitCreateSheet.swift
grep -Fq 'testManualFlowOriginDoesNotOfferReviewBack' SettlrTests/SplitDraftTests.swift
grep -Fq 'testDerivedTotalRestorationKeepsTrackingItemTotals' SettlrTests/SplitDraftTests.swift
grep -Fq 'enum SplitScanFlowOrigin: Equatable' Settlr/Views/Main/Split/SplitDraft.swift

# Task 7 fix round 1: shared CardsVM ownership, gated overflow, and retained
# data recovery after refresh failures.
grep -Fq 'CardsView(workspaceId: workspaceId, vm: cardsVM)' Settlr/Views/Main/CardsRootView.swift
grep -Fq 'onCardMutated' Settlr/Views/Main/CardsView.swift
grep -Fq 'if canUsePayments {' Settlr/Views/Main/CardsRootView.swift
grep -Fq 'Showing saved card data. Refresh failed.' Settlr/Views/Main/CardsRootView.swift
grep -Fq 'Showing saved payment status. Refresh failed.' Settlr/Views/Main/CardsRootView.swift
grep -Fq 'SignalRefreshWarning' Settlr/Views/Main/CardsView.swift
grep -Fq 'SignalRefreshWarning' Settlr/Views/Main/CardPaymentsView.swift
grep -Fq 'refreshAfterCardMutation()' Settlr/Views/Main/CardsRootView.swift
grep -Fq 'guard isCurrentWorkspace else { throw CancellationError() }' Settlr/Views/Main/CardsRootView.swift

# Task 7 fix round 2: retained card content and injected VM ownership.
grep -Fq 'else if let err = vm.errorMessage, vm.cards.isEmpty' Settlr/Views/Main/CardsView.swift
grep -Fq 'private let ownsViewModel: Bool' Settlr/Views/Main/CardsView.swift
grep -Fq 'guard ownsViewModel else { return }' Settlr/Views/Main/CardsView.swift

# Final whole-branch fix wave: these are wiring guards only. The XCTest cases
# and standalone harnesses own the accounting and ordering behavior.
if grep -Fq 'id: "split:\(split.id)"' Settlr/Models/ActivityEvent.swift; then
    echo "Activity must not synthesize ledger money from a split summary." >&2
    exit 1
fi
grep -Fq 'testClosedSplitWithoutLoadedExpenseDoesNotFabricateLedgerMoney' SettlrTests/ActivityEventTests.swift
grep -Fq 'savingsTargetAmountText(for: account?.targetAmountCents)' Settlr/Views/Main/Savings/SavingsAccountsSheet.swift
grep -Fq 'testFlexibleAccountKeepsGoalFieldsNil' SettlrTests/SavingsGoalTests.swift
grep -Fq 'struct BillSplitDetailResponseGate' Settlr/Models/BillSplit.swift
grep -Fq 'detailResponseGate.beginLoad()' Settlr/ViewModels/BillSplitVM.swift
grep -Fq 'detailResponseGate.beginMutation()' Settlr/ViewModels/BillSplitVM.swift
grep -Fq 'detailResponseGate.commitMutation' Settlr/ViewModels/BillSplitVM.swift
grep -Fq 'testOlderDetailLoadCannotOverwriteNewerMutation' SettlrTests/SplitPaymentMethodTests.swift
grep -Fq 'launcherTask?.cancel()' Settlr/Views/Main/MainTabView.swift
grep -Fq 'launcherContextIsValid' Settlr/Views/Main/MainTabView.swift
grep -Fq 'guardedPresentation' Settlr/Views/Main/MainTabView.swift
grep -Fq 'categoriesPresentation' Settlr/Views/Main/MainTabView.swift
grep -Fq 'splitScanPresentation' Settlr/Views/Main/MainTabView.swift
grep -Fq 'splitListPresentation' Settlr/Views/Main/MainTabView.swift
grep -Fq 'light: 0x7A817B' Settlr/Views/Components/DesignSystem.swift
grep -Fq 'dark: 0x6F7578' Settlr/Views/Components/DesignSystem.swift

for contrast_view in \
  Settlr/Views/Components/FormControls.swift \
  Settlr/Views/Main/Savings/SavingsView.swift \
  Settlr/Views/Main/Savings/SavingsAccountsSheet.swift \
  Settlr/Views/Main/Savings/SavingsRecurringSheet.swift \
  Settlr/Views/Main/Income/IncomeRecurringSheet.swift \
  Settlr/Views/Main/Split/SplitCreateSheet.swift \
  Settlr/Views/Main/Split/ReceiptCaptureView.swift \
  Settlr/Views/Main/Split/SplitListView.swift; do
  grep -Fq 'Theme.buttonInk' "$contrast_view"
done

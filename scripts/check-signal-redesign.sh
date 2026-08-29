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
grep -Fq '@State private var showCategories = false' Settlr/Views/Main/MainTabView.swift
grep -Fq '.sheet(isPresented: $showCategories)' Settlr/Views/Main/MainTabView.swift
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

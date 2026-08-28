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

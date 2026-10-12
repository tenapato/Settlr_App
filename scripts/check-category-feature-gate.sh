#!/bin/sh
set -eu

# Focused, executable source regression guard for the category-gated form
# boundary. The full Swift/XCTest target cannot run in this environment because
# it requires Xcode, so this keeps the exact call-site contract executable.
main_tab="Settlr/Views/Main/MainTabView.swift"
activity="Settlr/Views/Main/Activity/ActivityView.swift"
expenses_vm="Settlr/ViewModels/ExpensesVM.swift"
income_vm="Settlr/ViewModels/IncomeVM.swift"

if ! rg -U -q 'guard categoriesEnabled else \{\n[[:space:]]+categories = \[\]\n[[:space:]]+return\n[[:space:]]+\}' "$expenses_vm"; then
  echo "ExpensesVM.loadCategories must skip the endpoint when categories are disabled." >&2
  exit 1
fi

if ! rg -U -q 'guard categoriesEnabled else \{\n[[:space:]]+categories = \[\]\n[[:space:]]+return\n[[:space:]]+\}' "$income_vm"; then
  echo "IncomeVM.loadCategories must skip the endpoint when categories are disabled." >&2
  exit 1
fi

if ! rg -U -q 'if launcherContextIsValid\(workspaceId: workspaceId, userId: userId, feature: \.categories\) \{\n[[:space:]]+await expensesVM\.loadCategories\(workspaceId: workspaceId, categoriesEnabled: true\)\n[[:space:]]+\}' "$main_tab"; then
  echo "Expense quick action must gate category loading at its delayed boundary." >&2
  exit 1
fi

if ! rg -U -q 'if launcherContextIsValid\(workspaceId: workspaceId, userId: userId, feature: \.categories\) \{\n[[:space:]]+await incomeVM\.loadCategories\(workspaceId: workspaceId, categoriesEnabled: true\)\n[[:space:]]+\}' "$main_tab"; then
  echo "Income quick action must gate category loading at its delayed boundary." >&2
  exit 1
fi

if ! rg -U -q 'guard appState\.activeWorkspace\?\.id == workspaceId,\n[[:space:]]+appState\.currentUser\?\.has\(\.categories\) == true else \{ return \}\n[[:space:]]+await expensesVM\.loadCategories\(workspaceId: workspaceId, categoriesEnabled: true\)' "$activity"; then
  echo "Activity expense form must gate category loading at its delayed boundary." >&2
  exit 1
fi

if ! rg -U -q 'guard appState\.activeWorkspace\?\.id == workspaceId,\n[[:space:]]+appState\.currentUser\?\.has\(\.categories\) == true else \{ return \}\n[[:space:]]+await incomeVM\.loadCategories\(workspaceId: workspaceId, categoriesEnabled: true\)' "$activity"; then
  echo "Activity income form must gate category loading at its delayed boundary." >&2
  exit 1
fi

if ! rg -U -q 'categories: appState\.currentUser\?\.has\(\.categories\) == true \? expensesVM\.categories : \[\]' "$main_tab" ||
   ! rg -U -q 'categories: user\?\.has\(\.categories\) == true\n[[:space:]]+\? \(vm\.categories\.isEmpty \? expensesVM\.categories : vm\.categories\)\n[[:space:]]+: \[\]' "$activity"; then
  echo "Expense forms must receive an empty category list while Categories is disabled." >&2
  exit 1
fi

if ! rg -U -q 'categories: appState\.currentUser\?\.has\(\.categories\) == true \? incomeVM\.categories : \[\]' "$main_tab" ||
   ! rg -U -q 'categories: user\?\.has\(\.categories\) == true\n[[:space:]]+\? \(vm\.categories\.isEmpty \? incomeVM\.categories : vm\.categories\)\n[[:space:]]+: \[\]' "$activity"; then
  echo "Income forms must receive an empty category list while Categories is disabled." >&2
  exit 1
fi

echo "Category feature-gate regression check passed."

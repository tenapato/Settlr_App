#!/bin/sh
set -eu

# Focused, executable source regression guard for scanner-created result
# ownership. The SwiftUI target cannot run in this environment without
# Xcode/XCTest, so this checks the exact initializer and capability boundaries.
scan_flow="Settlr/Views/Main/Split/SplitScanFlow.swift"
result_view="Settlr/Views/Main/Split/SplitResultView.swift"
pass_around="Settlr/Views/Main/Split/SplitPassAroundView.swift"
vm="Settlr/ViewModels/BillSplitVM.swift"

if ! rg -U -q 'SplitResultView\(\n[[:space:]]+split: resultSplit,\n[[:space:]]+workspaceId: workspaceId,\n[[:space:]]+splitId: resultSplit\.id,\n[[:space:]]+vm: vm,\n[[:space:]]+onFinish:' "$scan_flow"; then
  echo "Scanner-created results must receive workspaceId, split ID, and the existing VM." >&2
  exit 1
fi

if ! rg -U -q 'func showsSettlementControls\(isOpen: Bool, hasOwnerContext: Bool\) -> Bool \{\n[[:space:]]+hasOwnerContext && !isOpen && payerMode == \.organizerPaid\n[[:space:]]+\}' "$result_view"; then
  echo "Settlement controls must remain gated to closed organizer-paid owner results." >&2
  exit 1
fi

if ! rg -q 'currentSplit\.isOpen' "$result_view" ||
   ! rg -q 'currentSplit\.payerMode == \.organizerPaid' "$result_view"; then
  echo "Open organizer-paid results must retain the claiming gate." >&2
  exit 1
fi

if ! rg -U -q '(?s)private var currentSplit: BillSplit \{.*vm\.detail.*detail\.id == splitId' "$result_view"; then
  echo "Result mutations must render the server-returned split through vm.detail." >&2
  exit 1
fi

if ! rg -U -q 'guard detailResponseGate\.commitMutation\(mutation\) else \{ return false \}\n[[:space:]]+detail = response\.split' "$vm"; then
  echo "BillSplitVM mutations must adopt the response split into detail." >&2
  exit 1
fi

if ! rg -q 'SplitResultView\(split: current, onFinish:' "$pass_around"; then
  echo "Pass-around results must remain presentation-only." >&2
  exit 1
fi

if ! rg -U -q 'else if queuedResult \{\n[[:space:]]+queuedResultView' "$scan_flow"; then
  echo "Queued offline results must remain presentation-only." >&2
  exit 1
fi

if ! rg -U -q 'VStack\(spacing: 10\) \{(?s).*Text\("Continue to split"\)(?s).*foregroundStyle\(Theme\.buttonInk\)(?s).*Label\("Retake photo", systemImage: "camera\.rotate"\)(?s).*foregroundStyle\(Theme\.ink\)(?s).*strokeBorder\(Theme\.line, lineWidth: 1\)' "$scan_flow"; then
  echo "Scanner review actions must use the approved stacked, high-contrast hierarchy." >&2
  exit 1
fi

echo "Scanner result settlement regression check passed."

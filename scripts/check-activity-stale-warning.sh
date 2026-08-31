#!/bin/sh
set -eu

# Executable source guard for Activity's partial-refresh presentation. The
# SwiftUI target cannot run in this environment without Xcode/XCTest, so keep
# the exact retained-data warning contract executable at the source boundary.
activity="Settlr/Views/Main/Activity/ActivityView.swift"

timeline_content=$(sed -n '/private var timelineContent: some View {/,/^    private var attentionSection:/p' "$activity")

if [ "$(printf '%s\n' "$activity" | wc -l | tr -d ' ')" -ne 1 ]; then
  echo "Activity source path must be singular." >&2
  exit 1
fi

if [ "$(printf '%s\n' "$timeline_content" | grep -Fc 'SignalRefreshWarning')" -ne 1 ]; then
  echo "Activity timeline must render exactly one retained-data refresh warning." >&2
  exit 1
fi

if ! printf '%s\n' "$timeline_content" | grep -Fq 'if let error = vm.errorMessage {'; then
  echo "Activity timeline warning must be driven by the underlying error message." >&2
  exit 1
fi

if ! printf '%s\n' "$timeline_content" | grep -Fq 'Saved Activity data remains visible but may be out of date. Refresh failed: \(error)'; then
  echo "Activity warning must disclose retained data, staleness, and the underlying error." >&2
  exit 1
fi

if ! printf '%s\n' "$timeline_content" | rg -U -q 'await vm\.load\(\n[[:space:]]+workspaceId: workspaceId,\n[[:space:]]+user: user,\n[[:space:]]+refreshSession: \{ await appState\.refreshSession\(\) \}\n[[:space:]]+\)'; then
  echo "Activity warning Retry must use the feature-aware load with session refresh." >&2
  exit 1
fi

if ! grep -Fq '.accessibilityLabel(message)' Settlr/Views/Main/CardsRootView.swift; then
  echo "SignalRefreshWarning must expose its full message accessibly." >&2
  exit 1
fi

echo "Activity retained-data warning regression check passed."

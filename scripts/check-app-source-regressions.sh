#!/bin/sh
set -eu

detail="Settlr/Views/Main/Split/SplitDetailView.swift"
plist="Settlr/Info.plist"

if ! rg -U -q 'private func eachOwnSummary\(_ split: BillSplit\) -> some View \{\n[[:space:]]+let presentation = split\.accountingPresentation\n[[:space:]]+return VStack' "$detail"; then
  echo "SplitDetailView.eachOwnSummary must explicitly return its VStack after local declarations." >&2
  exit 1
fi

if rg -q 'let organizerId = split\.organizer\?\.id|let mine = Set\(split\.organizer\?\.claimedItemIds' "$detail"; then
  echo "SplitDetailView.itemsSection still contains unused organizer claim locals." >&2
  exit 1
fi

if /usr/libexec/PlistBuddy -c 'Print :UIDeviceFamily' "$plist" >/dev/null 2>&1; then
  echo "Info.plist must not duplicate TARGETED_DEVICE_FAMILY with UIDeviceFamily." >&2
  exit 1
fi

echo "App source regression checks passed."

#!/bin/sh
set -eu

detail="Settlr/Views/Main/Split/SplitDetailView.swift"
plist="Settlr/Info.plist"
api_client="Settlr/Network/APIClient.swift"
receipt_capture="Settlr/Views/Main/Split/ReceiptCaptureView.swift"
bill_split="Settlr/Models/BillSplit.swift"
settings="Settlr/Views/Main/Settings/SettingsView.swift"
photo_upload="Settlr/Network/ReceiptPhotoUpload.swift"
router="Settlr/Views/Main/Split/ReceiptReconciler.swift"
scan_vm="Settlr/ViewModels/BillSplitVM.swift"
scan_flow="Settlr/Views/Main/Split/SplitScanFlow.swift"
create_sheet="Settlr/Views/Main/Split/SplitCreateSheet.swift"

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

if ! rg -U -q 'final class APIClient \{\n[[:space:]]+@MainActor\n[[:space:]]+static let shared = APIClient\(\)' "$api_client"; then
  echo "APIClient.shared must be main-actor isolated with its initializer." >&2
  exit 1
fi

if ! rg -q 'final class CameraController: NSObject, @unchecked Sendable' "$receipt_capture"; then
  echo "CameraController must document its manually synchronized Sendable boundary." >&2
  exit 1
fi

if [ "$(rg -c 'return switch (self|parser)' "$bill_split")" -lt 3 ]; then
  echo "Receipt parser labels must explicitly return their switch expressions." >&2
  exit 1
fi

if ! rg -q 'case automatic, onDevice, server, serverPhoto' "$bill_split" ||
   ! rg -q 'case serverPhoto = "server_photo"' "$bill_split" ||
   ! rg -q 'case requestedParser, fallback' "$bill_split"; then
  echo "Receipt photo preference and additive parser metadata must be represented in BillSplit models." >&2
  exit 1
fi

if ! rg -U -q 'var isExperimental: Bool \{.*self == \.serverPhoto.*\}' "$bill_split" ||
   ! rg -q 'Text\("Experimental"\)' "$settings" ||
   ! rg -U -q '(?s)VStack\(alignment: \.leading, spacing: 10\).*Picker\("Receipt parsing".*if receiptParser == ReceiptParserPreference\.serverPhoto\.rawValue.*Text\("Experimental"\).*if receiptParser == ReceiptParserPreference\.onDevice\.rawValue' "$settings"; then
    echo "Server-photo experimental chip regression" >&2
    exit 1
fi

if ! rg -q 'The receipt photo and recognized text are sent securely to the server for AI parsing\. The server does not store the photo\. If Save captures to Photos is enabled, a local copy is saved to your photo library\. The AI provider does not use it to train its models\.' "$settings"; then
  echo "Settings must disclose the exact server-photo privacy boundary." >&2
  exit 1
fi

if ! rg -U -q 'switch receipt\.parser \{\n[[:space:]]+case \.onDevice:\n[[:space:]]+return reconcile\(ReceiptPrices\.applyPrinted' "$router" ||
   ! rg -U -q 'case \.server, \.serverPhoto:\n[[:space:]]+return reconcile\(receipt\)' "$router"; then
  echo "Only on-device receipts may replace server prices with local OCR evidence." >&2
  exit 1
fi

if ! rg -q 'static let maxLongestEdge = 2048' "$photo_upload" ||
   ! rg -q 'static let jpegQuality: CGFloat = 0\.8' "$photo_upload" ||
   ! rg -q 'static let maxBytes = 6 \* 1024 \* 1024' "$photo_upload" ||
   ! rg -q 'name=\\"photo\\"; filename=\\"receipt\.jpg\\"' "$photo_upload" ||
   ! rg -q 'name=\\"text\\"' "$photo_upload"; then
  echo "Receipt photo preparation and multipart fields must retain their bounded wire contract." >&2
  exit 1
fi

if ! rg -q 'func uploadReceiptPhoto<Response: Decodable>' "$api_client" ||
   ! rg -q 'multipart/form-data; boundary=' "$api_client" ||
   ! rg -q 'forHTTPHeaderField: "Content-Length"' "$api_client"; then
  echo "APIClient must expose the bounded authenticated multipart upload transport." >&2
  exit 1
fi

if ! rg -q 'case \.serverPhoto:' "$router" ||
   ! rg -q 'typealias PhotoParser' "$router" ||
   ! rg -q 'serverPhoto:' "$scan_vm" ||
   ! rg -q 'ReceiptPhotoUpload\.prepare' "$router" ||
   ! rg -q 'scanReceipt\(workspaceId: workspaceId, text: text, image: image\)' "$scan_flow" ||
   ! rg -q 'scanReceipt\(workspaceId: workspaceId, text: text, image: image\)' "$create_sheet"; then
  echo "Photo parsing must be an explicit router branch and both scan entry points must pass the captured image." >&2
  exit 1
fi

if ! rg -q 'attemptText\(for parser: ReceiptParserKind\?' "$bill_split" ||
   ! rg -q 'requestedParser: ReceiptParserKind\?' "$bill_split" ||
   ! rg -q 'fallback: ReceiptParserKind\?' "$bill_split"; then
  echo "Receipt privacy copy must distinguish the in-flight photo attempt from a completed text fallback." >&2
  exit 1
fi

if ! rg -U -q 'let photo = try preparePhoto\(image\)\n[[:space:]]+onAttempt\?\(\.serverPhoto\)\n[[:space:]]+guard let raw = try await serverPhoto\(ocrText, photo\)' "$router"; then
  echo "The server-photo attempt legend must begin only after JPEG preparation and immediately before upload." >&2
  exit 1
fi

if ! rg -U -q 'do \{\n[[:space:]]+result = try await router\.parse\(text, preference: preference, image: image\).*\n[[:space:]]+\} catch \{\n[[:space:]]+receiptScanRouting\.clearPhotoAttemptAfterFailure\(\)\n[[:space:]]+throw error\n[[:space:]]+\}' "$scan_vm"; then
  echo "A failed published photo upload must clear only its in-flight attempt before rethrowing." >&2
  exit 1
fi

for recovery_view in "$scan_flow" "$create_sheet"; do
  if ! rg -q '@State private var photoRecovery = ReceiptPhotoRecovery\(\)' "$recovery_view" ||
     ! rg -q 'Button\("Retry photo"\)' "$recovery_view" ||
     ! rg -q 'Button\("On server \(text only\)"\)' "$recovery_view" ||
     ! rg -q 'Button\("Manual entry"\)' "$recovery_view"; then
    echo "Both scan entry points must retain transient photo recovery with retry, text-only, and manual actions." >&2
    exit 1
  fi
done

if rg -q 'UIImage|ReceiptPhotoRecovery' Settlr/Network/PendingSplitQueue.swift; then
  echo "Receipt images and photo recovery state must never enter the durable pending queue." >&2
  exit 1
fi

echo "App source regression checks passed."

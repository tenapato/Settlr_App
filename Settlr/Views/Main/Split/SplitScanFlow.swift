import SwiftUI

enum SplitScanStage {
    case capture, review, split, result
}

struct SplitPendingResultPresentation: Equatable {
    let title: String
    let reason: String?
    let supportingMessage: String
    let actionTitle: String
    let isWaiting: Bool

    init(entry: PendingSplit) {
        if let reason = entry.blockedReason {
            title = "Needs attention"
            self.reason = reason.message
            supportingMessage = "This split is saved on this phone. Open pending splits to try again or discard it."
            actionTitle = "View pending splits"
            isWaiting = false
        } else {
            title = "Waiting to upload"
            reason = nil
            supportingMessage = "This split is saved on this phone and will upload when you're back online."
            actionTitle = "Done"
            isWaiting = true
        }
    }
}

/// Everything the editor must retain while Review temporarily replaces it.
/// Keeping the queue identity beside the draft prevents a corrected save from
/// accidentally becoming a second durable operation.
struct SplitEditorContinuation {
    let draft: SplitDraft
    let totalEdited: Bool
    let blockedEntryID: UUID?
}

/// The `+ → Split a Bill` entry point.
///
/// Opens straight into the camera, because that is what splitting a bill starts
/// with — the receipt is in your hand and the table is waiting. Everything else
/// (typing items in, the list of past splits) is reachable from here, but the
/// scan is the default path rather than one option on a form.
struct SplitScanFlow: View {
    let workspaceId: String
    /// Called once the split is safely somewhere — on the server, or on the
    /// phone waiting to upload. Only the first case has a detail screen to open.
    let onSaved: (SplitSaveOutcome) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var vm = BillSplitVM()
    @State private var prefill: ScannedReceipt?
    @State private var stage: SplitScanStage = .capture
    @State private var showList = false
    @State private var busyMessage: String?
    @State private var busyImage: UIImage?
    @State private var errorMessage: String?
    @State private var photoRecovery = ReceiptPhotoRecovery()
    @State private var showPhotoRecovery = false
    /// Carried into the create sheet when the scan couldn't run — the user needs
    /// to know why the form is empty.
    @State private var notice: String?
    @State private var resultSplit: BillSplit?
    @State private var pendingResult: PendingSplit?
    @State private var editorContinuation: SplitEditorContinuation?
    @State private var flowOrigin: SplitScanFlowOrigin = .capturedReceipt

    private var flowMetadata: SplitScanFlowMetadata {
        SplitScanFlowMetadata(
            origin: flowOrigin,
            totalEdited: editorContinuation?.totalEdited ?? false
        )
    }

    var body: some View {
        NavigationStack {
            stageView
        }
            .confirmationDialog(
                "Photo parsing failed",
                isPresented: $showPhotoRecovery,
                titleVisibility: .visible
            ) {
                Button("Retry photo") { runRecovery(preference: .serverPhoto) }
                Button("On server (text only)") { runRecovery(preference: .server) }
                Button("Manual entry") { enterManually() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The captured photo is kept only in this scan session while you choose how to continue.")
            }
            .sheet(isPresented: $showList) {
                SplitListView(workspaceId: workspaceId)
            }
            .onDisappear { photoRecovery.clear() }
    }

    @ViewBuilder
    private var stageView: some View {
        switch stage {
        case .capture:
            ReceiptCaptureView(
                onCapture: handleCapture,
                onManualEntry: { enterManually() },
                onOpenSplits: { showList = true },
                busyMessage: busyMessage,
                busyImage: busyImage,
                busyPrivacyLegend: vm.scanPrivacyLegend,
                errorMessage: errorMessage
            )
        case .review:
            if let prefill {
                    ReceiptReviewView(
                        receipt: prefill,
                        onBack: { stage = .capture },
                        onRetake: resetCapture,
                        onContinue: { stage = .split }
                )
            } else {
                splitEditor
            }
        case .split:
            splitEditor
        case .result:
            resultView
        }
    }

    private var splitEditor: some View {
        SplitCreateSheet(
            workspaceId: workspaceId,
            vm: vm,
            prefill: prefill,
            notice: notice,
            initialDraft: editorContinuation?.draft,
            initialTotalEdited: editorContinuation?.totalEdited,
            initialBlockedEntryID: editorContinuation?.blockedEntryID,
            onBackToReview: flowMetadata.canReturnToReview ? { draft, totalEdited, blockedEntryID in
                editorContinuation = SplitEditorContinuation(
                    draft: draft,
                    totalEdited: totalEdited,
                    blockedEntryID: blockedEntryID
                )
                stage = .review
            } : nil,
            onCancelFlow: { dismiss() },
            dismissOnSave: false
        ) { outcome in
            switch outcome {
            case .created(let split):
                resultSplit = split
                pendingResult = nil
                editorContinuation = nil
                onSaved(outcome)
                stage = .result
            case .queued(let entry), .needsAttention(let entry):
                resultSplit = nil
                pendingResult = entry
                // SplitCreateSheet only forwards non-fixable needs-attention
                // outcomes; fixable ones stay in the editor with their ID.
                editorContinuation = nil
                onSaved(outcome)
                stage = .result
            case .rejected:
                // SplitCreateSheet keeps rejected requests inline so every
                // draft field remains available for correction.
                break
            }
        }
    }

    @ViewBuilder
    private var resultView: some View {
        if let resultSplit {
            SplitResultView(
                split: resultSplit,
                workspaceId: workspaceId,
                splitId: resultSplit.id,
                vm: vm,
                onFinish: { dismiss() }
            )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                }
        } else if let pendingResult {
            pendingResultView(pendingResult)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                }
        } else {
            splitEditor
        }
    }

    private func pendingResultView(_ entry: PendingSplit) -> some View {
        let presentation = SplitPendingResultPresentation(entry: entry)
        return ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 16) {
                Spacer()
                if presentation.isWaiting {
                    SettlrPulseLoadingView(message: presentation.title)
                } else {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundStyle(Theme.warning)
                    Text(presentation.title)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Theme.ink)
                    if let reason = presentation.reason {
                        Text(reason)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.expense)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 36)
                    }
                }
                Text(presentation.supportingMessage)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
                Spacer()
                Button(presentation.actionTitle) { dismiss() }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.buttonInk)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(16)
            }
        }
    }

    private func handleCapture(_ image: UIImage) {
        vm.beginReceiptScan()
        errorMessage = nil
        editorContinuation = nil
        flowOrigin = .capturedReceipt
        photoRecovery.clear()
        busyImage = image
        withAnimation(.easeOut(duration: 0.2)) { busyMessage = "Reading the receipt…" }
        Task {
            var recognizedText: String?
            defer {
                busyMessage = nil
                busyImage = nil
            }
            do {
                // OCR is CPU-bound; keep it off the main actor so the camera UI
                // stays responsive behind the overlay.
                let text = try await Task.detached(priority: .userInitiated) {
                    try ReceiptOCR.recognizeText(in: image)
                }.value
                recognizedText = text

                busyMessage = "Finding the items…"
                let parsed = try await vm.scanReceipt(workspaceId: workspaceId, text: text, image: image)
                photoRecovery.clear()
                prefill = parsed
                stage = .review
            } catch {
                if let recognizedText, vm.lastScanPreference == .serverPhoto {
                    retainPhotoRecovery(image: image, ocrText: recognizedText, error: error)
                } else if APIError.isOffline(error) {
                    // Text-only Automatic fallback has no photo recovery path.
                    notice = "No signal, so the items couldn't be read automatically — type them in."
                    prefill = nil
                    flowOrigin = .manual
                    stage = .split
                } else {
                    // OCR failed or a non-photo parser failed; another capture is
                    // the only retry that preserves the selected privacy mode.
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func retainPhotoRecovery(image: UIImage, ocrText: String, error: Error) {
        photoRecovery.retain(image: image, ocrText: ocrText)
        errorMessage = error.localizedDescription
        showPhotoRecovery = true
    }

    private func runRecovery(preference: ReceiptParserPreference) {
        guard let image = photoRecovery.image, let text = photoRecovery.ocrText else { return }
        vm.beginReceiptScan()
        errorMessage = nil
        busyImage = image
        busyMessage = "Finding the items…"
        Task {
            defer {
                busyMessage = nil
                busyImage = nil
            }
            do {
                let parsed = try await vm.scanReceipt(
                    workspaceId: workspaceId,
                    text: text,
                    image: preference == .serverPhoto ? image : nil,
                    preference: preference
                )
                photoRecovery.clear()
                prefill = parsed
                stage = .review
            } catch {
                errorMessage = error.localizedDescription
                showPhotoRecovery = true
            }
        }
    }

    private func enterManually() {
        vm.beginReceiptScan()
        photoRecovery.clear()
        errorMessage = nil
        notice = "Enter the receipt items manually."
        prefill = nil
        editorContinuation = nil
        flowOrigin = .manual
        stage = .split
    }

    private func resetCapture() {
        prefill = nil
        editorContinuation = nil
        flowOrigin = .capturedReceipt
        notice = nil
        errorMessage = nil
        busyMessage = nil
        busyImage = nil
        stage = .capture
    }
}

/// A read-only checkpoint between OCR and money-making. It keeps the parser's
/// uncertainty visible without making the user re-read the whole form.
private struct ReceiptReviewView: View {
    let receipt: ScannedReceipt
    let onBack: () -> Void
    let onRetake: () -> Void
    let onContinue: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var presentation: ReceiptReviewPresentation {
        ReceiptReviewPresentation(receipt: receipt)
    }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    progressHeader
                    amountHero
                    if !receipt.warnings.isEmpty { receiptWarnings }
                    itemsSection
                }
                .padding(16)
                .padding(.bottom, 168)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack {
                Spacer()
                VStack(spacing: 10) {
                    Button(action: onContinue) {
                        Text("Set up the split")
                            .font(.headline)
                            .foregroundStyle(Theme.buttonInk)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Theme.accent)
                            )
                    }
                    .buttonStyle(.plain)

                    Button(action: onRetake) {
                        Label("Retake photo", systemImage: "camera.rotate")
                            .font(.headline)
                            .foregroundStyle(Theme.ink)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Theme.surface2)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .strokeBorder(Theme.line, lineWidth: 1)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity)
                .padding(16)
                .background(.ultraThinMaterial)
            }
        }
        .navigationTitle("Review scan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Back", action: onBack)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Close") { dismiss() }
            }
        }
    }

    private var progressHeader: some View {
        HStack(spacing: 8) {
            progressStep("Scan", state: .complete)
            progressConnector(active: true)
            progressStep("Review", state: .current)
            progressConnector(active: false)
            progressStep("Set up split", state: .upcoming)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step 2 of 3, Review")
    }

    private enum ProgressState: Equatable {
        case complete, current, upcoming
    }

    private func progressStep(_ title: String, state: ProgressState) -> some View {
        HStack(spacing: 5) {
            Image(systemName: state == .complete ? "checkmark.circle.fill" : "circle.fill")
                .font(.system(size: state == .current ? 8 : 12, weight: .semibold))
            Text(title)
                .font(.system(size: 11, weight: state == .current ? .bold : .medium))
                .lineLimit(1)
        }
        .foregroundStyle(state == .upcoming ? Theme.faint : Theme.accentText)
    }

    private func progressConnector(active: Bool) -> some View {
        Rectangle()
            .fill(active ? Theme.accentText : Theme.line)
            .frame(maxWidth: .infinity, maxHeight: 1)
    }

    private var amountHero: some View {
        VStack(spacing: 10) {
            Text("SCANNED TOTAL")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(Theme.muted)

            Text("MXN")
                .font(.system(size: 13, weight: .semibold))
                .tracking(2)
                .foregroundStyle(Theme.faint)

            Text(formatSplitMoney(presentation.totalCents))
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.65)
                .lineLimit(1)
                .foregroundStyle(presentation.totalCents > 0 ? Theme.ink : Theme.warning)
                .accessibilityLabel("Scanned total, \(formatSplitMoney(presentation.totalCents))")

            Rectangle()
                .fill(presentation.totalCents > 0 ? Theme.line : Theme.warning)
                .frame(height: 1)

            Text(presentation.merchantName)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(presentation.merchantNeedsAttention ? Theme.warning : Theme.ink)

            Label(
                presentation.statusText,
                systemImage: presentation.needsAttention ? "exclamationmark.circle.fill" : "checkmark.circle.fill"
            )
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(presentation.needsAttention ? Theme.warning : Theme.accentText)
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
        .padding(.top, 4)
    }

    private var itemsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("SCANNED ITEMS")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(Theme.muted)
                .padding(.bottom, 8)

            if receipt.items.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "text.badge.xmark")
                        .foregroundStyle(Theme.warning)
                    Text("No items were found. You can add them during split setup.")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.muted)
                }
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .top) { Divider().overlay(Theme.line) }
                .overlay(alignment: .bottom) { Divider().overlay(Theme.line) }
            } else {
                ForEach(Array(receipt.items.enumerated()), id: \.offset) { index, item in
                    itemRow(item)
                    if index < receipt.items.count - 1 {
                        Divider().overlay(Theme.line)
                    }
                }
            }
        }
    }

    private func itemRow(_ item: ScannedReceiptItem) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(item.name.isEmpty ? "Unnamed item" : item.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(item.verification == .unverified ? Theme.warning : Theme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(formatSplitMoney(item.quantity * item.unitPriceCents))
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
            }
            HStack(spacing: 6) {
                Text("\(item.quantity) × \(formatSplitMoney(item.unitPriceCents))")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                if item.verification == .unverified {
                    Label("Check this item", systemImage: "exclamationmark.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.warning)
                }
            }
        }
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }

    private var receiptWarnings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("CHECK THE TOTAL", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(Theme.warning)
            ForEach(receipt.warnings, id: \.self) { warning in
                Text(warning)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.leading, 12)
        .padding(.vertical, 4)
        .overlay(alignment: .leading) {
            Rectangle().fill(Theme.warning).frame(width: 2)
        }
    }
}

import SwiftUI

enum SplitScanStage {
    case capture, review, split, result
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
    @State private var queuedResult = false
    @State private var flowDraft: SplitDraft?
    @State private var flowDraftTotalEdited = false
    @State private var flowOrigin: SplitScanFlowOrigin = .capturedReceipt

    private var flowMetadata: SplitScanFlowMetadata {
        SplitScanFlowMetadata(origin: flowOrigin, totalEdited: flowDraftTotalEdited)
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
            initialDraft: flowDraft,
            initialTotalEdited: flowDraft == nil ? nil : flowDraftTotalEdited,
            onBackToReview: flowMetadata.canReturnToReview ? { draft, totalEdited in
                flowDraft = draft
                flowDraftTotalEdited = totalEdited
                stage = .review
            } : nil,
            onCancelFlow: { dismiss() },
            dismissOnSave: false
        ) { outcome in
            switch outcome {
            case .created(let split):
                resultSplit = split
                queuedResult = false
                onSaved(outcome)
                stage = .result
            case .queued:
                queuedResult = true
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
            SplitResultView(split: resultSplit, onFinish: { dismiss() })
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                }
        } else if queuedResult {
            queuedResultView
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                }
        } else {
            splitEditor
        }
    }

    private var queuedResultView: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 16) {
                Spacer()
                SettlrPulseLoadingView(message: "Saved on this phone")
                Text("We'll upload this split when you're back online.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
                Spacer()
                Button("Done") { dismiss() }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.bg)
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
        flowDraft = nil
        flowDraftTotalEdited = false
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
        flowDraft = nil
        flowDraftTotalEdited = false
        flowOrigin = .manual
        stage = .split
    }

    private func resetCapture() {
        prefill = nil
        flowDraft = nil
        flowDraftTotalEdited = false
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

    private var confidence: String {
        receipt.items.contains { $0.verification == .unverified } || !receipt.warnings.isEmpty
            ? "Needs attention"
            : "High confidence"
    }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Review")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(Theme.ink)
                    Text("Check the scan before choosing how to split it.")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.muted)

                    reviewCard
                    itemsCard
                    if !receipt.warnings.isEmpty { warningsCard }
                }
                .padding(16)
                .padding(.bottom, 96)
            }
            VStack {
                Spacer()
                HStack(spacing: 10) {
                    Button("Retake", action: onRetake)
                        .buttonStyle(.bordered)
                        .tint(Theme.accent)
                    Button("Continue to split", action: onContinue)
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                }
                .font(.system(size: 14, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(16)
                .background(.ultraThinMaterial)
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Back", action: onBack)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Close") { dismiss() }
            }
        }
    }

    private var reviewCard: some View {
        VStack(spacing: 0) {
            reviewRow("Merchant", receipt.merchant ?? "Not found", attention: receipt.merchant == nil)
            Divider().overlay(Theme.line)
            reviewRow("Printed total", formatSplitMoney(receipt.totalCents), attention: receipt.totalCents <= 0)
            Divider().overlay(Theme.line)
            reviewRow("Date", Date().formatted(date: .abbreviated, time: .omitted))
            Divider().overlay(Theme.line)
            reviewRow("Payment method", "Choose in Split")
            Divider().overlay(Theme.line)
            reviewRow("Category", "Choose in Split")
            Divider().overlay(Theme.line)
            reviewRow("Parser confidence", confidence, attention: confidence != "High confidence")
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var itemsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Items")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.muted)
            ForEach(Array(receipt.items.enumerated()), id: \.offset) { _, item in
                HStack {
                    Text(item.name.isEmpty ? "Unnamed item" : item.name)
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Text(formatSplitMoney(item.quantity * item.unitPriceCents))
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundStyle(item.verification == .unverified ? Theme.warning : Theme.ink)
                }
                .padding(.vertical, 5)
            }
        }
        .padding(14)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var warningsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Check the scan", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.warning)
            ForEach(receipt.warnings, id: \.self) { warning in
                Text(warning).font(.system(size: 12)).foregroundStyle(Theme.muted)
            }
        }
        .padding(14)
        .background(Theme.warning.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func reviewRow(_ label: String, _ value: String, attention: Bool = false) -> some View {
        HStack {
            Text(label).font(.system(size: 13)).foregroundStyle(Theme.muted)
            Spacer(minLength: 10)
            Text(value).font(.system(size: 14, weight: .medium)).foregroundStyle(attention ? Theme.warning : Theme.ink)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}

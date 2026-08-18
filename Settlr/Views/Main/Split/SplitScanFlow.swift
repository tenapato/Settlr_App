import SwiftUI

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
    @State private var showCreate = false
    @State private var showList = false
    @State private var busyMessage: String?
    @State private var busyImage: UIImage?
    @State private var errorMessage: String?
    @State private var photoRecovery = ReceiptPhotoRecovery()
    @State private var showPhotoRecovery = false
    /// Carried into the create sheet when the scan couldn't run — the user needs
    /// to know why the form is empty.
    @State private var notice: String?

    var body: some View {
        ReceiptCaptureView(
            onCapture: handleCapture,
            onManualEntry: {
                enterManually()
            },
            onOpenSplits: { showList = true },
            busyMessage: busyMessage,
            busyImage: busyImage,
            busyPrivacyLegend: vm.scanPrivacyLegend,
            errorMessage: errorMessage
        )
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
        .sheet(isPresented: $showCreate) {
            SplitCreateSheet(workspaceId: workspaceId, vm: vm, prefill: prefill, notice: notice) { outcome in
                showCreate = false
                dismiss()
                onSaved(outcome)
            }
        }
        .sheet(isPresented: $showList) {
            SplitListView(workspaceId: workspaceId)
        }
        .onDisappear { photoRecovery.clear() }
    }

    private func handleCapture(_ image: UIImage) {
        vm.beginReceiptScan()
        errorMessage = nil
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
                showCreate = true
            } catch {
                if let recognizedText, vm.lastScanPreference == .serverPhoto {
                    retainPhotoRecovery(image: image, ocrText: recognizedText, error: error)
                } else if APIError.isOffline(error) {
                    // Text-only Automatic fallback has no photo recovery path.
                    notice = "No signal, so the items couldn't be read automatically — type them in."
                    prefill = nil
                    showCreate = true
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
                showCreate = true
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
        showCreate = true
    }
}

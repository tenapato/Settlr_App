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
    /// Carried into the create sheet when the scan couldn't run — the user needs
    /// to know why the form is empty.
    @State private var notice: String?

    var body: some View {
        ReceiptCaptureView(
            onCapture: handleCapture,
            onManualEntry: {
                prefill = nil
                showCreate = true
            },
            onOpenSplits: { showList = true },
            busyMessage: busyMessage,
            busyImage: busyImage,
            errorMessage: errorMessage
        )
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
    }

    private func handleCapture(_ image: UIImage) {
        errorMessage = nil
        busyImage = image
        withAnimation(.easeOut(duration: 0.2)) { busyMessage = "Reading the receipt…" }
        Task {
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

                busyMessage = "Finding the items…"
                let parsed = try await vm.scanReceipt(workspaceId: workspaceId, text: text)
                prefill = parsed
                showCreate = true
            } catch let error where APIError.isOffline(error) {
                // Vision read the receipt fine; only the fallback parser needed
                // the network. Another photo would fail identically, so move on
                // to the form rather than parking the user on the camera.
                notice = "No signal, so the items couldn't be read automatically — type them in."
                prefill = nil
                showCreate = true
            } catch {
                // Stay on the camera so the obvious next move is another shot.
                errorMessage = error.localizedDescription
            }
        }
    }
}

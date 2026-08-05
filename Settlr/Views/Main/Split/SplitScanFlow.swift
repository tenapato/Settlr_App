import SwiftUI

/// The `+ → Split a Bill` entry point.
///
/// Opens straight into the camera, because that is what splitting a bill starts
/// with — the receipt is in your hand and the table is waiting. Everything else
/// (typing items in, the list of past splits) is reachable from here, but the
/// scan is the default path rather than one option on a form.
struct SplitScanFlow: View {
    let workspaceId: String
    /// Called after a split is created so the caller can open its detail screen.
    let onCreated: (BillSplit) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var vm = BillSplitVM()
    @State private var prefill: ScannedReceipt?
    @State private var showCreate = false
    @State private var showList = false
    @State private var busyMessage: String?
    @State private var busyImage: UIImage?
    @State private var errorMessage: String?

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
            SplitCreateSheet(workspaceId: workspaceId, vm: vm, prefill: prefill) { created in
                showCreate = false
                dismiss()
                onCreated(created)
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
            } catch {
                // Stay on the camera so the obvious next move is another shot.
                errorMessage = error.localizedDescription
            }
        }
    }
}

import Foundation
import Observation

/// Drives the organizer's split screens: the list, one open detail, and the
/// create flow. Every number shown comes back from the server — the app never
/// does share math of its own, so the app, the web link and the ledger can't
/// disagree about who owes what.
@Observable
final class BillSplitVM {
    var splits: [BillSplitSummary] = []
    var detail: BillSplit?
    var isLoading = false
    var isSaving = false
    var errorMessage: String?
    /// True once a list fetch has succeeded, so an empty `splits` can be told
    /// apart from "not loaded yet" before showing an empty state.
    var hasLoaded = false

    private let api = APIClient.shared

    // MARK: - List

    @MainActor
    func load(workspaceId: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let resp: BillSplitListResponse = try await api.fetch(Endpoints.billSplits(workspaceId))
            splits = resp.splits
            hasLoaded = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Detail

    /// - Parameter silent: for background polling — leaves the spinner and any
    ///   existing error alone so a blip while the screen is open doesn't flash
    ///   chrome at someone who is just watching claims arrive.
    @MainActor
    func loadDetail(workspaceId: String, splitId: String, silent: Bool = false) async {
        if !silent {
            isLoading = true
            errorMessage = nil
        }
        defer { if !silent { isLoading = false } }
        do {
            let resp: BillSplitResponse = try await api.fetch(Endpoints.billSplit(workspaceId, splitId))
            detail = resp.split
        } catch {
            if !silent { errorMessage = error.localizedDescription }
        }
    }

    /// Runs a mutation that returns the whole split, and adopts the result.
    /// Keeping every write on this path means the UI can never drift from the
    /// server's view of the claims.
    @MainActor
    private func mutate(_ block: () async throws -> BillSplitResponse) async -> Bool {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            detail = try await block().split
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @MainActor
    func toggleClaim(workspaceId: String, splitId: String, itemId: String, claimed: Bool) async {
        _ = await mutate {
            try await api.fetch(
                Endpoints.billSplitClaims(workspaceId, splitId),
                method: "POST",
                body: BillSplitClaimBody(itemId: itemId, claimed: claimed)
            )
        }
    }

    @MainActor
    func setStatus(workspaceId: String, splitId: String, status: String) async -> Bool {
        await mutate {
            try await api.fetch(
                Endpoints.billSplit(workspaceId, splitId),
                method: "PATCH",
                body: BillSplitStatusBody(status: status)
            )
        }
    }

    @MainActor
    func setSettled(
        workspaceId: String,
        splitId: String,
        participantId: String,
        settled: Bool
    ) async {
        _ = await mutate {
            try await api.fetch(
                Endpoints.billSplitSettle(workspaceId, splitId, participantId),
                method: settled ? "POST" : "DELETE"
            )
        }
    }

    @MainActor
    func removeParticipant(workspaceId: String, splitId: String, participantId: String) async {
        _ = await mutate {
            try await api.fetch(
                Endpoints.billSplitParticipant(workspaceId, splitId, participantId),
                method: "DELETE"
            )
        }
    }

    // MARK: - Create / delete

    @MainActor
    func create(workspaceId: String, body: CreateBillSplitBody) async -> BillSplit? {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let resp: BillSplitResponse = try await api.fetch(
                Endpoints.billSplits(workspaceId),
                method: "POST",
                body: body
            )
            detail = resp.split
            await load(workspaceId: workspaceId)
            return resp.split
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    @MainActor
    func delete(workspaceId: String, splitId: String) async -> Bool {
        errorMessage = nil
        do {
            try await api.send(Endpoints.billSplit(workspaceId, splitId), method: "DELETE")
            splits.removeAll { $0.id == splitId }
            if detail?.id == splitId { detail = nil }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - Receipt scanning

    /// Set once a scan runs, so the UI can say where the parsing happened.
    var lastScanWasOnDevice = false

    /// Structures OCR text into items.
    ///
    /// Prefers Apple's on-device model: it's faster, spends none of the user's
    /// monthly AI quota, and the receipt never leaves the phone. Falls back to
    /// the server whenever Apple Intelligence isn't available on this device —
    /// and also if it fails, because a working scan matters more than where it
    /// ran. Throws only when both routes fail.
    @MainActor
    func scanReceipt(workspaceId: String, text: String) async throws -> ScannedReceipt {
        do {
            if let onDevice = try await OnDeviceReceiptParser.parse(ocrText: text),
               !onDevice.items.isEmpty {
                lastScanWasOnDevice = true
                return onDevice
            }
        } catch {
            // Fall through to the server rather than failing the scan outright.
        }

        lastScanWasOnDevice = false
        return try await api.fetch(
            Endpoints.billSplitScanReceipt(workspaceId),
            method: "POST",
            body: ScanReceiptBody(text: text)
        )
    }
}

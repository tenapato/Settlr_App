import Foundation
import Observation

/// Drives the organizer's split screens: the list, one open detail, and the
/// create flow. Every number shown comes back from the server — the app never
/// does share math of its own, so the app, the web link and the ledger can't
/// disagree about who owes what.
@Observable
final class BillSplitVM {
    enum ClaimMutationResult: Equatable {
        case saved
        case capacityChanged
        case failed
    }

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

    /// Sends desired state, not a boolean toggle. `participantId` nil writes the
    /// organizer's row, which is the server default.
    @MainActor
    func setClaimQuantity(
        workspaceId: String,
        splitId: String,
        itemId: String,
        quantity: Int,
        participantId: String? = nil
    ) async -> ClaimMutationResult {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let response: BillSplitResponse = try await api.fetch(
                Endpoints.billSplitClaims(workspaceId, splitId),
                method: "POST",
                body: BillSplitClaimBody(
                    itemId: itemId,
                    quantity: max(0, quantity),
                    participantId: participantId
                )
            )
            detail = response.split
            return .saved
        } catch let error as APIServerError where error.status == 409 {
            // A 409 response carries a fresh DTO, but APIClient deliberately
            // exposes server errors uniformly. Fetch it again so every caller
            // adopts current capacity before showing the conflict.
            let response: BillSplitResponse? = try? await api.fetch(
                Endpoints.billSplit(workspaceId, splitId)
            )
            if let response { detail = response.split }
            errorMessage = error.code == "claim_capacity_changed"
                ? "Someone else just claimed the remaining quantity. The item has been refreshed."
                : error.localizedDescription
            return error.code == "claim_capacity_changed" ? .capacityChanged : .failed
        } catch {
            errorMessage = error.localizedDescription
            return .failed
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
    private func mutateParticipant(
        workspaceId: String,
        splitId: String,
        endpoint: String,
        method: String,
        body: (any Encodable)? = nil
    ) async -> Bool {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let response: BillSplitResponse = try await api.fetch(
                endpoint,
                method: method,
                body: body
            )
            detail = response.split
            return true
        } catch let error as APIServerError where error.status == 409 {
            let response: BillSplitResponse? = try? await api.fetch(
                Endpoints.billSplit(workspaceId, splitId)
            )
            if let response { detail = response.split }
            errorMessage = "The table changed on another screen. It has been refreshed; try again."
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @MainActor
    func addParticipant(workspaceId: String, splitId: String, name: String) async -> Bool {
        await mutateParticipant(
            workspaceId: workspaceId,
            splitId: splitId,
            endpoint: Endpoints.billSplitParticipants(workspaceId, splitId),
            method: "POST",
            body: BillSplitParticipantNameBody(name: name)
        )
    }

    @MainActor
    func renameParticipant(
        workspaceId: String,
        splitId: String,
        participantId: String,
        name: String
    ) async -> Bool {
        await mutateParticipant(
            workspaceId: workspaceId,
            splitId: splitId,
            endpoint: Endpoints.billSplitParticipant(workspaceId, splitId, participantId),
            method: "PATCH",
            body: BillSplitParticipantNameBody(name: name)
        )
    }

    @MainActor
    @discardableResult
    func removeParticipant(workspaceId: String, splitId: String, participantId: String) async -> Bool {
        await mutateParticipant(
            workspaceId: workspaceId,
            splitId: splitId,
            endpoint: Endpoints.billSplitParticipant(workspaceId, splitId, participantId),
            method: "DELETE"
        )
    }

    // MARK: - Create / delete

    /// Creation does not live here.
    ///
    /// A split is composed at a table, where the connection is worst, so it is
    /// written to disk first and uploaded by `PendingSplitQueue` — which owns
    /// the retry, the idempotency key and the "not yet" state that a view model
    /// tied to one screen's lifetime cannot.

    /// Complete replacement edit. The returned DTO is adopted before this
    /// returns so the detail screen never briefly renders stale money or claims.
    @MainActor
    func updateDraft(
        workspaceId: String,
        splitId: String,
        body: EditBillSplitBody
    ) async -> Bool {
        await mutate {
            try await api.fetch(
                Endpoints.billSplitDraft(workspaceId, splitId),
                method: "PUT",
                body: body
            )
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

    /// Kept only for this view model's editor session so a failed parse can be
    /// retried without running Vision again or retaining the receipt image.
    var lastReceiptOCRText: String?
    var lastScanParser: ReceiptParserKind?
    var lastScanNeedsReview = false

    /// Compatibility for existing scan UI while callers move to parser metadata.
    var lastScanWasOnDevice: Bool { lastScanParser == .onDevice }

    /// Structures OCR text into items.
    ///
    /// Automatic prefers Apple's on-device model and falls back to the server.
    /// Explicit On-device and On-server preferences use only the selected path.
    ///
    /// Both routes go through `ReceiptReconciler` against the same OCR text, so
    /// whichever model read the receipt, every price comes off the receipt
    /// itself and the draft the organizer sees adds up the same way.
    @MainActor
    func scanReceipt(workspaceId: String, text: String) async throws -> ScannedReceipt {
        lastReceiptOCRText = text
        lastScanParser = nil
        lastScanNeedsReview = false
        let storedPreference = UserDefaults.standard.string(
            forKey: ReceiptParserPreference.storageKey
        )
        let preference = storedPreference.flatMap(ReceiptParserPreference.init(rawValue:)) ?? .automatic
        let router = ReceiptParserRouter(
            onDevice: { ocrText in
                try await OnDeviceReceiptParser.parse(ocrText: ocrText)
            },
            server: { [api] ocrText in
                let result: ScannedReceipt = try await api.fetch(
                    Endpoints.billSplitScanReceipt(workspaceId),
                    method: "POST",
                    body: ScanReceiptBody(text: ocrText)
                )
                return result
            }
        )
        let result = try await router.parse(text, preference: preference)
        lastScanParser = result.parser
        lastScanNeedsReview = !result.warnings.isEmpty
            || result.items.contains { $0.verification == .unverified }
        return result
    }
}

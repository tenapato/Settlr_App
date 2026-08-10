import Foundation
import Network
import Observation

/// Splits composed with no signal, waiting to reach the server.
///
/// Bill splitting happens at a restaurant table, which is where signal is
/// worst. Before this, the whole flow ended there: the POST failed, the sheet
/// showed red text, and the receipt was already back in the waiter's hand. The
/// scan half never needed the network — Vision and Apple Intelligence both run
/// on the phone — so the only thing standing between a user and a finished
/// split was one request.
///
/// The rule the whole file turns on: **an entry is only ever deleted after a
/// success has been decoded.** Everything else — the crash recovery, the
/// classifier, the idempotency key — exists to make that rule survivable.

// MARK: - Entry

struct PendingSplit: Codable, Identifiable {
    /// Why an entry stopped trying, in the user's terms. Each case is a
    /// different answer to "can I do anything about this?", which is the only
    /// question the pending list has to answer.
    enum Reason: Codable, Equatable {
        /// The monthly cap. Nothing to fix; it will work next month.
        case quotaReached(String)
        /// An admin turned bill splitting off for this account.
        case featureDisabled(String)
        /// The server refused this payload. The user can edit and resend.
        case rejected(String)
        /// The workspace is gone, or access to it was revoked.
        case workspaceUnavailable(String)
        /// Tried enough times against a server that kept failing.
        case serverUnavailable(String)

        var message: String {
            switch self {
            case .quotaReached(let m), .featureDisabled(let m), .rejected(let m),
                 .workspaceUnavailable(let m), .serverUnavailable(let m):
                return m
            }
        }

        /// Whether editing the split could plausibly make it upload.
        var isFixableByEditing: Bool {
            if case .rejected = self { return true }
            return false
        }
    }

    enum State: Codable, Equatable {
        case queued
        case uploading
        case needsAttention(Reason)
    }

    let id: UUID
    /// Stamped once, at composition, and never regenerated. Regenerating it on
    /// retry would defeat the entire server-side replay mechanism.
    let idempotencyKey: String
    /// Whose split this is. Entries are filtered by this on every flush, so a
    /// second account signing in on the same phone can never upload the first
    /// account's dinner into their own workspace.
    let userId: String
    let workspaceId: String
    var body: CreateBillSplitBody
    let createdAt: Date
    var state: State = .queued
    var attemptCount: Int = 0
    var nextAttemptAt: Date?
    var lastErrorMessage: String?

    var isWaiting: Bool {
        switch state {
        case .queued, .uploading: return true
        case .needsAttention: return false
        }
    }

    var blockedReason: Reason? {
        if case .needsAttention(let reason) = state { return reason }
        return nil
    }
}

// MARK: - Classification

/// What to do about one failed attempt. Split out as a pure function because it
/// is the highest-risk logic here and the only part that can be tested without
/// a device, a server, or a network.
enum SyncVerdict: Equatable {
    /// No usable connection. Not a failure — the split simply hasn't uploaded
    /// yet, so it costs no attempt and shows the user no error.
    case notYet
    /// Might work later, unchanged. Counts against the attempt budget.
    case retryLater
    /// Will never work unchanged; stop and tell the user.
    case giveUp(PendingSplit.Reason)
    /// The session died. Nothing is wrong with the entry, so hold the whole
    /// queue rather than blaming any single split.
    case waitForSignIn
}

enum SplitSyncPolicy {
    static let maxAttempts = 6

    static func classify(_ error: Error) -> SyncVerdict {
        if APIError.isOffline(error) { return .notYet }

        if let apiError = error as? APIError {
            switch apiError {
            case .unauthorized: return .waitForSignIn
            // Same shape as a lost session: nothing about the split is wrong,
            // and access can come back the moment an admin reactivates them.
            // Burning attempts on it would discard work that is still valid.
            case .accountDeactivated: return .waitForSignIn
            // The split was created — we just couldn't read the answer. Retrying
            // is safe (the key replays it) and is the only way to learn its id.
            case .decoding: return .retryLater
            default: return .retryLater
            }
        }

        guard let server = error as? APIServerError else { return .retryLater }

        if server.status == 401 { return .waitForSignIn }
        if server.isRetryable { return .retryLater }
        if server.feature != nil {
            return .giveUp(.featureDisabled(server.message))
        }
        switch server.code {
        case "bill_split_quota": return .giveUp(.quotaReached(server.message))
        // Too many items or too many people: both are the user's to fix.
        case "bill_split_limit": return .giveUp(.rejected(server.message))
        default: break
        }
        if server.status == 404 || server.status == 403 {
            return .giveUp(.workspaceUnavailable(server.message))
        }
        return .giveUp(.rejected(server.message))
    }

    /// 2s, 4s, 8s… capped at five minutes, jittered so a queue that drained
    /// into the same failure doesn't retry in lockstep.
    static func backoff(forAttempt attempt: Int, jitter: Double = Double.random(in: 0.8...1.2))
        -> TimeInterval
    {
        let base = min(pow(2.0, Double(max(1, attempt))), 300)
        return base * jitter
    }
}

// MARK: - Storage

/// The queue on disk.
///
/// A file rather than `UserDefaults`, which is where this codebase keeps its
/// other small things: an entry holds a whole receipt — merchant, every line and
/// every price — and a plist gets no per-file protection and is backed up by
/// default. A file can have both.
enum PendingSplitStore {
    private static var directory: URL {
        URL.applicationSupportDirectory.appendingPathComponent("Settlr", isDirectory: true)
    }

    private static var fileURL: URL {
        directory.appendingPathComponent("pending-splits.json")
    }

    static func load() -> [PendingSplit] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([PendingSplit].self, from: data)) ?? []
    }

    static func save(_ entries: [PendingSplit]) {
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(entries)
            // `.completeUnlessOpen` rather than `.complete`: every flush is
            // foreground-driven, but a write can still be in progress as the
            // app is backgrounded and the device locks.
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUnlessOpen])
            excludeFromBackup()
        } catch {
            // Nothing useful to do — and nothing to log, because the payload is
            // the user's receipt.
        }
    }

    /// A restored backup would resurrect weeks-old drafts on a new device.
    /// Harmless thanks to the idempotency key, but confusing.
    private static func excludeFromBackup() {
        var url = fileURL
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }
}

// MARK: - Connectivity

/// Whether the phone currently has a usable path off the device.
///
/// Advisory only. `NWPathMonitor` reports `.satisfied` behind captive portals
/// and mid-handoff, so this decides *when to try*, never *whether something
/// failed* — `APIError.offline` is the authority on that.
@MainActor
@Observable
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    private(set) var isOnline = true
    /// Fired on the false→true edge only. Level-triggering would fire on every
    /// path update — Wi-Fi to cellular, a DNS change — and cause flush storms.
    var onBecameReachable: (@MainActor () -> Void)?

    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let reachable = path.status == .satisfied
            Task { @MainActor in
                guard let self else { return }
                let wasOnline = self.isOnline
                self.isOnline = reachable
                if !wasOnline && reachable { self.onBecameReachable?() }
            }
        }
        monitor.start(queue: DispatchQueue(label: "settlr.network-monitor"))
    }
}

// MARK: - Queue

/// What happened when a composed split was handed to the queue.
enum SplitSaveOutcome {
    /// It reached the server. The caller can open it.
    case created(BillSplit)
    /// It is on disk and will upload itself. There is no split to open yet.
    case queued(PendingSplit)
    /// The server refused the payload. The sheet stays open so it can be fixed
    /// — byte-for-byte the behaviour before any of this existed.
    case rejected(String)
}

@MainActor
@Observable
final class PendingSplitQueue {
    static let shared = PendingSplitQueue()

    private(set) var entries: [PendingSplit] = []
    /// Set when a flush hit a 401. Nothing is wrong with the entries; they just
    /// can't move until somebody signs in again.
    private(set) var isWaitingForSignIn = false

    private let api = APIClient.shared
    private var inFlight: Task<Void, Never>?
    private var rerunRequested = false

    /// Bounded so a long offline stretch can't build a queue that blows through
    /// the monthly cap the moment it reconnects.
    private let maxEntries = 25

    private init() {
        entries = PendingSplitStore.load().map { entry in
            // An entry caught mid-upload by a crash or a force-quit. The request
            // may well have landed; the idempotency key makes finding out safe.
            guard entry.state == .uploading else { return entry }
            var recovered = entry
            recovered.state = .queued
            recovered.attemptCount += 1
            return recovered
        }
        if !entries.isEmpty { persist() }
    }

    // MARK: Reading

    func entries(userId: String, workspaceId: String? = nil) -> [PendingSplit] {
        entries
            .filter { $0.userId == userId }
            .filter { workspaceId == nil || $0.workspaceId == workspaceId }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func pendingCount(userId: String) -> Int {
        entries.count { $0.userId == userId }
    }

    // MARK: Composing

    func makeEntry(userId: String, workspaceId: String, body: CreateBillSplitBody) -> PendingSplit {
        let id = UUID()
        var stamped = body
        stamped.idempotencyKey = id.uuidString
        return PendingSplit(
            id: id,
            idempotencyKey: id.uuidString,
            userId: userId,
            workspaceId: workspaceId,
            body: stamped,
            createdAt: Date()
        )
    }

    var isFull: Bool { entries.count >= maxEntries }

    /// Writes the split to disk, then tries once to upload it.
    ///
    /// Persisting first is the point. Branching on "am I online?" and skipping
    /// the file would leave the *interesting* failures — request sent then the
    /// app is killed, socket dropped mid-body — in the one path with no
    /// durability. This way every split survives, and being online just means
    /// the entry usually disappears again within a second.
    func save(_ entry: PendingSplit) async -> SplitSaveOutcome {
        guard !isFull else {
            return .rejected("You have \(maxEntries) splits waiting to upload. Send those first.")
        }
        entries.append(entry)
        persist()
        return await attempt(entry.id, timeout: 8)
    }

    // MARK: Syncing

    /// Uploads everything waiting for this user, oldest first.
    ///
    /// Serial on purpose: the monthly cap is consumed in order, so if a queue
    /// runs into it the user can see exactly which splits landed and which
    /// didn't, instead of an arbitrary subset.
    func flush(userId: String) async {
        if let inFlight {
            rerunRequested = true
            await inFlight.value
            return
        }
        let task = Task { await runPass(userId: userId) }
        inFlight = task
        await task.value
        inFlight = nil
        if rerunRequested {
            rerunRequested = false
            await flush(userId: userId)
        }
    }

    private func runPass(userId: String) async {
        isWaitingForSignIn = false
        let now = Date()
        let due = entries(userId: userId).filter { entry in
            entry.isWaiting && (entry.nextAttemptAt ?? .distantPast) <= now
        }

        for entry in due {
            switch await attempt(entry.id, timeout: nil) {
            case .created, .rejected:
                continue
            case .queued(let updated):
                // No connection, or the session is gone: every remaining entry
                // would fail the same way, so stop rather than hammer.
                if updated.isWaiting && updated.nextAttemptAt == nil { return }
                if isWaitingForSignIn { return }
            }
        }
    }

    @discardableResult
    private func attempt(_ id: UUID, timeout: TimeInterval?) async -> SplitSaveOutcome {
        guard let index = entries.firstIndex(where: { $0.id == id }) else {
            return .rejected("This split is no longer waiting to upload.")
        }
        let entry = entries[index]
        update(id) { $0.state = .uploading }

        do {
            let response: BillSplitResponse = try await api.fetch(
                Endpoints.billSplits(entry.workspaceId),
                method: "POST",
                body: entry.body,
                timeout: timeout
            )
            // Only now, with a decoded split in hand, is it safe to forget it.
            remove(id)
            return .created(response.split)
        } catch {
            return record(failure: error, for: id)
        }
    }

    private func record(failure error: Error, for id: UUID) -> SplitSaveOutcome {
        switch SplitSyncPolicy.classify(error) {
        case .notYet:
            // Costs no attempt: being in a basement is not the split's fault.
            update(id) {
                $0.state = .queued
                $0.nextAttemptAt = nil
                $0.lastErrorMessage = nil
            }
        case .waitForSignIn:
            isWaitingForSignIn = true
            update(id) { $0.state = .queued }
        case .retryLater:
            update(id) { entry in
                entry.attemptCount += 1
                entry.lastErrorMessage = error.localizedDescription
                if entry.attemptCount >= SplitSyncPolicy.maxAttempts {
                    entry.state = .needsAttention(.serverUnavailable(error.localizedDescription))
                    entry.nextAttemptAt = nil
                } else {
                    entry.state = .queued
                    entry.nextAttemptAt = Date().addingTimeInterval(
                        SplitSyncPolicy.backoff(forAttempt: entry.attemptCount)
                    )
                }
            }
        case .giveUp(let reason):
            // A payload the server won't take goes straight back to the sheet,
            // exactly as it did before there was a queue.
            if reason.isFixableByEditing {
                remove(id)
                return .rejected(reason.message)
            }
            update(id) { entry in
                entry.attemptCount += 1
                entry.state = .needsAttention(reason)
                entry.nextAttemptAt = nil
                entry.lastErrorMessage = reason.message
            }
        }
        guard let entry = entries.first(where: { $0.id == id }) else {
            return .rejected(error.localizedDescription)
        }
        return .queued(entry)
    }

    // MARK: Editing

    /// Puts a blocked entry back in line. Keeps the original key: if the first
    /// attempt somehow did land, the retry replays it rather than creating a
    /// second split.
    func retry(_ id: UUID) {
        update(id) {
            $0.state = .queued
            $0.attemptCount = 0
            $0.nextAttemptAt = nil
            $0.lastErrorMessage = nil
        }
    }

    func remove(_ id: UUID) {
        entries.removeAll { $0.id == id }
        persist()
    }

    /// Everything belonging to an account that is going away for good.
    func removeAll(userId: String) {
        entries.removeAll { $0.userId == userId }
        persist()
    }

    private func update(_ id: UUID, _ change: (inout PendingSplit) -> Void) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        change(&entries[index])
        persist()
    }

    private func persist() {
        PendingSplitStore.save(entries)
    }
}

import Foundation

// MARK: - Organizer-facing models (workspace-scoped API)

struct BillSplitSummary: Codable, Identifiable {
    let id: String
    let shareToken: String
    /// Built by the server from its own `WEB_ORIGIN`.
    let shareUrl: String?
    let merchant: String
    let currency: String
    let occurredAt: String
    let totalCents: Int
    let status: String
    let participantCount: Int
    let settledCount: Int
    let pendingCount: Int
    /// Null while the split is open — shares are still moving, so there is no
    /// meaningful "still owed" figure yet.
    let outstandingCents: Int?
}

struct BillSplitItem: Codable, Identifiable {
    let id: String
    let name: String
    let quantity: Int
    let allocationMode: String
    let claimedQuantity: Int
    let availableQuantity: Int?
    let unitPriceCents: Int
    let lineTotalCents: Int
    let sortOrder: Int

    private enum CodingKeys: String, CodingKey {
        case id, name, quantity, allocationMode, claimedQuantity, availableQuantity
        case unitPriceCents, lineTotalCents, sortOrder
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        quantity = try values.decode(Int.self, forKey: .quantity)
        allocationMode = try values.decodeIfPresent(String.self, forKey: .allocationMode) ?? "shared"
        claimedQuantity = try values.decodeIfPresent(Int.self, forKey: .claimedQuantity) ?? 0
        availableQuantity = try values.decodeIfPresent(Int.self, forKey: .availableQuantity)
        unitPriceCents = try values.decode(Int.self, forKey: .unitPriceCents)
        lineTotalCents = try values.decode(Int.self, forKey: .lineTotalCents)
        sortOrder = try values.decode(Int.self, forKey: .sortOrder)
    }
}

struct BillSplitParticipant: Codable, Identifiable {
    let id: String
    let name: String
    let isOrganizer: Bool
    let claimedItemIds: [String]
    let claimQuantities: [String: Int]
    let owedCents: Int
    let shareCents: Int?
    let settledAt: String?
    let incomeId: String?
    let joinedAt: String

    private enum CodingKeys: String, CodingKey {
        case id, name, isOrganizer, claimedItemIds, claimQuantities, owedCents
        case shareCents, settledAt, incomeId, joinedAt
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        isOrganizer = try values.decode(Bool.self, forKey: .isOrganizer)
        claimedItemIds = try values.decodeIfPresent([String].self, forKey: .claimedItemIds) ?? []
        claimQuantities = try values.decodeIfPresent([String: Int].self, forKey: .claimQuantities) ?? [:]
        owedCents = try values.decode(Int.self, forKey: .owedCents)
        shareCents = try values.decodeIfPresent(Int.self, forKey: .shareCents)
        settledAt = try values.decodeIfPresent(String.self, forKey: .settledAt)
        incomeId = try values.decodeIfPresent(String.self, forKey: .incomeId)
        joinedAt = try values.decode(String.self, forKey: .joinedAt)
    }

    var isSettled: Bool { settledAt != nil }
}

/// Pure navigation state for the pass-the-phone flow.
///
/// Participant identity, not array position, is the source of truth. Server
/// refreshes can insert, remove, or reorder people while the phone is moving
/// around the table; keeping the id here prevents that refresh from silently
/// switching the person whose claims are being edited.
struct PassAroundState: Equatable {
    private(set) var orderedParticipantIDs: [String]
    private(set) var currentParticipantID: String?
    private(set) var hasStarted = false
    private var soloWasConfirmed = false

    init(participantIDs: [String]) {
        orderedParticipantIDs = Self.unique(participantIDs)
        currentParticipantID = nil
    }

    var canStart: Bool {
        orderedParticipantIDs.count >= 2
            || (orderedParticipantIDs.count == 1 && soloWasConfirmed)
    }

    /// One-based position for display; zero before the claim flow starts.
    var position: Int {
        guard let currentParticipantID,
              let index = orderedParticipantIDs.firstIndex(of: currentParticipantID) else { return 0 }
        return index + 1
    }

    var isLast: Bool { position > 0 && position == orderedParticipantIDs.count }

    mutating func continueWithJustMe() {
        guard orderedParticipantIDs.count == 1 else { return }
        soloWasConfirmed = true
    }

    @discardableResult
    mutating func start() -> Bool {
        guard canStart, let first = orderedParticipantIDs.first else { return false }
        hasStarted = true
        if let currentParticipantID, orderedParticipantIDs.contains(currentParticipantID) {
            // Resume the same person when returning from table setup.
        } else {
            currentParticipantID = first
        }
        return true
    }

    mutating func selectNext() {
        guard let currentParticipantID,
              let index = orderedParticipantIDs.firstIndex(of: currentParticipantID),
              index + 1 < orderedParticipantIDs.count else { return }
        self.currentParticipantID = orderedParticipantIDs[index + 1]
    }

    mutating func selectPrevious() {
        guard let currentParticipantID,
              let index = orderedParticipantIDs.firstIndex(of: currentParticipantID),
              index > 0 else { return }
        self.currentParticipantID = orderedParticipantIDs[index - 1]
    }

    mutating func moveParticipant(id: String, by offset: Int) {
        guard let oldIndex = orderedParticipantIDs.firstIndex(of: id) else { return }
        let newIndex = min(max(0, oldIndex + offset), orderedParticipantIDs.count - 1)
        guard oldIndex != newIndex else { return }
        orderedParticipantIDs.remove(at: oldIndex)
        orderedParticipantIDs.insert(id, at: newIndex)
    }

    mutating func adoptParticipantIDs(_ participantIDs: [String]) {
        let incoming = Self.unique(participantIDs)
        let incomingSet = Set(incoming)
        let oldPosition = max(0, position - 1)
        var nextOrder = orderedParticipantIDs.filter(incomingSet.contains)
        nextOrder.append(contentsOf: incoming.filter { !nextOrder.contains($0) })
        orderedParticipantIDs = nextOrder

        if let currentParticipantID, incomingSet.contains(currentParticipantID) {
            return
        }
        currentParticipantID = nextOrder.isEmpty
            ? nil
            : nextOrder[min(oldPosition, nextOrder.count - 1)]
    }

    private static func unique(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }
    }
}

/// Derived bounds and copy for one participant's item claim controls.
struct SplitClaimControlState: Equatable {
    let isShared: Bool
    let mine: Int
    let available: Int
    let total: Int

    init(
        allocationMode: String,
        totalQuantity: Int,
        claimedQuantity: Int,
        participantQuantity: Int
    ) {
        isShared = allocationMode == "shared"
        total = max(1, totalQuantity)
        if isShared {
            mine = participantQuantity > 0 ? 1 : 0
            available = 0
        } else {
            mine = min(max(0, participantQuantity), total)
            available = max(0, total - max(0, claimedQuantity))
        }
    }

    var canDecrement: Bool { !isShared && mine > 0 }
    var canIncrement: Bool { !isShared && available > 0 }
    var decrementedQuantity: Int { canDecrement ? mine - 1 : mine }
    var incrementedQuantity: Int { canIncrement ? mine + 1 : mine }
    var unitSelectionQuantity: Int { isShared ? sharedDesiredQuantity : (mine > 0 ? mine : 1) }
    var canSelectUnit: Bool { !isShared && mine == 0 && canIncrement }
    var sharedActionTitle: String { mine > 0 ? "Remove share" : "Share item" }
    var sharedDesiredQuantity: Int { mine > 0 ? 0 : 1 }
    var sharedPresentation: SharedClaimPresentation {
        mine > 0
            ? SharedClaimPresentation(title: "Included", isSelected: true, accessibilityLabel: "Remove me")
            : SharedClaimPresentation(title: "Add me", isSelected: false, accessibilityLabel: "Add me")
    }
}

struct SharedClaimPresentation: Equatable {
    let title: String
    let isSelected: Bool
    let accessibilityLabel: String

    func accessibilityLabel(isEnabled: Bool) -> String {
        isEnabled ? accessibilityLabel : "Shared item unavailable"
    }
}

/// The accounting meaning used by the UI after decoding a server response.
///
/// The wire value remains optional so cached responses from an older server can
/// still decode. Rendering never branches on that optional value directly:
/// missing and unknown values become `.unavailable`, which cannot be mistaken
/// for the organizer having paid the whole bill.
enum BillSplitPayerMode: Equatable {
    case organizerPaid
    case eachOwn
    case unavailable

    init(persistedValue: String?) {
        switch persistedValue {
        case "me": self = .organizerPaid
        case "each_own": self = .eachOwn
        default: self = .unavailable
        }
    }
}

/// Copy and capabilities shared by split detail and the linked expense card.
/// Keeping these decisions pure prevents one screen from inventing a debt that
/// the other screen correctly knows does not exist.
struct SplitAccountingPresentation: Equatable {
    enum SummaryMode: Equatable {
        case organizerReimbursement
        case individualShares
        case reviewRequired
    }

    let payerMode: BillSplitPayerMode

    var summaryMode: SummaryMode {
        switch payerMode {
        case .organizerPaid: .organizerReimbursement
        case .eachOwn: .individualShares
        case .unavailable: .reviewRequired
        }
    }

    var reviewMessage: String? {
        payerMode == .unavailable ? "Split mode unavailable — open to review" : nil
    }

    var allowsSettlementActions: Bool { payerMode == .organizerPaid }

    var peopleSectionTitle: String {
        switch payerMode {
        case .organizerPaid: "Who owes what"
        case .eachOwn: "Individual shares"
        case .unavailable: "Split needs review"
        }
    }

    var eachOwnSummaryTitle: String { "Everyone paid their own share" }

    var eachOwnOtherSharesLabel: String { "Everyone else's shares" }

    var eachOwnShareLabel: String { "Your share" }

    var eachOwnExpenseNote: String { "Only your share was recorded as an expense." }

    func expenseSubtitle(
        participantCount: Int,
        guestCount: Int,
        settledGuestCount: Int
    ) -> String {
        switch payerMode {
        case .eachOwn:
            return guestCount == 0
                ? "Your individual share"
                : "Split \(participantCount) ways · everyone paid their own"
        case .organizerPaid:
            if guestCount == 0 { return "Nobody has joined yet" }
            if settledGuestCount == guestCount { return "Everyone settled up" }
            return "\(settledGuestCount) of \(guestCount) paid you back"
        case .unavailable:
            return reviewMessage ?? "Split needs review"
        }
    }

    func participantStatus(isOrganizer: Bool, isSettled: Bool) -> String {
        switch payerMode {
        case .eachOwn:
            return isOrganizer ? "Your share" : "Paid their own"
        case .organizerPaid:
            if isOrganizer { return "Paid the bill" }
            return isSettled ? "Settled" : "Owes you"
        case .unavailable:
            return "Share needs review"
        }
    }

    func participantSubtitle(
        isOrganizer: Bool,
        isEvenSplit: Bool,
        claimedItemCount: Int
    ) -> String {
        switch payerMode {
        case .unavailable:
            return "Share needs review"
        case .eachOwn:
            if isOrganizer { return "Your share" }
            if isEvenSplit { return "Individual share" }
            return "\(claimedItemCount) item\(claimedItemCount == 1 ? "" : "s")"
        case .organizerPaid:
            if isEvenSplit { return "Equal share" }
            if isOrganizer { return "Paid the bill" }
            return "\(claimedItemCount) item\(claimedItemCount == 1 ? "" : "s")"
        }
    }

    func emptyPeopleMessage(isOpen: Bool) -> String? {
        guard isOpen else { return nil }
        switch payerMode {
        case .organizerPaid:
            return "Nobody has joined yet. Send the link and their picks show up here."
        case .eachOwn:
            return "Add everyone at the table to show their individual shares."
        case .unavailable:
            return reviewMessage
        }
    }

    func lockedHeaderStatus(outstandingCents: Int, currency: String = "MXN") -> String {
        switch payerMode {
        case .eachOwn:
            return "Everyone paid their own share"
        case .organizerPaid:
            return outstandingCents > 0
                ? "\(formatSplitMoney(outstandingCents, currency: currency)) still owed to you"
                : "Everyone has settled up"
        case .unavailable:
            return reviewMessage ?? "Split needs review"
        }
    }

    func lockButtonTitle(isOpen: Bool) -> String {
        switch payerMode {
        case .eachOwn:
            return isOpen ? "Finish split" : "Reopen for claiming"
        case .organizerPaid:
            return isOpen ? "Close claiming & collect" : "Reopen for claiming"
        case .unavailable:
            return "Review split mode"
        }
    }

    func lockButtonCaption(isOpen: Bool) -> String {
        switch payerMode {
        case .eachOwn:
            return isOpen
                ? "Freezes everyone's share and records your own share as an expense. Everyone pays their own share directly."
                : "Reopening removes the expense recorded for your share until you finish again."
        case .organizerPaid:
            return isOpen
                ? "Freezes everyone's share so you can start marking people as paid."
                : "Un-settle everyone first if you need to change the items."
        case .unavailable:
            return "Choose who paid before changing this split's accounting."
        }
    }
}

/// Shared tip choices and money arithmetic for both rendering and selection.
enum TipPreset {
    static let values = [10, 12, 15, 20]

    static func cents(base: Int, percent: Int) -> Int {
        guard base > 0, percent > 0 else { return 0 }
        return Int((Double(base) * Double(percent) / 100).rounded())
    }

    static func activePercent(base: Int, tipCents: Int) -> Int? {
        guard base > 0, tipCents > 0 else { return nil }
        return values.first { cents(base: base, percent: $0) == tipCents }
    }

    static func retotal(
        selectedTotal: Int,
        replacing oldTip: Int,
        with newTip: Int
    ) -> Int {
        max(0, selectedTotal - oldTip) + newTip
    }
}

struct BillSplit: Codable, Identifiable {
    let id: String
    let shareToken: String
    /// The public claim URL, built by the server from its own `WEB_ORIGIN`.
    /// Optional so an older deployment that doesn't send it still works.
    let shareUrl: String?
    let merchant: String
    let currency: String
    let occurredAt: String
    let subtotalCents: Int
    let taxCents: Int
    let tipCents: Int
    let feeCents: Int
    let totalCents: Int
    let status: String
    /// Optimistic concurrency token for complete draft edits.
    let version: Int
    /// Audit-only confirmation that a material line/total mismatch was kept.
    let mismatchAcknowledged: Bool
    /// "me" — you fronted the whole bill and the table owes you.
    /// "each_own" — everyone paid their own share, so nobody owes anybody.
    /// Missing legacy wire values decode to `unavailable`; presentation must
    /// resolve that explicit domain state before showing accounting language.
    let payer: String
    /// "by_item" (people claim what they ordered) | "even" (divided by heads).
    let splitMode: String?
    let paymentChannel: String
    let creditCardId: String?
    let categoryId: String?
    let expenseId: String?
    let createdAt: String
    let items: [BillSplitItem]
    let participants: [BillSplitParticipant]
    let unclaimedItemsCents: Int
    let unallocatedExtrasCents: Int
    let outstandingCents: Int

    private enum CodingKeys: String, CodingKey {
        case id, shareToken, shareUrl, merchant, currency, occurredAt, subtotalCents
        case taxCents, tipCents, feeCents, totalCents, status, version
        case mismatchAcknowledged, payer, splitMode, paymentChannel, creditCardId
        case categoryId, expenseId, createdAt, items, participants, unclaimedItemsCents
        case unallocatedExtrasCents, outstandingCents
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        shareToken = try values.decode(String.self, forKey: .shareToken)
        shareUrl = try values.decodeIfPresent(String.self, forKey: .shareUrl)
        merchant = try values.decode(String.self, forKey: .merchant)
        currency = try values.decode(String.self, forKey: .currency)
        occurredAt = try values.decode(String.self, forKey: .occurredAt)
        subtotalCents = try values.decode(Int.self, forKey: .subtotalCents)
        taxCents = try values.decode(Int.self, forKey: .taxCents)
        tipCents = try values.decode(Int.self, forKey: .tipCents)
        feeCents = try values.decode(Int.self, forKey: .feeCents)
        totalCents = try values.decode(Int.self, forKey: .totalCents)
        status = try values.decode(String.self, forKey: .status)
        version = try values.decodeIfPresent(Int.self, forKey: .version) ?? 0
        mismatchAcknowledged = try values.decodeIfPresent(Bool.self, forKey: .mismatchAcknowledged) ?? false
        payer = try values.decodeIfPresent(String.self, forKey: .payer) ?? "unavailable"
        splitMode = try values.decodeIfPresent(String.self, forKey: .splitMode)
        paymentChannel = try values.decodeIfPresent(String.self, forKey: .paymentChannel) ?? "cash"
        creditCardId = try values.decodeIfPresent(String.self, forKey: .creditCardId)
        categoryId = try values.decodeIfPresent(String.self, forKey: .categoryId)
        expenseId = try values.decodeIfPresent(String.self, forKey: .expenseId)
        createdAt = try values.decode(String.self, forKey: .createdAt)
        items = try values.decode([BillSplitItem].self, forKey: .items)
        participants = try values.decode([BillSplitParticipant].self, forKey: .participants)
        unclaimedItemsCents = try values.decode(Int.self, forKey: .unclaimedItemsCents)
        unallocatedExtrasCents = try values.decode(Int.self, forKey: .unallocatedExtrasCents)
        outstandingCents = try values.decode(Int.self, forKey: .outstandingCents)
    }

    var isOpen: Bool { status == "open" }
    var payerMode: BillSplitPayerMode { BillSplitPayerMode(persistedValue: payer) }
    var accountingPresentation: SplitAccountingPresentation {
        SplitAccountingPresentation(payerMode: payerMode)
    }
    /// Nobody owes the organizer: everyone settled with the restaurant directly.
    var isEachOwn: Bool { payerMode == .eachOwn }
    var isEvenSplit: Bool { splitMode == "even" }
    var isSettled: Bool { status == "settled" }
    var organizer: BillSplitParticipant? { participants.first(where: \.isOrganizer) }
    var guests: [BillSplitParticipant] { participants.filter { !$0.isOrganizer } }

    /// Web URL to hand to people who don't have the app.
    ///
    /// Prefer the server's value: it knows which Panel deployment actually serves
    /// `/s/:shareToken` for this environment, and a link built here would go stale
    /// the moment that moves.
    var shareLink: URL? {
        if let shareUrl, let url = URL(string: shareUrl) { return url }
        return URL(string: "\(SplitLinks.fallbackWebBase)/s/\(shareToken)")
    }
}

/// Cents → "$1,234.56". Split screens show money constantly, so this lives next
/// to the models rather than being re-derived per view.
func formatSplitMoney(_ cents: Int, currency: String = "MXN") -> String {
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.currencyCode = currency
    f.locale = Locale(identifier: "es_MX")
    return f.string(from: NSNumber(value: Double(cents) / 100.0)) ?? "\(cents)"
}

/// Timestamps arrive as ISO strings; tolerate a plain date and epoch ms too.
func formatSplitDate(_ raw: String) -> String {
    let formats = ["yyyy-MM-dd'T'HH:mm:ss.SSSZ", "yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd"]
    let out = DateFormatter()
    out.dateStyle = .medium
    out.timeStyle = .none
    for fmt in formats {
        let f = DateFormatter()
        f.dateFormat = fmt
        if let d = f.date(from: raw) { return out.string(from: d) }
    }
    if let ms = Double(raw), ms > 1_000_000_000_000 {
        return out.string(from: Date(timeIntervalSince1970: ms / 1000))
    }
    return String(raw.prefix(10))
}

/// Initials for the little avatar chips on shared items.
func splitInitials(_ name: String) -> String {
    name.split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init).joined().uppercased()
}

enum SplitLinks {
    /// Last resort only, for a server too old to return `shareUrl`. The server's
    /// `WEB_ORIGIN` is the real source of truth for where splits are claimed.
    static let fallbackWebBase: String = {
        #if DEBUG
        return "https://settler-v2-panel.pages.dev"
        #else
        return "https://web.settlr.cash"
        #endif
    }()
}

struct BillSplitListResponse: Decodable { let splits: [BillSplitSummary] }
struct BillSplitResponse: Decodable { let split: BillSplit }

// MARK: - Request bodies

/// `Codable`, not just `Encodable`: a split composed with no signal is written
/// to disk in exactly this shape and replayed later, so it has to survive the
/// round trip.
struct BillSplitItemBody: Codable {
    let name: String
    let quantity: Int
    let unitPriceCents: Int
    var allocationMode: String? = nil
}

struct CreateBillSplitBody: Codable {
    let merchant: String
    let occurredAt: String
    let items: [BillSplitItemBody]
    let taxCents: Int
    let tipCents: Int
    let feeCents: Int
    let totalCents: Int
    let paymentChannel: String
    let creditCardId: String?
    /// Makes this create safe to retry. Minted once when the split is composed
    /// and reused on every attempt, so a request whose response was lost — to a
    /// dropped connection, to the app being killed — replays into the same
    /// split instead of a second one. Sent even when the phone is online: that
    /// is precisely when a response can go missing without anyone noticing.
    var idempotencyKey: String? = nil
    /// "me" | "each_own". New requests always carry an explicit payer.
    /// Legacy durable queue entries that predate this field decode as `me`.
    var payer: String = "me"
    /// "by_item" (default) | "even".
    var splitMode: String? = nil
    /// Headcount, organizer included. Required by the server for an even split.
    var participantCount: Int? = nil
    /// Optional names for the other people on an even split, in order, you
    /// excluded. Blank entries become "Person 2", "Person 3"… on the server.
    var participantNames: [String]? = nil
    /// Audit-only acknowledgement; never changes the user's selected total.
    var mismatchAcknowledged: Bool? = nil

    private enum CodingKeys: String, CodingKey {
        case merchant, occurredAt, items, taxCents, tipCents, feeCents, totalCents
        case paymentChannel, creditCardId, idempotencyKey, payer, splitMode
        case participantCount, participantNames, mismatchAcknowledged
    }

    init(
        merchant: String,
        occurredAt: String,
        items: [BillSplitItemBody],
        taxCents: Int,
        tipCents: Int,
        feeCents: Int,
        totalCents: Int,
        paymentChannel: String,
        creditCardId: String?,
        idempotencyKey: String? = nil,
        payer: String = "me",
        splitMode: String? = nil,
        participantCount: Int? = nil,
        participantNames: [String]? = nil,
        mismatchAcknowledged: Bool? = nil
    ) {
        self.merchant = merchant
        self.occurredAt = occurredAt
        self.items = items
        self.taxCents = taxCents
        self.tipCents = tipCents
        self.feeCents = feeCents
        self.totalCents = totalCents
        self.paymentChannel = paymentChannel
        self.creditCardId = creditCardId
        self.idempotencyKey = idempotencyKey
        self.payer = payer
        self.splitMode = splitMode
        self.participantCount = participantCount
        self.participantNames = participantNames
        self.mismatchAcknowledged = mismatchAcknowledged
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        merchant = try values.decode(String.self, forKey: .merchant)
        occurredAt = try values.decode(String.self, forKey: .occurredAt)
        items = try values.decode([BillSplitItemBody].self, forKey: .items)
        taxCents = try values.decode(Int.self, forKey: .taxCents)
        tipCents = try values.decode(Int.self, forKey: .tipCents)
        feeCents = try values.decode(Int.self, forKey: .feeCents)
        totalCents = try values.decode(Int.self, forKey: .totalCents)
        paymentChannel = try values.decode(String.self, forKey: .paymentChannel)
        creditCardId = try values.decodeIfPresent(String.self, forKey: .creditCardId)
        idempotencyKey = try values.decodeIfPresent(String.self, forKey: .idempotencyKey)
        payer = try values.decodeIfPresent(String.self, forKey: .payer) ?? "me"
        splitMode = try values.decodeIfPresent(String.self, forKey: .splitMode)
        participantCount = try values.decodeIfPresent(Int.self, forKey: .participantCount)
        participantNames = try values.decodeIfPresent([String].self, forKey: .participantNames)
        mismatchAcknowledged = try values.decodeIfPresent(Bool.self, forKey: .mismatchAcknowledged)
    }
}

struct EditBillSplitItemBody: Encodable {
    let id: String?
    let name: String
    let quantity: Int
    let unitPriceCents: Int
    let allocationMode: String
    var clearClaims: Bool? = nil
}

struct EditBillSplitParticipantBody: Encodable {
    let id: String?
    let name: String
    let isOrganizer: Bool
}

struct EditBillSplitBody: Encodable {
    let version: Int
    let merchant: String
    let occurredAt: String
    let currency: String
    let payer: String
    let splitMode: String
    let paymentChannel: String
    let creditCardId: String?
    let categoryId: String?
    let taxCents: Int
    let tipCents: Int
    let feeCents: Int
    let totalCents: Int
    let items: [EditBillSplitItemBody]
    let participants: [EditBillSplitParticipantBody]
    let mismatchAcknowledged: Bool
}

struct BillSplitClaimBody: Encodable {
    let itemId: String
    /// Desired quantity after this mutation. Zero removes the claim. Shared
    /// items use zero or one; unit items may use any value within capacity.
    let quantity: Int
    /// Whose claim this is. Omitted means the organizer's own row, which is what
    /// the detail screen wants; the pass-the-phone flow names each person in turn.
    var participantId: String? = nil
}

struct BillSplitParticipantNameBody: Encodable { let name: String }

struct BillSplitStatusBody: Encodable { let status: String }

struct ScanReceiptBody: Encodable { let text: String }

enum ReceiptParserPreference: String, CaseIterable, Identifiable {
    static let storageKey = "receiptParserPreference"

    case automatic, onDevice, server, serverPhoto

    var id: String { rawValue }

    var isExperimental: Bool { self == .serverPhoto }

    var displayName: String {
        return switch self {
        case .automatic: "Automatic"
        case .onDevice: "On device"
        case .server: "On server"
        case .serverPhoto: "On server + photo"
        }
    }
}

enum ReceiptParserKind: String, Codable {
    case onDevice = "on_device"
    case server
    case serverPhoto = "server_photo"

    var displayName: String {
        return switch self {
        case .onDevice: "On device"
        case .server: "On server"
        case .serverPhoto: "On server + photo"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        switch value {
        case "on_device", "onDevice": self = .onDevice
        case "server", "cloudflare": self = .server
        case "server_photo", "serverPhoto": self = .serverPhoto
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown receipt parser kind: \(value)"
            )
        }
    }
}

enum ReceiptPrivacyLegend {
    static func text(for parser: ReceiptParserKind?) -> String? {
        guard let parser else { return nil }
        return switch parser {
        case .onDevice: "Everything is read on your phone."
        case .server: "Your photo stays on your phone. Only the recognized text is sent for parsing."
        case .serverPhoto: "The receipt photo and recognized text are sent securely to the server for AI parsing. The server does not store the photo. If Save captures to Photos is enabled, a local copy is saved to your photo library. The AI provider does not use it to train its models."
        }
    }

    static func attemptText(for parser: ReceiptParserKind?) -> String? {
        guard let parser else { return nil }
        if parser == .serverPhoto {
            return "Sending the photo and recognized text to the server. The server does not store the photo. If Save captures to Photos is enabled, a local copy is saved to your photo library."
        }
        return text(for: parser)
    }

    static func text(
        for parser: ReceiptParserKind?,
        requestedParser: ReceiptParserKind?,
        fallback: ReceiptParserKind?
    ) -> String? {
        guard let parser else { return nil }
        if requestedParser == .serverPhoto, fallback == .server {
            return "The receipt photo and recognized text were sent to the server for parsing. The server used the recognized-text fallback and does not store the photo. If Save captures to Photos is enabled, a local copy is saved to your photo library."
        }
        return text(for: parser)
    }
}

enum ReceiptVerification: String, Codable {
    case verified
    case unverified
}

struct ScannedReceiptItem: Decodable {
    let name: String
    let quantity: Int
    let unitPriceCents: Int
    let verification: ReceiptVerification

    init(
        name: String,
        quantity: Int,
        unitPriceCents: Int,
        verification: ReceiptVerification = .unverified
    ) {
        self.name = name
        self.quantity = quantity
        self.unitPriceCents = unitPriceCents
        self.verification = verification
    }

    private enum CodingKeys: String, CodingKey {
        case name, quantity, unitPriceCents, verification
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        name = try values.decode(String.self, forKey: .name)
        quantity = try values.decode(Int.self, forKey: .quantity)
        unitPriceCents = try values.decode(Int.self, forKey: .unitPriceCents)
        verification = try values.decodeIfPresent(ReceiptVerification.self, forKey: .verification) ?? .unverified
    }
}

struct ScannedReceipt: Decodable {
    let parser: ReceiptParserKind
    let requestedParser: ReceiptParserKind?
    let fallback: ReceiptParserKind?
    let merchant: String?
    let items: [ScannedReceiptItem]
    let taxCents: Int
    let tipCents: Int
    let totalCents: Int
    let warnings: [String]

    init(
        parser: ReceiptParserKind,
        requestedParser: ReceiptParserKind? = nil,
        fallback: ReceiptParserKind? = nil,
        merchant: String?,
        items: [ScannedReceiptItem],
        taxCents: Int,
        tipCents: Int,
        totalCents: Int,
        warnings: [String]
    ) {
        self.parser = parser
        self.requestedParser = requestedParser
        self.fallback = fallback
        self.merchant = merchant
        self.items = items
        self.taxCents = taxCents
        self.tipCents = tipCents
        self.totalCents = totalCents
        self.warnings = warnings
    }

    private enum CodingKeys: String, CodingKey {
        case parser
        case requestedParser, fallback
        case merchant, items, taxCents, tipCents, totalCents, warnings
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        // Missing metadata means an older response from the existing server
        // endpoint. Locally-created device results always set their parser.
        parser = try values.decodeIfPresent(ReceiptParserKind.self, forKey: .parser) ?? .server
        requestedParser = try values.decodeIfPresent(ReceiptParserKind.self, forKey: .requestedParser)
        fallback = try values.decodeIfPresent(ReceiptParserKind.self, forKey: .fallback)
        merchant = try values.decodeIfPresent(String.self, forKey: .merchant)
        items = try values.decode([ScannedReceiptItem].self, forKey: .items)
        taxCents = try values.decode(Int.self, forKey: .taxCents)
        tipCents = try values.decode(Int.self, forKey: .tipCents)
        totalCents = try values.decode(Int.self, forKey: .totalCents)
        warnings = try values.decodeIfPresent([String].self, forKey: .warnings) ?? []
    }

    func attributed(to parser: ReceiptParserKind) -> ScannedReceipt {
        ScannedReceipt(
            parser: parser,
            requestedParser: requestedParser,
            fallback: fallback,
            merchant: merchant,
            items: items,
            taxCents: taxCents,
            tipCents: tipCents,
            totalCents: totalCents,
            warnings: warnings
        )
    }
}

// MARK: - Public share-link models (used by the deep-link claim screen)

struct PublicSplitParticipant: Codable, Identifiable {
    let id: String
    let name: String
    let isOrganizer: Bool
    let claimedItemIds: [String]
    let claimQuantities: [String: Int]
    let owedCents: Int
    let settled: Bool

    private enum CodingKeys: String, CodingKey {
        case id, name, isOrganizer, claimedItemIds, claimQuantities, owedCents, settled
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        isOrganizer = try values.decode(Bool.self, forKey: .isOrganizer)
        claimedItemIds = try values.decodeIfPresent([String].self, forKey: .claimedItemIds) ?? []
        claimQuantities = try values.decodeIfPresent([String: Int].self, forKey: .claimQuantities) ?? [:]
        owedCents = try values.decode(Int.self, forKey: .owedCents)
        settled = try values.decode(Bool.self, forKey: .settled)
    }
}

struct PublicSplit: Codable {
    let merchant: String
    let currency: String
    let occurredAt: String
    let subtotalCents: Int
    let taxCents: Int
    let tipCents: Int
    let feeCents: Int
    let totalCents: Int
    let status: String
    /// "me" | "each_own", and "by_item" | "even". Optional so a split served by
    /// an older deployment still decodes.
    let payer: String?
    let splitMode: String?
    let organizerName: String?
    let items: [BillSplitItem]
    let participants: [PublicSplitParticipant]
    let unclaimedItemsCents: Int
    let viewerParticipantId: String?

    var isOpen: Bool { status == "open" }
    var payerMode: BillSplitPayerMode { BillSplitPayerMode(persistedValue: payer) }
    var isEachOwn: Bool { payerMode == .eachOwn }
    /// Divided by headcount, so there is nothing for a guest to pick.
    var isEvenSplit: Bool { splitMode == "even" }
}

struct PublicSplitResponse: Decodable { let split: PublicSplit }

struct PublicJoinResponse: Decodable {
    let participantId: String
    /// Returned exactly once, at join time. Persisted in the Keychain-free
    /// UserDefaults store below because it authorizes nothing but this one split.
    let claimSecret: String
    let split: PublicSplit?
}

struct PublicJoinBody: Encodable { let name: String }

/// Per-split guest credentials for splits this device joined through a link.
enum SplitGuestStore {
    private static func key(_ shareToken: String) -> String { "settlr.split.\(shareToken)" }

    static func secret(for shareToken: String) -> String? {
        UserDefaults.standard.string(forKey: key(shareToken))
    }

    static func save(secret: String, for shareToken: String) {
        UserDefaults.standard.set(secret, forKey: key(shareToken))
    }

    static func clear(for shareToken: String) {
        UserDefaults.standard.removeObject(forKey: key(shareToken))
    }
}

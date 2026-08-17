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
    /// Optional so a split created before the field existed still decodes.
    let payer: String?
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
        payer = try values.decodeIfPresent(String.self, forKey: .payer)
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
    /// Nobody owes the organizer: everyone settled with the restaurant directly.
    var isEachOwn: Bool { payer == "each_own" }
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
    /// "me" (default) | "each_own". Omitted by callers that don't care.
    var payer: String? = nil
    /// "by_item" (default) | "even".
    var splitMode: String? = nil
    /// Headcount, organizer included. Required by the server for an even split.
    var participantCount: Int? = nil
    /// Optional names for the other people on an even split, in order, you
    /// excluded. Blank entries become "Person 2", "Person 3"… on the server.
    var participantNames: [String]? = nil
    /// Audit-only acknowledgement; never changes the user's selected total.
    var mismatchAcknowledged: Bool? = nil
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
    let claimed: Bool
    /// Whose claim this is. Omitted means the organizer's own row, which is what
    /// the detail screen wants; the pass-the-phone flow names each person in turn.
    var participantId: String? = nil
}

struct BillSplitStatusBody: Encodable { let status: String }

struct ScanReceiptBody: Encodable { let text: String }

enum ReceiptParserPreference: String, CaseIterable, Identifiable {
    static let storageKey = "receiptParserPreference"

    case automatic
    case onDevice
    case server

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .automatic: "Automatic"
        case .onDevice: "On device"
        case .server: "On server"
        }
    }
}

enum ReceiptParserKind: String, Codable {
    case onDevice = "on_device"
    case server

    var displayName: String {
        switch self {
        case .onDevice: "On device"
        case .server: "On server"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        switch value {
        case "on_device", "onDevice": self = .onDevice
        case "server", "cloudflare": self = .server
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown receipt parser kind: \(value)"
            )
        }
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
    let merchant: String?
    let items: [ScannedReceiptItem]
    let taxCents: Int
    let tipCents: Int
    let totalCents: Int
    let warnings: [String]

    init(
        parser: ReceiptParserKind,
        merchant: String?,
        items: [ScannedReceiptItem],
        taxCents: Int,
        tipCents: Int,
        totalCents: Int,
        warnings: [String]
    ) {
        self.parser = parser
        self.merchant = merchant
        self.items = items
        self.taxCents = taxCents
        self.tipCents = tipCents
        self.totalCents = totalCents
        self.warnings = warnings
    }

    private enum CodingKeys: String, CodingKey {
        case parser, merchant, items, taxCents, tipCents, totalCents, warnings
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        // Missing metadata means an older response from the existing server
        // endpoint. Locally-created device results always set their parser.
        parser = try values.decodeIfPresent(ReceiptParserKind.self, forKey: .parser) ?? .server
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
    let owedCents: Int
    let settled: Bool
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
    var isEachOwn: Bool { payer == "each_own" }
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

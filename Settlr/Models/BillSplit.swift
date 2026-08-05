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
    let unitPriceCents: Int
    let lineTotalCents: Int
    let sortOrder: Int
}

struct BillSplitParticipant: Codable, Identifiable {
    let id: String
    let name: String
    let isOrganizer: Bool
    let claimedItemIds: [String]
    let owedCents: Int
    let shareCents: Int?
    let settledAt: String?
    let incomeId: String?
    let joinedAt: String

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
    let expenseId: String?
    let createdAt: String
    let items: [BillSplitItem]
    let participants: [BillSplitParticipant]
    let unclaimedItemsCents: Int
    let unallocatedExtrasCents: Int
    let outstandingCents: Int

    var isOpen: Bool { status == "open" }
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

struct BillSplitItemBody: Encodable {
    let name: String
    let quantity: Int
    let unitPriceCents: Int
}

struct CreateBillSplitBody: Encodable {
    let merchant: String
    let occurredAt: String
    let items: [BillSplitItemBody]
    let taxCents: Int
    let tipCents: Int
    let feeCents: Int
    let totalCents: Int
    let paymentChannel: String
    let creditCardId: String?
}

struct BillSplitClaimBody: Encodable {
    let itemId: String
    let claimed: Bool
}

struct BillSplitStatusBody: Encodable { let status: String }

struct ScanReceiptBody: Encodable { let text: String }

struct ScannedReceiptItem: Decodable {
    let name: String
    let quantity: Int
    let unitPriceCents: Int
}

struct ScannedReceipt: Decodable {
    let merchant: String?
    let items: [ScannedReceiptItem]
    let taxCents: Int
    let tipCents: Int
    let totalCents: Int
    let warnings: [String]
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
    let organizerName: String?
    let items: [BillSplitItem]
    let participants: [PublicSplitParticipant]
    let unclaimedItemsCents: Int
    let viewerParticipantId: String?

    var isOpen: Bool { status == "open" }
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

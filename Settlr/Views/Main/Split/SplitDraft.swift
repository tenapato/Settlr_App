import Foundation

/// Complete, reusable state for both composing and editing a split.
///
/// Money stays in integer cents here. Text-field formatting belongs to the
/// view, while this type owns the server contract and reconciliation rules.
struct SplitDraft {
    struct Item: Identifiable, Equatable {
        let localID: UUID
        var serverID: String?
        var name: String
        var quantity: Int
        var unitPriceCents: Int
        var allocationMode: String
        var verification: ReceiptVerification
        var clearClaims: Bool

        var id: UUID { localID }
        var lineTotalCents: Int { max(0, quantity) * max(0, unitPriceCents) }
        var isBlank: Bool {
            name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && unitPriceCents == 0
        }

        init(
            localID: UUID = UUID(),
            serverID: String? = nil,
            name: String = "",
            quantity: Int = 1,
            unitPriceCents: Int = 0,
            allocationMode: String? = nil,
            verification: ReceiptVerification = .verified,
            clearClaims: Bool = false
        ) {
            self.localID = localID
            self.serverID = serverID
            self.name = name
            self.quantity = max(1, quantity)
            self.unitPriceCents = max(0, unitPriceCents)
            self.allocationMode = allocationMode ?? (quantity > 1 ? "units" : "shared")
            self.verification = verification
            self.clearClaims = clearClaims
        }
    }

    struct Participant: Identifiable, Equatable {
        let localID: UUID
        var serverID: String?
        var name: String
        var isOrganizer: Bool

        var id: UUID { localID }

        init(
            localID: UUID = UUID(),
            id: String?,
            name: String,
            isOrganizer: Bool
        ) {
            self.localID = localID
            self.serverID = id
            self.name = name
            self.isOrganizer = isOrganizer
        }
    }

    struct Reconciliation: Equatable {
        enum Kind: Equatable { case exact, rounding, shortfall, overshoot }

        let itemSubtotalCents: Int
        let calculatedTotalCents: Int
        let selectedTotalCents: Int
        /// Selected/printed total minus calculated lines and extras.
        let differenceCents: Int
        let toleranceCents: Int
        let kind: Kind
        let mismatchAcknowledged: Bool

        var isMaterial: Bool { kind == .shortfall || kind == .overshoot }
        var requiresDecision: Bool { isMaterial && !mismatchAcknowledged }
    }

    var merchant: String
    var occurredAt: Date
    var currency: String
    var payer: String
    var splitMode: String
    var participants: [Participant]
    var items: [Item]
    var taxCents: Int
    var tipCents: Int
    var feeCents: Int
    var selectedTotalCents: Int
    var paymentChannel: String
    var creditCardId: String?
    var categoryId: String?
    var mismatchAcknowledged: Bool
    var scanWarnings: [String]

    init(scan: ScannedReceipt? = nil) {
        merchant = scan?.merchant ?? ""
        occurredAt = Date()
        currency = "MXN"
        payer = "me"
        splitMode = "by_item"
        participants = [.init(id: nil, name: "You", isOrganizer: true)]
        items = scan?.items.map {
            Item(
                name: $0.name,
                quantity: $0.quantity,
                unitPriceCents: $0.unitPriceCents,
                verification: $0.verification
            )
        } ?? [Item()]
        if items.isEmpty { items = [Item()] }
        taxCents = scan?.taxCents ?? 0
        tipCents = scan?.tipCents ?? 0
        feeCents = 0
        let calculated = items.reduce(0) { $0 + $1.lineTotalCents } + taxCents + tipCents
        selectedTotalCents = (scan?.totalCents ?? 0) > 0 ? scan!.totalCents : calculated
        paymentChannel = "cash"
        creditCardId = nil
        categoryId = nil
        mismatchAcknowledged = false
        scanWarnings = scan?.warnings ?? []
    }

    init(split: BillSplit) {
        merchant = split.merchant
        occurredAt = Self.day(from: split.occurredAt) ?? Date()
        currency = split.currency
        payer = split.payer ?? "me"
        splitMode = split.splitMode ?? "by_item"
        participants = split.participants.map {
            Participant(id: $0.id, name: $0.name, isOrganizer: $0.isOrganizer)
        }
        items = split.items.sorted { $0.sortOrder < $1.sortOrder }.map {
            Item(
                serverID: $0.id,
                name: $0.name,
                quantity: $0.quantity,
                unitPriceCents: $0.unitPriceCents,
                allocationMode: $0.allocationMode,
                verification: .verified
            )
        }
        taxCents = split.taxCents
        tipCents = split.tipCents
        feeCents = split.feeCents
        selectedTotalCents = split.totalCents
        paymentChannel = split.paymentChannel
        creditCardId = split.creditCardId
        categoryId = split.categoryId
        mismatchAcknowledged = split.mismatchAcknowledged
        scanWarnings = []
    }

    var filledItems: [Item] { items.filter { !$0.isBlank } }
    var unverifiedItems: [Item] { filledItems.filter { $0.verification == .unverified } }
    var itemSubtotalCents: Int { filledItems.reduce(0) { $0 + $1.lineTotalCents } }
    var calculatedTotalCents: Int { itemSubtotalCents + taxCents + tipCents + feeCents }
    var guestParticipants: [Participant] { participants.filter { !$0.isOrganizer } }

    var reconciliation: Reconciliation {
        let difference = selectedTotalCents - calculatedTotalCents
        let tolerance = max(100, Int(Double(max(0, selectedTotalCents)) * 0.001))
        let kind: Reconciliation.Kind
        if difference == 0 {
            kind = .exact
        } else if abs(difference) <= tolerance {
            kind = .rounding
        } else if difference > 0 {
            kind = .shortfall
        } else {
            kind = .overshoot
        }
        return Reconciliation(
            itemSubtotalCents: itemSubtotalCents,
            calculatedTotalCents: calculatedTotalCents,
            selectedTotalCents: selectedTotalCents,
            differenceCents: difference,
            toleranceCents: tolerance,
            kind: kind,
            mismatchAcknowledged: mismatchAcknowledged
        )
    }

    mutating func confirmKeepReceiptTotal() {
        guard reconciliation.isMaterial else { return }
        mismatchAcknowledged = true
    }

    mutating func useCalculatedTotal() {
        selectedTotalCents = calculatedTotalCents
        mismatchAcknowledged = false
    }

    func makeCreateBody() -> CreateBillSplitBody {
        let guests = guestParticipants
        return CreateBillSplitBody(
            merchant: merchant.trimmingCharacters(in: .whitespacesAndNewlines),
            occurredAt: Self.string(from: occurredAt),
            items: filledItems.map {
                BillSplitItemBody(
                    name: $0.name.trimmingCharacters(in: .whitespacesAndNewlines),
                    quantity: max(1, $0.quantity),
                    unitPriceCents: max(0, $0.unitPriceCents),
                    allocationMode: $0.allocationMode
                )
            },
            taxCents: max(0, taxCents),
            tipCents: max(0, tipCents),
            feeCents: max(0, feeCents),
            totalCents: max(0, selectedTotalCents),
            paymentChannel: paymentChannel,
            creditCardId: paymentChannel == "credit_card" ? creditCardId : nil,
            payer: payer,
            splitMode: splitMode,
            participantCount: participants.count,
            participantNames: guests.enumerated().map { index, participant in
                let name = participant.name.trimmingCharacters(in: .whitespacesAndNewlines)
                return name.isEmpty ? "Person \(index + 2)" : name
            },
            mismatchAcknowledged: mismatchAcknowledged ? true : nil
        )
    }

    func makeEditBody(version: Int) -> EditBillSplitBody {
        EditBillSplitBody(
            version: version,
            merchant: merchant.trimmingCharacters(in: .whitespacesAndNewlines),
            occurredAt: Self.string(from: occurredAt),
            currency: currency,
            payer: payer,
            splitMode: splitMode,
            paymentChannel: paymentChannel,
            creditCardId: paymentChannel == "credit_card" ? creditCardId : nil,
            categoryId: categoryId,
            taxCents: max(0, taxCents),
            tipCents: max(0, tipCents),
            feeCents: max(0, feeCents),
            totalCents: max(0, selectedTotalCents),
            items: filledItems.map {
                EditBillSplitItemBody(
                    id: $0.serverID,
                    name: $0.name.trimmingCharacters(in: .whitespacesAndNewlines),
                    quantity: max(1, $0.quantity),
                    unitPriceCents: max(0, $0.unitPriceCents),
                    allocationMode: $0.allocationMode,
                    clearClaims: $0.clearClaims ? true : nil
                )
            },
            participants: participants.enumerated().map { index, participant in
                let name = participant.name.trimmingCharacters(in: .whitespacesAndNewlines)
                let guestNumber = participants[..<index].filter { !$0.isOrganizer }.count + 2
                return EditBillSplitParticipantBody(
                    id: participant.serverID,
                    name: name.isEmpty && !participant.isOrganizer ? "Person \(guestNumber)" : name,
                    isOrganizer: participant.isOrganizer
                )
            },
            mismatchAcknowledged: mismatchAcknowledged
        )
    }

    static func day(from raw: String) -> Date? {
        let prefix = String(raw.prefix(10))
        return dayFormatter.date(from: prefix)
    }

    static func string(from date: Date) -> String { dayFormatter.string(from: date) }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        // `DatePicker` supplies a local calendar day. Formatting that instant
        // in UTC can move the date backward for users east of Greenwich.
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

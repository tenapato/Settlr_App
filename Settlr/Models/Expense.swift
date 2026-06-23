import Foundation

struct Expense: Codable, Identifiable {
    let id: String
    let description: String
    let amountCents: Int
    let currency: String
    let occurredAt: String
    let categoryId: String?
    let creditCardId: String?
    let paymentChannel: String
    let notes: String?
    let msiInstallment: Int?
    let msiCount: Int?
    let deferredInstallment: Int?
    let deferredCount: Int?

    var amount: Double { Double(amountCents) / 100.0 }
    var displayDate: String { formatExpenseDate(occurredAt) }
    var msiTagLabel: String? { LedgerMarkers.msiTagLabel(installment: msiInstallment, count: msiCount) }
    var deferredTagLabel: String? {
        LedgerMarkers.deferredTagLabel(installment: deferredInstallment, count: deferredCount)
    }
    var isStatementVerified: Bool { LedgerMarkers.isStatementVerified(notes: notes) }
    var channelTagLabel: String? { LedgerMarkers.channelTagLabel(for: paymentChannel) }
}

private func formatExpenseDate(_ raw: String) -> String {
    let formats = ["yyyy-MM-dd'T'HH:mm:ss.SSSZ", "yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd"]
    let out = DateFormatter()
    out.dateStyle = .medium
    out.timeStyle = .none
    for fmt in formats {
        let f = DateFormatter()
        f.dateFormat = fmt
        if let d = f.date(from: raw) { return out.string(from: d) }
    }
    return String(raw.prefix(10))
}

struct ExpensesResponse: Decodable {
    let expenses: [Expense]
}

struct CreateExpenseBody: Encodable {
    let description: String
    let amountCents: Int
    let occurredAt: String
    let categoryId: String?
    let paymentChannel: String
    let creditCardId: String?
    let currency: String = "MXN"
}

struct CreateExpenseResponse: Decodable {
    let expense: Expense
}

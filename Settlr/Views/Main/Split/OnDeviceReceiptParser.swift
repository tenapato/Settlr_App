import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Structures a receipt with Apple's on-device model instead of the server.
///
/// Worth preferring when it's available: nothing leaves the phone, it costs the
/// user none of their monthly AI quota, and it answers in about a second rather
/// than waiting on a Workers AI round trip. Guided generation also constrains
/// the shape directly, so there is no JSON to coax out of a prompt.
///
/// It is never the only path — Apple Intelligence needs a recent device with the
/// feature switched on, so `parse` returns nil whenever that isn't true and the
/// caller falls back to the server.
enum OnDeviceReceiptParser {
    /// True when this device can actually run the model right now.
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            return SystemLanguageModel.default.availability == .available
        }
        #endif
        return false
    }

    /// Returns nil when on-device parsing isn't possible, so the caller can fall
    /// back. Throws only when the model ran and produced nothing usable.
    static func parse(ocrText: String) async throws -> ScannedReceipt? {
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            guard SystemLanguageModel.default.availability == .available else { return nil }
            return try await runOnDevice(ocrText: ocrText)
        }
        #endif
        return nil
    }
}

/// Rejects receipt lines that are never something anybody ordered.
///
/// Mirrors `isNonItemLine` in `Server/src/lib/receiptParser.ts`. The instructions
/// already ask the model to leave these out, but the on-device model is small and
/// a mis-read header becomes a phantom charge split across the whole table — so
/// correctness doesn't rest on prompt wording.
enum ReceiptLineFilter {
    /// Uppercase, unaccented, punctuation-free — for comparing OCR'd text.
    static func normalize(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .map { $0.isLetter || $0.isNumber ? $0 : " " }
            .reduce(into: "") { $0.append($1) }
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
            .uppercased()
    }

    /// Spanish first — the app's users are in Mexico — then English equivalents.
    private static let keywords: Set<String> = [
        "SUBTOTAL", "SUB TOTAL", "TOTAL", "GRAN TOTAL", "IVA", "IMPUESTO", "IMPUESTOS",
        "PROPINA", "SERVICIO", "CARGO POR SERVICIO", "EFECTIVO", "CAMBIO", "TARJETA",
        "PAGO", "CUENTA", "TICKET", "FACTURA", "MESA", "MESERO", "MESERA", "FOLIO",
        "RFC", "TEL", "TELEFONO", "DIRECCION", "SUCURSAL", "GRACIAS", "PERSONAS", "PAX",
        "TAX", "TIP", "GRATUITY", "SERVICE CHARGE", "CASH", "CHANGE", "CARD", "VISA",
        "MASTERCARD", "AMEX", "PAYMENT", "TABLE", "SERVER", "THANK YOU", "RECEIPT",
    ]

    static func isNonItem(_ name: String, merchant: String?) -> Bool {
        let normalized = normalize(name)
        guard !normalized.isEmpty, normalized.contains(where: \.isLetter) else { return true }

        // Leading keyword catches "TOTAL A PAGAR", "IVA 16%", "PROPINA SUGERIDA".
        if keywords.contains(where: { normalized == $0 || normalized.hasPrefix("\($0) ") }) {
            return true
        }

        if let merchant {
            let normalizedMerchant = normalize(merchant)
            if !normalizedMerchant.isEmpty {
                if normalized == normalizedMerchant { return true }
                // Either direction, because OCR truncates the header. Gated on
                // length so a short merchant can't swallow every item.
                if normalizedMerchant.count >= 4,
                   normalized.hasPrefix(normalizedMerchant) || normalizedMerchant.hasPrefix(normalized) {
                    return true
                }
            }
        }
        return false
    }
}

#if canImport(FoundationModels)

@available(iOS 26, *)
private extension OnDeviceReceiptParser {
    static func runOnDevice(ocrText: String) async throws -> ScannedReceipt {
        let session = LanguageModelSession(instructions: Instructions(instructions))
        let reply = try await session.respond(
            to: "Receipt text:\n\n\(ocrText)",
            generating: ReceiptDraft.self
        )
        return reply.content.asScannedReceipt()
    }

    static var instructions: String {
        """
        You read receipts from restaurants and shops, often in Spanish or English.

        Pull out only the things that were ordered.

        Never turn these into items:
        - subtotal, IVA, tax, propina, tip, service charge, total, cash, change,
          card or payment lines
        - the header: restaurant name, branch, address, phone, RFC, table, server,
          number of people, folio or date — not even when OCR has put an amount on
          the same line as one of them
        - the footer: "gracias por su visita", website, ticket or invoice numbers

        A line like `2  JAMESON  290.00` prints the total for both units, so the
        price of one unit is 145.00. Only treat a price as per-unit when the
        receipt marks it that way, e.g. `@ 145.00`.

        Amounts are written exactly as printed on the receipt, like 129.50.
        """
    }
}

/// Prices cross as printed decimal strings rather than cents.
///
/// Asking a model to multiply by 100 invites an order-of-magnitude slip on
/// somebody's dinner; `centsFromText` already does that conversion exactly, and
/// is the same function the manual entry fields use.
@available(iOS 26, *)
@Generable
private struct ReceiptDraft {
    @Guide(description: "The restaurant or shop name printed at the top. Empty string if there isn't one.")
    var merchant: String

    @Guide(description: "Every item that was ordered, in the order printed.")
    var items: [ReceiptDraftItem]

    @Guide(description: "Tax as printed, e.g. 229.60. Use 0 when the receipt shows none.")
    var tax: String

    @Guide(description: "Tip or gratuity as printed. Use 0 when the receipt shows none.")
    var tip: String

    @Guide(description: "The grand total as printed. Use 0 when you cannot find one.")
    var total: String
}

@available(iOS 26, *)
@Generable
private struct ReceiptDraftItem {
    @Guide(description: "The item name exactly as printed, without the price.")
    var name: String

    @Guide(description: "How many were ordered. Use 1 when the receipt doesn't say.")
    var quantity: Int

    @Guide(description: "Price of ONE unit as printed, e.g. 145.00. When a line prints the total for several units, divide it by the quantity.")
    var unitPrice: String
}

@available(iOS 26, *)
private extension ReceiptDraft {
    func asScannedReceipt() -> ScannedReceipt {
        let trimmedMerchant = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        var unreadable = 0

        let parsed: [ScannedReceiptItem] = items.compactMap { item in
            let cents = centsFromText(item.unitPrice)
            let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            // A zero or negative price is an OCR artifact or a discount line we
            // don't model — same rule the server parser applies.
            guard cents > 0, !name.isEmpty else {
                unreadable += 1
                return nil
            }
            // Not counted as unreadable: read fine, just isn't an ordered item.
            guard !ReceiptLineFilter.isNonItem(name, merchant: trimmedMerchant) else { return nil }
            return ScannedReceiptItem(
                name: String(name.prefix(120)),
                quantity: max(1, min(item.quantity, 99)),
                unitPriceCents: cents
            )
        }
        let skipped = unreadable

        return ScannedReceipt(
            merchant: trimmedMerchant.isEmpty ? nil : String(trimmedMerchant.prefix(120)),
            items: parsed,
            taxCents: max(0, centsFromText(tax)),
            tipCents: max(0, centsFromText(tip)),
            totalCents: max(0, centsFromText(total)),
            warnings: skipped > 0 ? ["\(skipped) unreadable line(s) were skipped."] : []
        )
    }
}

#endif

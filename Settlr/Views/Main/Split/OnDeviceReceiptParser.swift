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
/// Apple Intelligence needs a recent device with the feature switched on, so
/// `parse` returns nil whenever that isn't true. The caller decides whether the
/// selected preference allows a server fallback.
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

    /// Never put a concrete price in these instructions.
    ///
    /// An earlier version illustrated the quantity rule with `2 JAMESON 290.00`
    /// and "the price of one unit is 145.00". Scans came back with every line
    /// priced at exactly 145.00: the example was the most available number in
    /// context and a small model reached for it instead of reading the column.
    /// Columns are shown as `<amount>` here, and `ReceiptPrices` copies every
    /// number the user actually sees off the receipt anyway.
    static var instructions: String {
        """
        You read receipts from restaurants and shops, often in Spanish or English.

        The text is laid out one printed row per line, with the receipt's columns
        separated by runs of spaces, like `<qty>   <name>   <amount>`. The amount
        on a row belongs to the name on that same row — never to the row above or
        below it.

        Pull out only the things that were ordered, and pull out every one of
        them. Never merge two rows into one, and never drop a repeat: the same
        dish printed on two rows is two items.

        Never turn these into items:
        - subtotal, IVA, tax, propina, tip, service charge, total, cash, change,
          card or payment lines
        - the header: restaurant name, branch, address, phone, RFC, table, server,
          number of people, folio or date — not even when OCR has put an amount on
          the same line as one of them
        - the footer: "gracias por su visita", website, ticket or invoice numbers

        Copy each row's amount character for character, exactly as it is printed.
        Never round it, never convert it, never work it out, and never divide it
        by the quantity — a row that prints one amount for several units keeps
        that amount.

        Two rows that happen to cost the same still cost the same. Do not make
        prices differ to look plausible, and never reuse one row's amount on a
        different row.

        Report tax, tip and total exactly as they are printed. Do not decide
        whether the tax is charged on top or already inside the prices, and do
        not adjust any of them to make the arithmetic come out even.
        """
    }
}

/// Prices cross as printed decimal strings rather than cents.
///
/// Asking a model to multiply by 100 invites an order-of-magnitude slip on
/// somebody's dinner; `ReceiptPrices.centsFromPrinted` does that conversion
/// exactly, on a string that can be compared straight back to the receipt.
///
/// Descriptions here carry no example amounts on purpose — see `instructions`.
@available(iOS 26, *)
@Generable
private struct ReceiptDraft {
    @Guide(description: "The restaurant or shop name printed at the top. Empty string if there isn't one.")
    var merchant: String

    @Guide(description: "Every item that was ordered, in the order printed.")
    var items: [ReceiptDraftItem]

    @Guide(description: "Tax as printed on the receipt. Use 0 when it shows none.")
    var tax: String

    @Guide(description: "Tip or gratuity as printed on the receipt. Use 0 when it shows none.")
    var tip: String

    @Guide(description: "The grand total as printed. Use 0 when you cannot find one.")
    var total: String
}

@available(iOS 26, *)
@Generable
private struct ReceiptDraftItem {
    @Guide(description: "The item name exactly as printed, without the price.")
    var name: String

    @Guide(description: "The count printed on that row. Use 1 when the row prints none.")
    var quantity: Int

    @Guide(description: "The money printed on that row, copied exactly as printed. Do not divide it by the quantity.")
    var amount: String
}

@available(iOS 26, *)
private extension ReceiptDraft {
    func asScannedReceipt() -> ScannedReceipt {
        let trimmedMerchant = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        var unreadable = 0

        let parsed: [ScannedReceiptItem] = items.compactMap { item in
            // The row's money is its line total; `ReceiptPrices.rebuilt` turns
            // that back into the quantity/unit-price pair a split stores.
            let lineTotalCents = ReceiptPrices.centsFromPrinted(item.amount) ?? 0
            let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            // A zero or negative price is an OCR artifact or a discount line we
            // don't model — same rule the server parser applies.
            guard lineTotalCents > 0, !name.isEmpty else {
                unreadable += 1
                return nil
            }
            // Not counted as unreadable: read fine, just isn't an ordered item.
            guard !ReceiptLineFilter.isNonItem(name, merchant: trimmedMerchant) else { return nil }
            return ReceiptPrices.rebuilt(
                ScannedReceiptItem(
                    name: String(name.prefix(120)),
                    quantity: max(1, min(item.quantity, 99)),
                    unitPriceCents: lineTotalCents,
                    verification: .unverified
                ),
                lineTotalCents: lineTotalCents
            )
        }
        let skipped = unreadable

        return ScannedReceipt(
            parser: .onDevice,
            merchant: trimmedMerchant.isEmpty ? nil : String(trimmedMerchant.prefix(120)),
            items: parsed,
            taxCents: max(0, ReceiptPrices.centsFromPrinted(tax) ?? 0),
            tipCents: max(0, ReceiptPrices.centsFromPrinted(tip) ?? 0),
            totalCents: max(0, ReceiptPrices.centsFromPrinted(total) ?? 0),
            warnings: skipped > 0 ? ["\(skipped) unreadable line(s) were skipped."] : []
        )
    }
}

#endif

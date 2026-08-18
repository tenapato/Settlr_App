import Foundation
import UIKit

struct ReceiptScanRoutingState: Equatable {
    var preference: ReceiptParserPreference?
    var attempt: ReceiptParserKind?

    mutating func clearPhotoAttemptAfterFailure() {
        if attempt == .serverPhoto { attempt = nil }
    }
}

/// In-memory recovery material for one active scan/editor session. This type is
/// intentionally neither Codable nor connected to `PendingSplitQueue`.
struct ReceiptPhotoRecovery {
    private(set) var image: UIImage?
    private(set) var ocrText: String?

    var isAvailable: Bool { image != nil && ocrText != nil }

    mutating func retain(image: UIImage, ocrText: String) {
        self.image = image
        self.ocrText = ocrText
    }

    mutating func clear() {
        image = nil
        ocrText = nil
    }
}

/// Makes a scanned receipt add up before the organizer ever sees it.
///
/// A receipt prints more numbers than it actually charges. Mexican prices
/// already include IVA, so a printed `IVA 157.66` is a breakdown of the total,
/// not a line added on top of it — and `PROPINA SUGERIDA 10%` is a suggestion
/// the kitchen prints, not money anybody was billed. Treating either as an
/// additive charge invents money: an 1,143-peso dinner becomes 1,415 and every
/// person at the table is over-billed by a share of the difference.
///
/// The printed total is the arbiter. Whichever reading of tax and tip
/// reconstructs it is the reading the receipt meant. When no reading does, the
/// items themselves are wrong — a line was missed or read twice — and that is
/// said out loud rather than quietly folded into everyone's share.
///
/// Server parses already apply the same deterministic printed-price evidence
/// before returning. Only on-device results need local OCR price replacement;
/// server results keep their evidence and run the total/tax/tip check below.
enum ReceiptReconciler {
    /// Makes a scan add up, in the order the two checks depend on: every price
    /// is taken from the receipt first, then tax and tip are read against the
    /// total. Checking the arithmetic before the prices are trustworthy only
    /// decides which wrong answer to keep.
    static func reconcile(_ receipt: ScannedReceipt, ocrText: String) -> ScannedReceipt {
        switch receipt.parser {
        case .onDevice:
            return reconcile(ReceiptPrices.applyPrinted(to: receipt, ocrText: ocrText))
        case .server, .serverPhoto:
            return reconcile(receipt)
        }
    }

    /// How far a reading may sit from the printed total and still be accepted.
    ///
    /// The readings differ from each other by a whole tax or tip line — several
    /// percent of the bill — so a tight window still separates them cleanly
    /// while absorbing the peso-or-two of rounding a receipt carries.
    private static func tolerance(forTotal total: Int) -> Int {
        max(100, total / 1_000)
    }

    /// Which printed lines a reading treats as actually charged.
    private struct Reading {
        let chargesTax: Bool
        let chargesTip: Bool
    }

    static func reconcile(_ receipt: ScannedReceipt) -> ScannedReceipt {
        let itemsCents = receipt.items.reduce(0) { $0 + $1.unitPriceCents * max(1, $1.quantity) }
        // With no printed total there is nothing to check the items against.
        guard receipt.totalCents > 0, itemsCents > 0 else { return receipt }

        let total = receipt.totalCents
        let tax = receipt.taxCents
        let tip = receipt.tipCents

        // Most conservative first: a tie keeps both lines, so this only ever
        // drops one when dropping it is what matches the receipt.
        let readings = [
            Reading(chargesTax: true, chargesTip: true),
            Reading(chargesTax: false, chargesTip: true),
            Reading(chargesTax: true, chargesTip: false),
            Reading(chargesTax: false, chargesTip: false),
        ]

        var best = readings[0]
        var bestGap = Int.max
        for reading in readings {
            let predicted =
                itemsCents + (reading.chargesTax ? tax : 0) + (reading.chargesTip ? tip : 0)
            let gap = abs(predicted - total)
            if gap < bestGap {
                bestGap = gap
                best = reading
            }
        }

        guard bestGap <= tolerance(forTotal: total) else {
            return receipt.adding(warnings: [unreconciledWarning(items: itemsCents, total: total)])
        }

        var notes: [String] = []
        if !best.chargesTax, tax > 0 {
            notes.append(
                "The \(formatSplitMoney(tax)) of tax is already included in the item prices, so it isn't added again."
            )
        }
        if !best.chargesTip, tip > 0 {
            notes.append(
                "The receipt printed a suggested tip of \(formatSplitMoney(tip)), which isn't part of the total. Add it in Tip if you want to include it."
            )
        }

        return ScannedReceipt(
            parser: receipt.parser,
            requestedParser: receipt.requestedParser,
            fallback: receipt.fallback,
            merchant: receipt.merchant,
            items: receipt.items,
            taxCents: best.chargesTax ? tax : 0,
            tipCents: best.chargesTip ? tip : 0,
            totalCents: total,
            warnings: receipt.warnings + notes
        )
    }

    /// Names the direction of the mismatch, because the fix differs: a shortfall
    /// means a line was missed, an overshoot means one was counted twice.
    private static func unreconciledWarning(items: Int, total: Int) -> String {
        let gap = abs(total - items)
        if items > total {
            return "The items add up to \(formatSplitMoney(items)), which is \(formatSplitMoney(gap)) more than the receipt's \(formatSplitMoney(total)). Check for a line that was read twice."
        }
        return "The items add up to \(formatSplitMoney(items)), \(formatSplitMoney(gap)) short of the receipt's \(formatSplitMoney(total)). Check for a line the scan missed."
    }
}

/// Takes every price straight off the receipt.
///
/// Mirrors `applyPrintedAmounts` in `Server/src/lib/receiptParser.ts`, so the
/// on-device and server routes give the same answer for the same photo.
///
/// A language model's job here is to say which printed rows are things somebody
/// ordered. It is not trusted with the money: prices are the part it gets wrong
/// in the way that costs a real person real pesos. One scan came back with nine
/// consecutive items priced at exactly 145.00 — the number used as an example in
/// the instructions — and every one of them would have been billed to whoever
/// claimed it. The receipt is right there in the OCR text; it gets the last word.
enum ReceiptPrices {
    /// Money as a receipt prints it: digits ending in exactly two decimals.
    private static let money = try! NSRegularExpression(pattern: "\\d[\\d.,]*[.,]\\d{2}(?!\\d)")

    /// A printed money string → cents. Handles both `1,234.50` and `1.234,50`:
    /// the decimal separator is always the last one, because the token is only
    /// accepted with exactly two decimal places behind it.
    static func centsFromPrinted(_ raw: String) -> Int? {
        let cleaned = raw.filter { $0.isNumber || $0 == "." || $0 == "," }
        guard !cleaned.isEmpty else { return nil }

        if cleaned.count >= 3 {
            let decimals = cleaned.suffix(2)
            let separator = cleaned[cleaned.index(cleaned.endIndex, offsetBy: -3)]
            if (separator == "." || separator == ",") && decimals.allSatisfy(\.isNumber) {
                let whole = cleaned.dropLast(3).filter(\.isNumber)
                guard let cents = Int(decimals) else { return nil }
                return (whole.isEmpty ? 0 : (Int(whole) ?? 0)) * 100 + cents
            }
        }
        // No decimals printed: a receipt's `150` is 150 pesos, never 1.50.
        let whole = cleaned.filter(\.isNumber)
        guard !whole.isEmpty, let value = Int(whole) else { return nil }
        return value * 100
    }

    /// One printed row, reduced to what it names and what it charges.
    private struct Row {
        let printedName: String
        let label: String
        let quantity: Int
        let lineTotalCents: Int
        var claimed = false
    }

    private static func row(from line: String) -> Row? {
        let range = NSRange(line.startIndex..., in: line)
        let matches = money.matches(in: line, range: range)
        // The rightmost amount is the money column; anything left of it is a
        // unit price, a code or a quantity.
        guard let last = matches.last,
              let swiftRange = Range(last.range, in: line),
              let cents = centsFromPrinted(String(line[swiftRange])),
              cents > 0
        else { return nil }

        // Work only with text before the rightmost amount. Any earlier money
        // token is a printed unit-price column, not part of the item name.
        var nameColumn = String(line[..<swiftRange.lowerBound])
        let nameRange = NSRange(nameColumn.startIndex..., in: nameColumn)
        nameColumn = money.stringByReplacingMatches(
            in: nameColumn,
            range: nameRange,
            withTemplate: " "
        )

        // Quantity evidence is accepted only at the leading edge. A product
        // number at the end of a name (for example `XX AMB 23`) stays a name.
        let leadingQuantity = try! NSRegularExpression(
            pattern: "^\\s*(\\d{1,3})(?:\\s*[xX×*])?\\s+(?=\\p{L})"
        )
        let quantityRange = NSRange(nameColumn.startIndex..., in: nameColumn)
        var quantity = 1
        if let match = leadingQuantity.firstMatch(in: nameColumn, range: quantityRange),
           let digitsRange = Range(match.range(at: 1), in: nameColumn),
           let printedQuantity = Int(nameColumn[digitsRange]),
           (1...99).contains(printedQuantity),
           let fullRange = Range(match.range, in: nameColumn) {
            quantity = printedQuantity
            nameColumn.removeSubrange(fullRange)
        }

        let printedName = nameColumn
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        let label = ReceiptLineFilter.normalize(printedName)
        guard !label.isEmpty else { return nil }
        return Row(
            printedName: printedName,
            label: label,
            quantity: quantity,
            lineTotalCents: cents
        )
    }

    static func applyPrinted(to receipt: ScannedReceipt, ocrText: String) -> ScannedReceipt {
        var rows = ocrText.split(separator: "\n", omittingEmptySubsequences: false)
            .compactMap { row(from: String($0)) }
        guard !rows.isEmpty else { return receipt }

        var unverified = 0
        var evidenceWarnings: [String] = []
        let items: [ScannedReceiptItem] = receipt.items.map { item in
            let target = ReceiptLineFilter.normalize(item.name)

            // Exact first, so "CARAJILLO" can't consume the row that belongs to
            // "CARAJILLO MEXICANO" just because it was printed above it. Rows are
            // consumed as they match, so a dish printed twice keeps two prices.
            // Short labels may match exactly, but never by containment.
            let index = rows.firstIndex { !$0.claimed && $0.label == target }
                ?? (target.count >= 4
                    ? rows.firstIndex {
                        !$0.claimed
                            && $0.label.count >= 4
                            && ($0.label.contains(target) || target.contains($0.label))
                    }
                    : nil)
            guard let index else {
                unverified += 1
                return ScannedReceiptItem(
                    name: item.name,
                    quantity: item.quantity,
                    unitPriceCents: item.unitPriceCents,
                    verification: .unverified
                )
            }

            rows[index].claimed = true
            let row = rows[index]
            if row.quantity > 1, row.lineTotalCents % row.quantity != 0 {
                evidenceWarnings.append(
                    "\(row.printedName) has a quantity that doesn't divide its printed total, so it was kept as one line for review."
                )
            }
            return rebuilt(
                item,
                lineTotalCents: row.lineTotalCents,
                printedQuantity: row.quantity,
                printedName: row.printedName,
                verification: .verified
            )
        }

        let notes = unverified > 0
            ? ["\(unverified) line(s) couldn't be matched to a printed row — check their prices."]
            : []
        return ScannedReceipt(
            parser: receipt.parser,
            requestedParser: receipt.requestedParser,
            fallback: receipt.fallback,
            merchant: receipt.merchant,
            items: items,
            taxCents: receipt.taxCents,
            tipCents: receipt.tipCents,
            totalCents: receipt.totalCents,
            warnings: receipt.warnings + evidenceWarnings + notes
        )
    }

    /// A row's money is its line total. A quantity that doesn't divide it evenly
    /// is dropped rather than the amount: what somebody owes has to be exact,
    /// what the row says they ordered is only ever a label.
    static func rebuilt(
        _ item: ScannedReceiptItem,
        lineTotalCents: Int,
        printedQuantity: Int? = nil,
        printedName: String? = nil,
        verification: ReceiptVerification? = nil
    ) -> ScannedReceiptItem {
        let quantity = max(1, printedQuantity ?? item.quantity)
        let name = printedName ?? item.name
        let status = verification ?? item.verification
        if quantity > 1, lineTotalCents % quantity == 0 {
            return ScannedReceiptItem(
                name: name,
                quantity: quantity,
                unitPriceCents: lineTotalCents / quantity,
                verification: status
            )
        }
        return ScannedReceiptItem(
            name: name,
            quantity: 1,
            unitPriceCents: lineTotalCents,
            verification: status
        )
    }
}

enum ReceiptParserRoutingError: LocalizedError {
    case onDeviceUnavailable
    case onDeviceInvalid
    case onDeviceFailed
    case serverReturnedNoUsableRows
    case serverPhotoRequiresImage

    var errorDescription: String? {
        switch self {
        case .onDeviceUnavailable:
            "On-device parsing isn't available. Choose Automatic or On server in Settings. Your receipt text was not uploaded."
        case .onDeviceInvalid:
            "On-device parsing couldn't verify any item rows. Choose Automatic or On server in Settings. Your receipt text was not uploaded."
        case .onDeviceFailed:
            "On-device parsing couldn't finish. Choose Automatic or On server in Settings. Your receipt text was not uploaded."
        case .serverReturnedNoUsableRows:
            "On server parsing couldn't verify any item rows. Check the receipt or enter the items manually."
        case .serverPhotoRequiresImage:
            "Photo parsing needs the captured receipt image. Try scanning the receipt again."
        }
    }
}

/// Selects a parser without owning OCR or network transport. Injected closures
/// make the privacy boundary explicit: the server closure is never reached in
/// On-device mode, while Automatic alone may use it as a fallback.
@MainActor
struct ReceiptParserRouter {
    typealias Parser = (String) async throws -> ScannedReceipt?
    typealias PhotoPreparer = (UIImage) throws -> PreparedReceiptPhoto
    typealias PhotoParser = (String, PreparedReceiptPhoto) async throws -> ScannedReceipt?

    let onDevice: Parser
    let server: Parser
    let preparePhoto: PhotoPreparer
    let serverPhoto: PhotoParser
    var onAttempt: ((ReceiptParserKind) -> Void)? = nil

    init(
        onDevice: @escaping Parser,
        server: @escaping Parser,
        preparePhoto: @escaping PhotoPreparer = ReceiptPhotoUpload.prepare,
        serverPhoto: @escaping PhotoParser = { _, _ in nil },
        onAttempt: ((ReceiptParserKind) -> Void)? = nil
    ) {
        self.onDevice = onDevice
        self.server = server
        self.preparePhoto = preparePhoto
        self.serverPhoto = serverPhoto
        self.onAttempt = onAttempt
    }

    func parse(
        _ ocrText: String,
        preference: ReceiptParserPreference,
        image: UIImage? = nil
    ) async throws -> ScannedReceipt {
        switch preference {
        case .automatic:
            do {
                onAttempt?(.onDevice)
                if let raw = try await onDevice(ocrText) {
                    let result = reconciled(raw, parser: .onDevice, ocrText: ocrText)
                    if hasUsableRows(result) { return result }
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Automatic is the only mode authorized to try the server after
                // a device-model failure.
            }
            return try await parseOnServer(ocrText)

        case .onDevice:
            do {
                onAttempt?(.onDevice)
                guard let raw = try await onDevice(ocrText) else {
                    throw ReceiptParserRoutingError.onDeviceUnavailable
                }
                let result = reconciled(raw, parser: .onDevice, ocrText: ocrText)
                guard hasUsableRows(result) else {
                    throw ReceiptParserRoutingError.onDeviceInvalid
                }
                return result
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as ReceiptParserRoutingError {
                throw error
            } catch {
                throw ReceiptParserRoutingError.onDeviceFailed
            }

        case .server:
            return try await parseOnServer(ocrText)

        case .serverPhoto:
            guard let image else { throw ReceiptParserRoutingError.serverPhotoRequiresImage }
            let photo = try preparePhoto(image)
            onAttempt?(.serverPhoto)
            guard let raw = try await serverPhoto(ocrText, photo) else {
                throw ReceiptParserRoutingError.serverReturnedNoUsableRows
            }
            let result = reconciled(raw, parser: raw.parser, ocrText: ocrText)
            guard result.items.contains(where: { $0.quantity > 0 && $0.unitPriceCents > 0 }) else {
                throw ReceiptParserRoutingError.serverReturnedNoUsableRows
            }
            return result
        }
    }

    private func parseOnServer(_ ocrText: String) async throws -> ScannedReceipt {
        onAttempt?(.server)
        guard let raw = try await server(ocrText) else {
            throw ReceiptParserRoutingError.serverReturnedNoUsableRows
        }
        let result = reconciled(raw, parser: raw.parser, ocrText: ocrText)
        // An unverified server row still belongs in the editable review form;
        // only a completely empty/invalid response blocks the scan.
        guard result.items.contains(where: { $0.quantity > 0 && $0.unitPriceCents > 0 }) else {
            throw ReceiptParserRoutingError.serverReturnedNoUsableRows
        }
        return result
    }

    private func reconciled(
        _ receipt: ScannedReceipt,
        parser: ReceiptParserKind,
        ocrText: String
    ) -> ScannedReceipt {
        ReceiptReconciler.reconcile(receipt.attributed(to: parser), ocrText: ocrText)
    }

    private func hasUsableRows(_ receipt: ScannedReceipt) -> Bool {
        receipt.items.contains {
            $0.verification == .verified && $0.quantity > 0 && $0.unitPriceCents > 0
        }
    }
}

private extension ScannedReceipt {
    func adding(warnings extra: [String]) -> ScannedReceipt {
        ScannedReceipt(
            parser: parser,
            requestedParser: requestedParser,
            fallback: fallback,
            merchant: merchant,
            items: items,
            taxCents: taxCents,
            tipCents: tipCents,
            totalCents: totalCents,
            warnings: warnings + extra
        )
    }
}

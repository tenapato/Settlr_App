import Foundation

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
/// Applied to on-device and server parses alike, so the two paths can't disagree
/// about what a receipt means.
enum ReceiptReconciler {
    /// Makes a scan add up, in the order the two checks depend on: every price
    /// is taken from the receipt first, then tax and tip are read against the
    /// total. Checking the arithmetic before the prices are trustworthy only
    /// decides which wrong answer to keep.
    static func reconcile(_ receipt: ScannedReceipt, ocrText: String) -> ScannedReceipt {
        reconcile(ReceiptPrices.applyPrinted(to: receipt, ocrText: ocrText))
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
        let label: String
        let amountCents: Int
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

        // Strip the amounts and any leading count, leaving just the name.
        var label = money.stringByReplacingMatches(in: line, range: range, withTemplate: " ")
        label = label.replacingOccurrences(
            of: "^\\s*\\d+\\s*[xX*]?\\s",
            with: " ",
            options: .regularExpression
        )
        return Row(label: ReceiptLineFilter.normalize(label), amountCents: cents)
    }

    static func applyPrinted(to receipt: ScannedReceipt, ocrText: String) -> ScannedReceipt {
        var rows = ocrText.split(separator: "\n", omittingEmptySubsequences: false)
            .compactMap { row(from: String($0)) }
        guard !rows.isEmpty else { return receipt }

        var unverified = 0
        let items: [ScannedReceiptItem] = receipt.items.map { item in
            let target = ReceiptLineFilter.normalize(item.name)
            // Two or three characters of a misread name would match half the
            // receipt; below that the item is safer unverified than mismatched.
            guard target.count >= 4 else {
                unverified += 1
                return item
            }

            // Exact first, so "CARAJILLO" can't consume the row that belongs to
            // "CARAJILLO MEXICANO" just because it was printed above it. Rows are
            // consumed as they match, so a dish printed twice keeps two prices.
            let index = rows.firstIndex { !$0.claimed && $0.label == target }
                ?? rows.firstIndex { !$0.claimed && ($0.label.contains(target) || target.contains($0.label)) }
            guard let index else {
                unverified += 1
                return item
            }

            rows[index].claimed = true
            return rebuilt(item, lineTotalCents: rows[index].amountCents)
        }

        let notes = unverified > 0
            ? ["\(unverified) line(s) couldn't be matched to a printed row — check their prices."]
            : []
        return ScannedReceipt(
            merchant: receipt.merchant,
            items: items,
            taxCents: receipt.taxCents,
            tipCents: receipt.tipCents,
            totalCents: receipt.totalCents,
            warnings: receipt.warnings + notes
        )
    }

    /// A row's money is its line total. A quantity that doesn't divide it evenly
    /// is dropped rather than the amount: what somebody owes has to be exact,
    /// what the row says they ordered is only ever a label.
    static func rebuilt(_ item: ScannedReceiptItem, lineTotalCents: Int) -> ScannedReceiptItem {
        if item.quantity > 1, lineTotalCents % item.quantity == 0 {
            return ScannedReceiptItem(
                name: item.name,
                quantity: item.quantity,
                unitPriceCents: lineTotalCents / item.quantity
            )
        }
        return ScannedReceiptItem(name: item.name, quantity: 1, unitPriceCents: lineTotalCents)
    }
}

private extension ScannedReceipt {
    func adding(warnings extra: [String]) -> ScannedReceipt {
        ScannedReceipt(
            merchant: merchant,
            items: items,
            taxCents: taxCents,
            tipCents: tipCents,
            totalCents: totalCents,
            warnings: warnings + extra
        )
    }
}

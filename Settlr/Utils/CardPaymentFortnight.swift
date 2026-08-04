import Foundation

enum FortnightFilter: String, CaseIterable {
    case all, this, next, last
}

struct FortnightWindow: Equatable {
    let monthKey: String // "yyyy-MM"
    let startDay: Int
    let endDay: Int
    let label: String
}

/// A card row resolved into a fortnight window, tagged with the statement
/// month its payment date actually belongs to. Writes must target that month.
struct FortnightCard: Identifiable {
    let row: CardPaymentRow
    let resolvedDueMonthKey: String
    var id: String { row.creditCardId }
}

/// Swift port of Panel/src/lib/cardPaymentDates.ts (quincena subset).
enum CardPaymentFortnight {
    static func parseMonthKey(_ monthKey: String) -> (year: Int, month: Int)? {
        let parts = monthKey.split(separator: "-")
        guard parts.count >= 2,
              let y = Int(parts[0]),
              let m = Int(parts[1]),
              m >= 1, m <= 12 else { return nil }
        return (y, m)
    }

    static func daysInMonth(year: Int, month: Int) -> Int {
        var comps = DateComponents(); comps.year = year; comps.month = month; comps.day = 1
        let cal = Calendar.current
        guard let date = cal.date(from: comps),
              let range = cal.range(of: .day, in: .month, for: date) else { return 30 }
        return range.count
    }

    static func shiftMonth(_ monthKey: String, by delta: Int) -> String {
        guard let (y, m) = parseMonthKey(monthKey) else { return monthKey }
        var comps = DateComponents(); comps.year = y; comps.month = m + delta; comps.day = 1
        guard let date = Calendar.current.date(from: comps) else { return monthKey }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM"
        return f.string(from: date)
    }

    /// Reference day inside the viewed month, keeping today's day-of-month
    /// clamped to that month's length. Mirrors Panel referenceYmdForMonth:
    /// the fortnight follows the month being viewed, not always today.
    static func referenceDay(
        forMonth monthKey: String,
        todayDay: Int = Calendar.current.component(.day, from: Date())
    ) -> (monthKey: String, day: Int) {
        guard let (y, m) = parseMonthKey(monthKey) else { return (monthKey, 1) }
        let dim = daysInMonth(year: y, month: m)
        return (monthKey, min(max(todayDay, 1), dim))
    }

    /// Mexico-style quincena relative to the reference date. Mirrors Panel quincenaWindow.
    static func window(reference: (monthKey: String, day: Int), which: FortnightFilter) -> FortnightWindow? {
        guard which != .all, let (y, m) = parseMonthKey(reference.monthKey) else { return nil }
        let d = reference.day
        let dim = daysInMonth(year: y, month: m)
        let monthKey = reference.monthKey

        switch which {
        case .this:
            if d <= 15 {
                return FortnightWindow(monthKey: monthKey, startDay: 1, endDay: 15, label: "This fortnight (1–15)")
            }
            return FortnightWindow(monthKey: monthKey, startDay: 16, endDay: dim, label: "This fortnight (16–end)")
        case .next:
            if d <= 15 {
                return FortnightWindow(monthKey: monthKey, startDay: 16, endDay: dim, label: "Next fortnight (16–end)")
            }
            return FortnightWindow(monthKey: shiftMonth(monthKey, by: 1), startDay: 1, endDay: 15, label: "Next fortnight (1–15)")
        case .last:
            if d <= 15 {
                let prevKey = shiftMonth(monthKey, by: -1)
                guard let (py, pm) = parseMonthKey(prevKey) else { return nil }
                return FortnightWindow(monthKey: prevKey, startDay: 16, endDay: daysInMonth(year: py, month: pm), label: "Last fortnight (16–end)")
            }
            return FortnightWindow(monthKey: monthKey, startDay: 1, endDay: 15, label: "Last fortnight (1–15)")
        case .all:
            return nil
        }
    }

    /// Calendar (monthKey, day) on which the statement for dueMonthKey is paid.
    /// When the payment day is on or before the cutoff day, payment lands in
    /// the following calendar month. Mirrors Panel paymentCalendarDateForDueMonth.
    static func paymentCalendarDate(
        dueMonthKey: String,
        paymentDueDay: Int?,
        statementCutoffDay: Int?
    ) -> (monthKey: String, day: Int)? {
        guard let dueDay = paymentDueDay, dueDay >= 1 else { return nil }
        let nextMonth = statementCutoffDay.map { dueDay <= $0 } ?? false
        return (nextMonth ? shiftMonth(dueMonthKey, by: 1) : dueMonthKey, dueDay)
    }

    /// Merge two adjacent months' card rollups into the set that belongs in
    /// `window`. A card's payment for a given statement month lands either in
    /// that same calendar month or the next one, so for a target window exactly
    /// one of {window month, previous month} can produce a payment date inside
    /// it — pick whichever does, per card. Mirrors Panel mergeCardsForQuincenaWindow.
    static func mergeCards(
        window: FortnightWindow,
        currentMonthCards: [CardPaymentRow],
        previousMonthCards: [CardPaymentRow]
    ) -> [FortnightCard] {
        let prevMonthKey = shiftMonth(window.monthKey, by: -1)
        let currentById = Dictionary(uniqueKeysWithValues: currentMonthCards.map { ($0.creditCardId, $0) })
        let previousById = Dictionary(uniqueKeysWithValues: previousMonthCards.map { ($0.creditCardId, $0) })

        var orderedIds = currentMonthCards.map(\.creditCardId)
        for row in previousMonthCards where currentById[row.creditCardId] == nil {
            orderedIds.append(row.creditCardId)
        }

        var out: [FortnightCard] = []
        for id in orderedIds {
            guard let sample = currentById[id] ?? previousById[id] else { continue }

            if let pay = paymentCalendarDate(
                dueMonthKey: window.monthKey,
                paymentDueDay: sample.paymentDueDay,
                statementCutoffDay: sample.statementCutoffDay
            ), pay.monthKey == window.monthKey, pay.day >= window.startDay, pay.day <= window.endDay {
                if let row = currentById[id] {
                    out.append(FortnightCard(row: row, resolvedDueMonthKey: window.monthKey))
                }
                continue
            }

            if let pay = paymentCalendarDate(
                dueMonthKey: prevMonthKey,
                paymentDueDay: sample.paymentDueDay,
                statementCutoffDay: sample.statementCutoffDay
            ), pay.monthKey == window.monthKey, pay.day >= window.startDay, pay.day <= window.endDay {
                if let row = previousById[id] {
                    out.append(FortnightCard(row: row, resolvedDueMonthKey: prevMonthKey))
                }
            }
        }
        return out
    }
}

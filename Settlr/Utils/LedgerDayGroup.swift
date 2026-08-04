import Foundation

// MARK: - Date parsing

enum LedgerDate {
    private static let formats = [
        "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
        "yyyy-MM-dd'T'HH:mm:ssZ",
        "yyyy-MM-dd"
    ]

    /// Parses the API's `occurredAt` strings (same formats the models accept).
    static func parse(_ raw: String) -> Date? {
        for fmt in formats {
            let f = DateFormatter()
            f.dateFormat = fmt
            if let d = f.date(from: raw) { return d }
        }
        if let ms = Double(raw), ms > 1_000_000_000_000 {
            return Date(timeIntervalSince1970: ms / 1000)
        }
        return nil
    }
}

// MARK: - Day grouping

/// One day's worth of ledger items plus its subtotal, for sectioned lists.
struct DaySection<T: Identifiable>: Identifiable {
    let id: String          // yyyy-MM-dd
    let title: String       // "Today" / "Yesterday" / "Mon, Jun 16"
    let subtotalCents: Int
    let items: [T]
}

/// Groups items by calendar day (newest day first), preserving each day's input order.
func groupByDay<T: Identifiable>(
    _ items: [T],
    date: (T) -> String,
    cents: (T) -> Int
) -> [DaySection<T>] {
    let keyFmt = DateFormatter()
    keyFmt.dateFormat = "yyyy-MM-dd"

    var order: [String] = []
    var buckets: [String: [T]] = [:]
    var dayDate: [String: Date] = [:]

    for item in items {
        let raw = date(item)
        let parsed = LedgerDate.parse(raw)
        let key = parsed.map { keyFmt.string(from: $0) } ?? String(raw.prefix(10))
        if buckets[key] == nil {
            buckets[key] = []
            order.append(key)
            dayDate[key] = parsed ?? .distantPast
        }
        buckets[key]?.append(item)
    }

    let sections = order.map { key -> DaySection<T> in
        let group = buckets[key] ?? []
        let subtotal = group.reduce(0) { $0 + cents($1) }
        return DaySection(
            id: key,
            title: dayTitle(dayDate[key], fallback: key),
            subtotalCents: subtotal,
            items: group
        )
    }

    return sections.sorted { (dayDate[$0.id] ?? .distantPast) > (dayDate[$1.id] ?? .distantPast) }
}

private func dayTitle(_ date: Date?, fallback: String) -> String {
    guard let date else { return fallback }
    let cal = Calendar.current
    if cal.isDateInToday(date) { return "Today" }
    if cal.isDateInYesterday(date) { return "Yesterday" }

    let f = DateFormatter()
    let sameYear = cal.component(.year, from: date) == cal.component(.year, from: Date())
    f.dateFormat = sameYear ? "EEE, MMM d" : "MMM d, yyyy"
    return f.string(from: date)
}

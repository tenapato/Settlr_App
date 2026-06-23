import Foundation

enum MonthRangeQuery {
    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// Inclusive `[start, end]` for that calendar month in the user's local timezone (ISO instants for the API).
    static func localMonthRangeIso(_ yyyyMm: String) -> (from: String, to: String)? {
        let trimmed = yyyyMm.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(separator: "-")
        guard parts.count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              month >= 1, month <= 12 else { return nil }

        let calendar = Calendar.current

        var startComps = DateComponents()
        startComps.year = year
        startComps.month = month
        startComps.day = 1
        startComps.hour = 0
        startComps.minute = 0
        startComps.second = 0
        startComps.nanosecond = 0
        guard let start = calendar.date(from: startComps) else { return nil }

        var endComps = DateComponents()
        endComps.year = year
        endComps.month = month + 1
        endComps.day = 0
        endComps.hour = 23
        endComps.minute = 59
        endComps.second = 59
        endComps.nanosecond = 999_000_000
        guard let end = calendar.date(from: endComps) else { return nil }

        return (from: isoFormatter.string(from: start), to: isoFormatter.string(from: end))
    }

    static func summaryQuery(month: String) -> String {
        guard let range = localMonthRangeIso(month) else {
            return queryString([URLQueryItem(name: "month", value: month)])
        }
        return queryString([
            URLQueryItem(name: "month", value: month),
            URLQueryItem(name: "from", value: range.from),
            URLQueryItem(name: "to", value: range.to),
        ])
    }

    static func ledgerQuery(month: String) -> String {
        guard let range = localMonthRangeIso(month) else { return "" }
        return queryString([
            URLQueryItem(name: "from", value: range.from),
            URLQueryItem(name: "to", value: range.to),
        ])
    }

    private static func queryString(_ items: [URLQueryItem]) -> String {
        var components = URLComponents()
        components.queryItems = items
        guard let query = components.percentEncodedQuery else { return "" }
        return "?" + query
    }
}

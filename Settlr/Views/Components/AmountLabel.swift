import SwiftUI

struct AmountLabel: View {
    let cents: Int
    var currency: String = "MXN"
    var font: Font = .body
    var positive: Bool = false

    var body: some View {
        Text(formatted)
            .font(font)
            .monospacedDigit()
            .accessibilityLabel(spokenAmount)
    }

    private var formatted: String {
        let value = Double(cents) / 100.0
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.groupingSeparator = ","
        formatter.decimalSeparator = "."
        let number = formatter.string(from: NSNumber(value: value)) ?? "\(value)"
        return "\(currency) $\(number)"
    }

    private var spokenAmount: String {
        let value = Double(abs(cents)) / 100.0
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        let number = formatter.string(from: NSNumber(value: value)) ?? "\(value)"
        let sign = cents < 0 ? "minus " : (positive && cents > 0 ? "plus " : "")
        let currencyName = currency == "MXN" ? "Mexican pesos" : currency
        return "\(sign)\(number) \(currencyName)"
    }
}

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
}

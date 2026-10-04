import Foundation

@main
enum CardPaymentLoadRegression {
    static func main() {
        let request = CardPaymentLoadSnapshot(month: "2026-08", fortnight: "this")

        expect(
            !request.matches(month: "2026-09", fortnight: "this"),
            "rejects a completion after the selected month changes"
        )
        expect(
            !request.matches(month: "2026-08", fortnight: "next"),
            "rejects a completion after the selected fortnight changes"
        )
        expect(
            request.matches(month: "2026-08", fortnight: "this"),
            "accepts a completion for the unchanged selection"
        )
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError("Regression failed: \(message)") }
    }
}

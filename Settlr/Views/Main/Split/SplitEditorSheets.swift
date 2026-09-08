import SwiftUI
import Foundation

enum SplitMoneyField: Hashable { case total, tax, tip, fee }

struct SplitItemEditDraft {
    private let original: SplitDraft.Item

    init(item: SplitDraft.Item) { original = item }

    func committed(name: String, quantity: Int, unitPriceCents: Int, allocationMode: String) -> SplitDraft.Item {
        SplitDraft.Item(
            localID: original.localID,
            serverID: original.serverID,
            name: name,
            quantity: max(1, quantity),
            unitPriceCents: max(0, unitPriceCents),
            allocationMode: allocationMode,
            verification: original.verification,
            clearClaims: original.clearClaims
        )
    }
}

struct SplitPeopleEditDraft {
    var participants: [SplitDraft.Participant]

    mutating func setHeadcount(_ count: Int) {
        let target = max(1, count)
        if participants.isEmpty {
            participants = [.init(id: nil, name: "You", isOrganizer: true)]
        }
        let organizer = participants.first(where: \.isOrganizer) ?? .init(id: nil, name: "You", isOrganizer: true)
        var guests = participants.filter { !$0.isOrganizer }
        while guests.count < target - 1 {
            guests.append(.init(id: nil, name: "", isOrganizer: false))
        }
        if guests.count > target - 1 { guests.removeLast(guests.count - (target - 1)) }
        participants = [organizer] + guests
    }
}

struct SplitReceiptDetailsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var merchant: String
    @State private var occurredAt: Date
    let onCommit: (String, Date) -> Void

    init(merchant: String, occurredAt: Date, onCommit: @escaping (String, Date) -> Void) {
        _merchant = State(initialValue: merchant)
        _occurredAt = State(initialValue: occurredAt)
        self.onCommit = onCommit
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Restaurant or store", text: $merchant)
                DatePicker("Date", selection: $occurredAt, displayedComponents: .date)
            }
            .navigationTitle("Receipt details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { onCommit(merchant, occurredAt); dismiss() } }
            }
        }
    }
}

struct SplitPeopleEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: SplitPeopleEditDraft
    let onCommit: ([SplitDraft.Participant]) -> Void

    init(participants: [SplitDraft.Participant], onCommit: @escaping ([SplitDraft.Participant]) -> Void) {
        _draft = State(initialValue: SplitPeopleEditDraft(participants: participants))
        self.onCommit = onCommit
    }

    var body: some View {
        NavigationStack {
            Form {
                Stepper("People: \(draft.participants.count)", value: Binding(
                    get: { draft.participants.count },
                    set: { draft.setHeadcount($0) }
                ), in: 1...50)
                ForEach($draft.participants) { $participant in
                    TextField(participant.isOrganizer ? "Your name" : "Name (optional)", text: $participant.name)
                        .disabled(participant.isOrganizer)
                }
            }
            .navigationTitle("People")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { onCommit(draft.participants); dismiss() } }
            }
        }
    }
}

struct SplitItemEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?
    @State private var name: String
    @State private var quantity: Int
    @State private var priceText: String
    @State private var allocationMode: String
    let item: SplitDraft.Item
    let onCommit: (SplitDraft.Item) -> Void
    let onRemove: (() -> Void)?

    private enum Field: Hashable {
        case name
        case price
    }

    init(item: SplitDraft.Item, onCommit: @escaping (SplitDraft.Item) -> Void, onRemove: (() -> Void)? = nil) {
        self.item = item
        self.onCommit = onCommit
        self.onRemove = onRemove
        _name = State(initialValue: item.name)
        _quantity = State(initialValue: item.quantity)
        _priceText = State(initialValue: Self.moneyText(item.unitPriceCents))
        _allocationMode = State(initialValue: item.allocationMode)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Item", text: $name)
                    .focused($focusedField, equals: .name)
                Stepper("Quantity: \(quantity)", value: $quantity, in: 1...999)
                TextField("Unit price", text: $priceText)
                    .keyboardType(.decimalPad)
                    .focused($focusedField, equals: .price)
                Picker("Allocation", selection: $allocationMode) {
                    Text("Shared").tag("shared")
                    Text("By units").tag("units")
                }
                if let onRemove {
                    Button("Remove item", role: .destructive) { onRemove(); dismiss() }
                }
            }
            .navigationTitle("Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { commit() } }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                }
            }
        }
    }

    private func commit() {
        onCommit(SplitItemEditDraft(item: item).committed(name: name, quantity: quantity, unitPriceCents: Self.parseMoney(priceText), allocationMode: allocationMode))
        dismiss()
    }

    private static func parseMoney(_ value: String) -> Int {
        Int(((Double(value.replacingOccurrences(of: ",", with: ".")) ?? 0) * 100.0).rounded())
    }

    private static func moneyText(_ cents: Int) -> String { String(format: "%.2f", Double(cents) / 100) }
}

struct SplitMoneyEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let kind: SplitMoneyField
    let tipBaseCents: Int
    let onCommit: (Int) -> Void
    @State private var text: String

    init(kind: SplitMoneyField, cents: Int, tipBaseCents: Int, onCommit: @escaping (Int) -> Void) {
        self.kind = kind
        self.tipBaseCents = tipBaseCents
        self.onCommit = onCommit
        _text = State(initialValue: String(format: "%.2f", Double(cents) / 100))
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Amount", text: $text)
                    .keyboardType(.decimalPad)
                    .font(.system(.title2, design: .rounded).monospacedDigit())
                if kind == .tip {
                    ForEach(TipPreset.values, id: \.self) { percent in
                        let isActive = TipPreset.activePercent(base: tipBaseCents, tipCents: Self.parseMoney(text)) == percent
                        Button("\(percent)% — \(Self.money(TipPreset.cents(base: tipBaseCents, percent: percent)))") {
                            text = Self.moneyText(Self.toggledTipCents(base: tipBaseCents, currentCents: Self.parseMoney(text), percent: percent))
                        }
                        .accessibilityValue(isActive ? "Selected" : "Not selected")
                    }
                }
            }
            .navigationTitle(kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { onCommit(Self.parseMoney(text)); dismiss() } }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { onCommit(Self.parseMoney(text)); dismiss() } }
            }
        }
    }

    static func toggledTipCents(base: Int, currentCents: Int, percent: Int) -> Int {
        if TipPreset.activePercent(base: base, tipCents: currentCents) == percent {
            return 0
        }
        return TipPreset.cents(base: base, percent: percent)
    }

    private static func parseMoney(_ value: String) -> Int { max(0, Int(((Double(value.replacingOccurrences(of: ",", with: ".")) ?? 0) * 100.0).rounded())) }
    private static func moneyText(_ cents: Int) -> String { String(format: "%.2f", Double(cents) / 100) }
    private static func money(_ cents: Int) -> String { String(format: "$%.2f", Double(cents) / 100) }
}

private extension SplitMoneyField {
    var title: String {
        switch self { case .total: "Total"; case .tax: "Tax"; case .tip: "Tip"; case .fee: "Fee" }
    }
}

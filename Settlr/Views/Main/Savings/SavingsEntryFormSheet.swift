import SwiftUI

struct SavingsEntryFormSheet: View {
    let workspaceId: String
    let accounts: [SavingsAccount]
    var entry: SavingsEntry?
    var defaultAccountId: String?
    let onSave: (CreateSavingsEntryBody) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var direction: String
    @State private var accountId: String
    @State private var amountText: String
    @State private var description: String
    @State private var selectedDate: Date
    @State private var notes: String
    @State private var errorMessage: String?
    @FocusState private var amountFocused: Bool
    @FocusState private var descriptionFocused: Bool

    private var isEditing: Bool { entry != nil }

    init(
        workspaceId: String,
        accounts: [SavingsAccount],
        entry: SavingsEntry? = nil,
        defaultAccountId: String? = nil,
        onSave: @escaping (CreateSavingsEntryBody) -> Void
    ) {
        self.workspaceId = workspaceId
        self.accounts = accounts
        self.entry = entry
        self.defaultAccountId = defaultAccountId
        self.onSave = onSave

        if let entry {
            _direction = State(initialValue: entry.direction)
            _accountId = State(initialValue: entry.accountId)
            _amountText = State(initialValue: Self.formatAmount(entry.amountCents))
            _description = State(initialValue: entry.description)
            _selectedDate = State(initialValue: Self.parseFormDate(entry.occurredAt))
            _notes = State(initialValue: entry.notes ?? "")
        } else {
            _direction = State(initialValue: "deposit")
            _accountId = State(initialValue: defaultAccountId ?? accounts.first?.id ?? "")
            _amountText = State(initialValue: "")
            _description = State(initialValue: "")
            _selectedDate = State(initialValue: Date())
            _notes = State(initialValue: "")
        }
    }

    private var tint: Color {
        direction == "deposit" ? Theme.income : Theme.expense
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        directionToggle

                        HeroAmountField(amountText: $amountText, tint: tint, focus: $amountFocused)

                        FormCard {
                            FormTextRow(
                                label: "Description",
                                placeholder: direction == "deposit" ? "Where from?" : "What for?",
                                text: $description,
                                focus: $descriptionFocused
                            )
                            FormRowDivider()
                            accountRow
                            FormRowDivider()
                            dateRow
                            FormRowDivider()
                            FormTextRow(label: "Notes", placeholder: "Optional", text: $notes)
                        }

                        if let error = errorMessage {
                            Text(error)
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.expense)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Button(isEditing ? "Save Changes" : (direction == "deposit" ? "Add Deposit" : "Add Withdrawal")) {
                            save()
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(!isValid)
                        .padding(.top, 4)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(isEditing ? "Edit Entry" : "Add Savings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.muted)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { amountFocused = false; descriptionFocused = false }
                        .foregroundStyle(Theme.accent)
                        .fontWeight(.semibold)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { if !isEditing { amountFocused = true } }
    }

    // MARK: - Sections

    private var directionToggle: some View {
        SegmentedToggle(
            selection: $direction,
            options: [
                ToggleOption(value: "deposit", label: "Deposit", icon: "arrow.down.left"),
                ToggleOption(value: "withdrawal", label: "Withdrawal", icon: "arrow.up.right"),
            ]
        )
    }

    private var accountRow: some View {
        FormMenuRow(
            label: "Account",
            value: accountValueLabel,
            isPlaceholder: accountId.isEmpty
        ) {
            ForEach(accounts) { account in
                Button(account.name) { accountId = account.id }
            }
        }
    }

    private var dateRow: some View {
        HStack(spacing: 12) {
            Text("Date")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.muted)
            Spacer()
            DatePicker("", selection: $selectedDate, displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.compact)
                .tint(Theme.accent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    // MARK: - Derived

    private var isValid: Bool {
        let hasDescription = !description.trimmingCharacters(in: .whitespaces).isEmpty
        let normalized = amountText.replacingOccurrences(of: ",", with: ".")
        let hasAmount = (Double(normalized) ?? 0) > 0
        return hasDescription && hasAmount && !accountId.isEmpty
    }

    private var accountValueLabel: String {
        accounts.first(where: { $0.id == accountId })?.name ?? "Select"
    }

    // MARK: - Save

    private func save() {
        guard !accountId.isEmpty else {
            errorMessage = "Select a savings account."
            return
        }
        guard !description.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Description is required."
            return
        }
        let normalized = amountText.replacingOccurrences(of: ",", with: ".")
        guard let amount = Double(normalized), amount > 0 else {
            errorMessage = "Enter a valid amount."
            return
        }
        let cents = Int((amount * 100).rounded())
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        onSave(CreateSavingsEntryBody(
            accountId: accountId,
            direction: direction,
            amountCents: cents,
            description: description.trimmingCharacters(in: .whitespaces),
            occurredAt: f.string(from: selectedDate),
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes
        ))
        dismiss()
    }

    private static func formatAmount(_ cents: Int) -> String {
        String(format: "%.2f", Double(cents) / 100.0)
    }

    private static func parseFormDate(_ raw: String) -> Date {
        let formats = ["yyyy-MM-dd'T'HH:mm:ss.SSSZ", "yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd"]
        for fmt in formats {
            let f = DateFormatter()
            f.dateFormat = fmt
            if let date = f.date(from: raw) { return date }
        }
        if let ms = Double(raw), ms > 1_000_000_000_000 {
            return Date(timeIntervalSince1970: ms / 1000)
        }
        return Date()
    }
}

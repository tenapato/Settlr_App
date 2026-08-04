import SwiftUI

struct SavingsRecurringSheet: View {
    let workspaceId: String
    @Bindable var vm: SavingsVM
    @Environment(\.dismiss) private var dismiss

    @State private var showForm = false
    @State private var editingRule: RecurringSavings?
    @State private var ruleToDelete: RecurringSavings?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()

                if vm.recurring.isEmpty {
                    emptyState
                } else {
                    ruleList
                }
            }
            .navigationTitle("Recurring")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.muted)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        editingRule = nil
                        showForm = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    .disabled(vm.accounts.isEmpty)
                }
            }
            .sheet(isPresented: $showForm) {
                SavingsRecurringFormSheet(
                    accounts: vm.accounts,
                    rule: editingRule,
                    defaultAccountId: vm.selectedAccountId,
                    onSave: { body in
                        Task {
                            let ok: Bool
                            if let editingRule {
                                ok = await vm.updateRecurring(
                                    workspaceId: workspaceId,
                                    ruleId: editingRule.id,
                                    body: UpdateRecurringSavingsBody(
                                        accountId: body.accountId,
                                        amountCents: body.amountCents,
                                        description: body.description,
                                        frequency: body.frequency,
                                        startDate: body.startDate,
                                        notes: body.notes
                                    )
                                )
                            } else {
                                ok = await vm.createRecurring(workspaceId: workspaceId, body: body)
                            }
                            if ok {
                                showForm = false
                                editingRule = nil
                            }
                        }
                    }
                )
            }
            .overlay {
                if let rule = ruleToDelete {
                    DeleteConfirmDialog(
                        title: "Delete Recurring?",
                        itemName: "\(rule.description) — deposits already made stay",
                        onConfirm: {
                            Task { await vm.deleteRecurring(workspaceId: workspaceId, ruleId: rule.id) }
                            ruleToDelete = nil
                        },
                        onCancel: { ruleToDelete = nil }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .animation(.easeOut(duration: 0.2), value: ruleToDelete != nil)
        }
        .preferredColorScheme(.dark)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                .font(.system(size: 36))
                .foregroundStyle(Theme.faint)
            Text("No recurring investments")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.muted)
            Text("Schedule a deposit that repeats weekly, biweekly, or monthly.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.faint)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            if !vm.accounts.isEmpty {
                Button {
                    editingRule = nil
                    showForm = true
                } label: {
                    Text("Schedule deposit")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.bg)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Theme.accent)
                        .clipShape(Capsule())
                }
                .padding(.top, 4)
            }
            Spacer()
        }
    }

    private var ruleList: some View {
        List {
            ForEach(vm.recurring) { rule in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Color(hex: vm.account(for: rule.accountId)?.color ?? "#22c55e"))
                            .frame(width: 10, height: 10)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(rule.description)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Theme.ink)
                                .lineLimit(1)
                            Text("\(rule.cadence.label) · \(vm.account(for: rule.accountId)?.name ?? "—")")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.faint)
                        }

                        Spacer()

                        AmountLabel(cents: rule.amountCents, font: .system(size: 15, weight: .semibold))
                            .foregroundStyle(rule.active ? Theme.income : Theme.muted)
                    }

                    HStack(spacing: 8) {
                        if !rule.active {
                            Text("PAUSED")
                                .font(.system(size: 10, weight: .bold))
                                .tracking(0.6)
                                .foregroundStyle(Theme.muted)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Theme.surface2, in: Capsule())
                        }

                        Spacer()

                        Button(rule.active ? "Pause" : "Resume") {
                            Task {
                                _ = await vm.updateRecurring(
                                    workspaceId: workspaceId,
                                    ruleId: rule.id,
                                    body: UpdateRecurringSavingsBody(active: !rule.active)
                                )
                            }
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.accent)
                        .buttonStyle(.plain)

                        Button {
                            editingRule = rule
                            showForm = true
                        } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.muted)
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.plain)

                        Button {
                            ruleToDelete = rule
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.expense)
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
                .listRowBackground(Theme.surface)
                .listRowSeparatorTint(Theme.line)
            }

            Spacer().frame(height: 40)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
}

// MARK: - Rule create/edit form

struct SavingsRecurringFormSheet: View {
    let accounts: [SavingsAccount]
    var rule: RecurringSavings?
    var defaultAccountId: String?
    let onSave: (CreateRecurringSavingsBody) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var accountId: String
    @State private var amountText: String
    @State private var description: String
    @State private var frequency: SavingsFrequency
    @State private var startDate: Date
    @State private var notes: String
    @State private var errorMessage: String?
    @FocusState private var amountFocused: Bool
    @FocusState private var descriptionFocused: Bool

    private var isEditing: Bool { rule != nil }

    init(
        accounts: [SavingsAccount],
        rule: RecurringSavings? = nil,
        defaultAccountId: String? = nil,
        onSave: @escaping (CreateRecurringSavingsBody) -> Void
    ) {
        self.accounts = accounts
        self.rule = rule
        self.defaultAccountId = defaultAccountId
        self.onSave = onSave

        if let rule {
            _accountId = State(initialValue: rule.accountId)
            _amountText = State(initialValue: String(format: "%.2f", Double(rule.amountCents) / 100.0))
            _description = State(initialValue: rule.description)
            _frequency = State(initialValue: rule.cadence)
            _startDate = State(initialValue: Self.parseFormDate(rule.startDate))
            _notes = State(initialValue: rule.notes ?? "")
        } else {
            _accountId = State(initialValue: defaultAccountId ?? accounts.first?.id ?? "")
            _amountText = State(initialValue: "")
            _description = State(initialValue: "")
            _frequency = State(initialValue: .monthly)
            _startDate = State(initialValue: Date())
            _notes = State(initialValue: "")
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        HeroAmountField(amountText: $amountText, tint: Theme.income, focus: $amountFocused)

                        FormCard {
                            FormTextRow(
                                label: "Description",
                                placeholder: "CETES, payday save…",
                                text: $description,
                                focus: $descriptionFocused
                            )
                            FormRowDivider()
                            accountRow
                            FormRowDivider()
                            frequencyRow
                            FormRowDivider()
                            startDateRow
                            FormRowDivider()
                            FormTextRow(label: "Notes", placeholder: "Optional", text: $notes)
                        }

                        Text("Deposits are created automatically from the start date onward, including occurrences already due.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.faint)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if let error = errorMessage {
                            Text(error)
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.expense)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Button(isEditing ? "Save Changes" : "Schedule Deposits") {
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
            .navigationTitle(isEditing ? "Edit Recurring" : "New Recurring")
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

    private var accountRow: some View {
        FormMenuRow(
            label: "Account",
            value: accounts.first(where: { $0.id == accountId })?.name ?? "Select",
            isPlaceholder: accountId.isEmpty
        ) {
            ForEach(accounts) { account in
                Button(account.name) { accountId = account.id }
            }
        }
    }

    private var frequencyRow: some View {
        FormMenuRow(label: "Repeats", value: frequency.label, isPlaceholder: false) {
            ForEach(SavingsFrequency.allCases, id: \.self) { option in
                Button(option.label) { frequency = option }
            }
        }
    }

    private var startDateRow: some View {
        HStack(spacing: 12) {
            Text("Starts")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.muted)
            Spacer()
            DatePicker("", selection: $startDate, displayedComponents: .date)
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
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        onSave(CreateRecurringSavingsBody(
            accountId: accountId,
            amountCents: Int((amount * 100).rounded()),
            description: description.trimmingCharacters(in: .whitespaces),
            frequency: frequency.rawValue,
            startDate: f.string(from: startDate),
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes
        ))
        dismiss()
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

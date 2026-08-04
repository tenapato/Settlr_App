import SwiftUI

struct IncomeRecurringSheet: View {
    let workspaceId: String
    @Bindable var vm: IncomeVM
    @Environment(\.dismiss) private var dismiss

    @State private var showForm = false
    @State private var editingRule: RecurringIncome?
    @State private var ruleToDelete: RecurringIncome?

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
            .navigationTitle("Recurring Income")
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
                }
            }
            .sheet(isPresented: $showForm) {
                IncomeRecurringFormSheet(
                    categories: vm.categories,
                    rule: editingRule,
                    onSave: { body in
                        Task {
                            let ok: Bool
                            if let editingRule {
                                ok = await vm.updateRecurring(
                                    workspaceId: workspaceId,
                                    ruleId: editingRule.id,
                                    body: UpdateRecurringIncomeBody(
                                        amountCents: body.amountCents,
                                        description: body.description,
                                        frequency: body.frequency,
                                        startDate: body.startDate,
                                        categoryId: body.categoryId
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
                        itemName: "\(rule.description) — income already added stays",
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
            Text("No recurring income")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.muted)
            Text("Create a rule for salary or any inflow that repeats daily, weekly, or monthly.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.faint)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button {
                editingRule = nil
                showForm = true
            } label: {
                Text("Create rule")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.bg)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Theme.accent)
                    .clipShape(Capsule())
            }
            .padding(.top, 4)
            Spacer()
        }
    }

    private var ruleList: some View {
        List {
            ForEach(vm.recurring) { rule in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(rule.description)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Theme.ink)
                                .lineLimit(1)
                            Text("\(rule.cadence.label) · \(categoryName(rule.categoryId))")
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
                                    body: UpdateRecurringIncomeBody(active: !rule.active)
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

    private func categoryName(_ id: String?) -> String {
        guard let id, let cat = vm.categories.first(where: { $0.id == id }) else {
            return "No category"
        }
        return cat.name
    }
}

// MARK: - Rule create/edit form

struct IncomeRecurringFormSheet: View {
    let categories: [Category]
    var rule: RecurringIncome?
    let onSave: (CreateRecurringIncomeBody) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var amountText: String
    @State private var description: String
    @State private var selectedCategoryId: String?
    @State private var frequency: RecurrenceFrequency
    @State private var startDate: Date
    @State private var errorMessage: String?
    @FocusState private var amountFocused: Bool
    @FocusState private var descriptionFocused: Bool

    private var isEditing: Bool { rule != nil }

    init(
        categories: [Category],
        rule: RecurringIncome? = nil,
        onSave: @escaping (CreateRecurringIncomeBody) -> Void
    ) {
        self.categories = categories
        self.rule = rule
        self.onSave = onSave

        if let rule {
            _amountText = State(initialValue: String(format: "%.2f", Double(rule.amountCents) / 100.0))
            _description = State(initialValue: rule.description)
            _selectedCategoryId = State(initialValue: rule.categoryId)
            _frequency = State(initialValue: rule.cadence)
            _startDate = State(initialValue: Self.parseFormDate(rule.startDate))
        } else {
            _amountText = State(initialValue: "")
            _description = State(initialValue: "")
            _selectedCategoryId = State(initialValue: nil)
            _frequency = State(initialValue: .monthly)
            _startDate = State(initialValue: Date())
        }
    }

    private var incomeCategories: [Category] {
        categories.filter { $0.scope == "income" || $0.scope == "both" }
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
                                placeholder: "Salary, rent collected…",
                                text: $description,
                                focus: $descriptionFocused
                            )
                            FormRowDivider()
                            frequencyRow
                            FormRowDivider()
                            startDateRow
                            if !incomeCategories.isEmpty {
                                FormRowDivider()
                                categoryRow
                            }
                        }

                        Text("Rows are added automatically from the start date, as each month is viewed.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.faint)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if let error = errorMessage {
                            Text(error)
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.expense)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Button(isEditing ? "Save Changes" : "Create Rule") { save() }
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

    // MARK: - Rows

    private var frequencyRow: some View {
        FormMenuRow(label: "Repeats", value: frequency.label, isPlaceholder: false) {
            ForEach(RecurrenceFrequency.allCases, id: \.self) { option in
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

    private var categoryRow: some View {
        FormMenuRow(
            label: "Category",
            value: categoryValueLabel,
            isPlaceholder: selectedCategoryId == nil
        ) {
            Button("No category") { selectedCategoryId = nil }
            ForEach(incomeCategories) { cat in
                Button(cat.name) { selectedCategoryId = cat.id }
            }
        }
    }

    // MARK: - Derived

    private var isValid: Bool {
        let hasDescription = !description.trimmingCharacters(in: .whitespaces).isEmpty
        let normalized = amountText.replacingOccurrences(of: ",", with: ".")
        return hasDescription && (Double(normalized) ?? 0) > 0
    }

    private var categoryValueLabel: String {
        guard let id = selectedCategoryId,
              let cat = incomeCategories.first(where: { $0.id == id }) else { return "None" }
        return cat.name
    }

    // MARK: - Save

    private func save() {
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
        onSave(CreateRecurringIncomeBody(
            amountCents: Int((amount * 100).rounded()),
            description: description.trimmingCharacters(in: .whitespaces),
            frequency: frequency.rawValue,
            startDate: f.string(from: startDate),
            categoryId: selectedCategoryId
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

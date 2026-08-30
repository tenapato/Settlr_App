import SwiftUI
import UIKit

struct SavingsAccountsSheet: View {
    let workspaceId: String
    @Bindable var vm: SavingsVM
    @Environment(\.dismiss) private var dismiss

    @State private var showAccountForm = false
    @State private var editingAccount: SavingsAccount?
    @State private var accountToDelete: SavingsAccount?
    @State private var isSavingAccount = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()

                if vm.accounts.isEmpty && vm.accountsErrorMessage != nil && !vm.hasLoadedAccounts {
                    accountsErrorState
                } else if vm.accounts.isEmpty {
                    emptyState
                } else {
                    accountList
                }
            }
            .navigationTitle("Manage Accounts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.muted)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        editingAccount = nil
                        showAccountForm = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Create savings account")
                }
            }
            .sheet(isPresented: $showAccountForm) {
                SavingsAccountFormSheet(
                    account: editingAccount,
                    isSaving: isSavingAccount,
                    onSave: { name, color, targetAmountCents, targetDate in
                        guard !isSavingAccount else { return }
                        isSavingAccount = true
                        let generation = vm.workspaceMutationGeneration(for: workspaceId)
                        Task { @MainActor in
                            let ok: Bool
                            if let editingAccount {
                                ok = await vm.updateAccount(
                                    workspaceId: workspaceId,
                                    accountId: editingAccount.id,
                                    name: name,
                                    color: color,
                                    targetAmountCents: targetAmountCents,
                                    targetDate: targetDate,
                                    expectedGeneration: generation
                                )
                            } else {
                                ok = await vm.createAccount(
                                    workspaceId: workspaceId,
                                    name: name,
                                    color: color,
                                    targetAmountCents: targetAmountCents,
                                    targetDate: targetDate,
                                    expectedGeneration: generation
                                )
                            }
                            isSavingAccount = false
                            if ok {
                                showAccountForm = false
                                editingAccount = nil
                            }
                        }
                    }
                )
            }
            .overlay {
                if let account = accountToDelete {
                    DeleteConfirmDialog(
                        title: "Delete Account?",
                        itemName: "\(account.name) — all entries will be deleted",
                        onConfirm: {
                            let generation = vm.workspaceMutationGeneration(for: workspaceId)
                            Task { @MainActor in
                                await vm.deleteAccount(
                                    workspaceId: workspaceId,
                                    accountId: account.id,
                                    expectedGeneration: generation
                                )
                            }
                            accountToDelete = nil
                        },
                        onCancel: { accountToDelete = nil }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: accountToDelete != nil)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "banknote")
                .font(.system(size: 36))
                .foregroundStyle(Theme.faint)
            Text("No savings accounts")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.muted)
            Button {
                editingAccount = nil
                showAccountForm = true
            } label: {
                Text("Create account")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.bg)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Theme.accent)
                    .clipShape(Capsule())
            }
            Spacer()
        }
    }

    private var accountsErrorState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 32))
                .foregroundStyle(Theme.warning)
            Text("Accounts unavailable")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Text("We couldn’t load this workspace’s accounts. Try again before creating one.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
            Button("Retry") { Task { await vm.load(workspaceId: workspaceId) } }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 32)
            Spacer()
        }
        .padding(.horizontal, 28)
    }

    private var accountList: some View {
        List {
            if vm.accountsErrorMessage != nil {
                VStack(alignment: .leading, spacing: 6) {
                    SignalTraceLoadingView(lastUpdated: nil)
                    Text("Couldn’t refresh accounts. Showing your last saved data.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.warning)
                }
                .padding(.vertical, 6)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            ForEach(vm.accounts) { account in
                HStack(spacing: 14) {
                    Circle()
                        .fill(Color(hex: account.color ?? "#22c55e"))
                        .frame(width: 12, height: 12)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(account.name)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Theme.ink)
                        AmountLabel(cents: account.balanceCents, font: .system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.muted)
                        if let target = account.targetAmountCents {
                            HStack(spacing: 4) {
                                Text(accountGoalStatus(account))
                                AmountLabel(cents: target, font: .system(size: 11, weight: .medium))
                            }
                            .font(.system(size: 11))
                            .foregroundStyle(account.goalStatus == "funded" ? Theme.income : Theme.faint)
                        } else {
                            Text("Flexible")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.faint)
                        }
                    }

                    Spacer()

                    Button {
                        editingAccount = account
                        showAccountForm = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit \(account.name)")

                    Button {
                        accountToDelete = account
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.expense)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Delete \(account.name)")
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

// MARK: - Account create/edit form

struct SavingsAccountFormSheet: View {
    var account: SavingsAccount?
    let isSaving: Bool
    let onSave: (_ name: String, _ color: String, _ targetAmountCents: Int?, _ targetDate: String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var colorHex: String
    @State private var pickedColor: Color
    @State private var targetAmountText: String
    @State private var targetDate: Date
    @State private var hasTargetDate: Bool
    @State private var errorMessage: String?
    @FocusState private var nameFocused: Bool

    private var isEditing: Bool { account != nil }

    private static let presets = [
        "#22c55e", "#3b82f6", "#a855f7", "#f59e0b",
        "#ef4444", "#14b8a6", "#ec4899", "#c8ff5a",
    ]

    init(
        account: SavingsAccount?,
        isSaving: Bool = false,
        onSave: @escaping (_ name: String, _ color: String, _ targetAmountCents: Int?, _ targetDate: String?) -> Void
    ) {
        self.account = account
        self.isSaving = isSaving
        self.onSave = onSave
        let hex = account?.color ?? "#22c55e"
        _name = State(initialValue: account?.name ?? "")
        _colorHex = State(initialValue: hex)
        _pickedColor = State(initialValue: Color(hex: hex))
        _targetAmountText = State(initialValue: account.map { String(format: "%.2f", Double($0.targetAmountCents ?? 0) / 100.0) } ?? "")
        _targetDate = State(initialValue: Self.parseDate(account?.targetDate))
        _hasTargetDate = State(initialValue: account?.targetDate != nil)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()

                ScrollView {
                VStack(spacing: 20) {
                    FormCard {
                        FormTextRow(
                            label: "Name",
                            placeholder: "Cajita Nu, Revolut…",
                            text: $name,
                            focus: $nameFocused
                        )
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Color")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                            .textCase(.uppercase)
                            .tracking(0.6)

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                            ForEach(Self.presets, id: \.self) { hex in
                                Button {
                                    colorHex = hex
                                    pickedColor = Color(hex: hex)
                                } label: {
                                    ZStack {
                                        Circle()
                                            .fill(Color(hex: hex))
                                            .frame(width: 40, height: 40)
                                        if colorHex.lowercased() == hex.lowercased() {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 14, weight: .bold))
                                                .foregroundStyle(Theme.bg)
                                        }
                                    }
                                    .frame(width: 44, height: 44)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Account color \(hex)")
                                .accessibilityValue(colorHex.lowercased() == hex.lowercased() ? "Selected" : "Not selected")
                                .accessibilityAddTraits(colorHex.lowercased() == hex.lowercased() ? .isSelected : [])
                            }
                        }

                        ColorPicker("Custom", selection: $pickedColor, supportsOpacity: false)
                            .foregroundStyle(Theme.ink)
                            .onChange(of: pickedColor) { _, newValue in
                                colorHex = newValue.toHex() ?? colorHex
                            }
                            .padding(.top, 4)
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Theme.surface)
                            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.line, lineWidth: 1))
                    )

                    goalSection

                    Button {
                        let trimmed = name.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty, !isSaving else { return }
                        do {
                            let target = try parseSavingsTargetAmount(targetAmountText.replacingOccurrences(of: ",", with: "."))
                            let date = target == nil || !hasTargetDate ? nil : Self.formatDate(targetDate)
                            errorMessage = nil
                            onSave(trimmed, colorHex, target, date)
                        } catch {
                            errorMessage = "Enter a positive target amount within the supported range, or leave it blank."
                        }
                    } label: {
                        if isSaving {
                            ProgressView().tint(Theme.bg)
                        } else {
                            Text(isEditing ? "Save Changes" : "Create Account")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.expense)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 40)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(isEditing ? "Edit Account" : "New Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.muted)
                        .disabled(isSaving)
                }
            }
            .onAppear { nameFocused = true }
        }
        .interactiveDismissDisabled(isSaving)
    }

    private var goalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionEyebrow("GOAL", color: Theme.muted)
                Spacer()
                Text("Optional")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.faint)
            }
            HStack(spacing: 8) {
                Text("Target amount")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.muted)
                Spacer()
                Text("$").foregroundStyle(Theme.accentText)
                TextField("0.00", text: $targetAmountText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 120)
            }
            .frame(minHeight: 44)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }

            Toggle(isOn: $hasTargetDate) {
                Text("Target date")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.muted)
            }
            .tint(Theme.accent)
            .frame(minHeight: 44)

            if hasTargetDate {
                DatePicker("Date", selection: $targetDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .tint(Theme.accent)
            }

            Text("Leave the target amount blank for a flexible account.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.faint)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.surface)
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.line, lineWidth: 1))
        )
    }

    private static func parseDate(_ raw: String?) -> Date {
        guard let raw else { return Date() }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: raw) ?? Date()
    }

    private static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

private func accountGoalStatus(_ account: SavingsAccount) -> String {
    switch account.goalStatus {
    case "funded": return "Funded"
    case "past_due": return "Past due"
    case "in_progress": return "In progress"
    case "not_started", nil: return "Not started"
    default: return "Status unavailable"
    }
}

private extension Color {
    func toHex() -> String? {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard ui.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}

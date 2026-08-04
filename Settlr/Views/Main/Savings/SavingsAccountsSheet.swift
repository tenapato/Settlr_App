import SwiftUI
import UIKit

struct SavingsAccountsSheet: View {
    let workspaceId: String
    @Bindable var vm: SavingsVM
    @Environment(\.dismiss) private var dismiss

    @State private var showAccountForm = false
    @State private var editingAccount: SavingsAccount?
    @State private var accountToDelete: SavingsAccount?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()

                if vm.accounts.isEmpty {
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
                    }
                }
            }
            .sheet(isPresented: $showAccountForm) {
                SavingsAccountFormSheet(
                    account: editingAccount,
                    onSave: { name, color in
                        Task {
                            let ok: Bool
                            if let editingAccount {
                                ok = await vm.updateAccount(
                                    workspaceId: workspaceId,
                                    accountId: editingAccount.id,
                                    name: name,
                                    color: color
                                )
                            } else {
                                ok = await vm.createAccount(
                                    workspaceId: workspaceId,
                                    name: name,
                                    color: color
                                )
                            }
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
                            Task { await vm.deleteAccount(workspaceId: workspaceId, accountId: account.id) }
                            accountToDelete = nil
                        },
                        onCancel: { accountToDelete = nil }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .animation(.easeOut(duration: 0.2), value: accountToDelete != nil)
        }
        .preferredColorScheme(.dark)
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

    private var accountList: some View {
        List {
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
                    }

                    Spacer()

                    Button {
                        editingAccount = account
                        showAccountForm = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)

                    Button {
                        accountToDelete = account
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.expense)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
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
    let onSave: (_ name: String, _ color: String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var colorHex: String
    @State private var pickedColor: Color
    @FocusState private var nameFocused: Bool

    private var isEditing: Bool { account != nil }

    private static let presets = [
        "#22c55e", "#3b82f6", "#a855f7", "#f59e0b",
        "#ef4444", "#14b8a6", "#ec4899", "#c8ff5a",
    ]

    init(account: SavingsAccount?, onSave: @escaping (_ name: String, _ color: String) -> Void) {
        self.account = account
        self.onSave = onSave
        let hex = account?.color ?? "#22c55e"
        _name = State(initialValue: account?.name ?? "")
        _colorHex = State(initialValue: hex)
        _pickedColor = State(initialValue: Color(hex: hex))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()

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
                                }
                                .buttonStyle(.plain)
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

                    Button(isEditing ? "Save Changes" : "Create Account") {
                        let trimmed = name.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        onSave(trimmed, colorHex)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)

                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }
            .navigationTitle(isEditing ? "Edit Account" : "New Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.muted)
                }
            }
            .onAppear { nameFocused = true }
        }
        .preferredColorScheme(.dark)
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

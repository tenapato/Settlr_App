import SwiftUI

struct SavingsView: View {
    let workspaceId: String
    @Binding var showForm: Bool
    var embedded: Bool = false
    @State private var vm = SavingsVM()
    @State private var showManageAccounts = false
    @State private var showRecurring = false
    @State private var entryToEdit: SavingsEntry?
    @State private var entryToDelete: SavingsEntry?

    var body: some View {
        Group {
            if embedded {
                savingsBody
            } else {
                NavigationStack {
                    savingsBody
                        .navigationTitle("Savings")
                        .navigationBarTitleDisplayMode(.large)
                }
            }
        }
        .preferredColorScheme(.dark)
        .task { await vm.load(workspaceId: workspaceId) }
        .onChange(of: vm.selectedAccountId) { _, _ in
            Task { await vm.load(workspaceId: workspaceId) }
        }
        .onChange(of: showForm) { _, open in
            guard open else { return }
            // Only divert to account creation once we know the workspace really has no
            // accounts. Checking mid-load sent every "Add savings" tap to Manage Accounts.
            Task {
                await vm.awaitCurrentLoad()
                if vm.hasLoadedAccounts && vm.accounts.isEmpty {
                    showForm = false
                    showManageAccounts = true
                }
            }
        }
    }

    private var savingsBody: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                balanceHeader
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)

                if !vm.accounts.isEmpty {
                    accountChips
                        .padding(.bottom, 12)
                }

                if vm.isLoading {
                    Spacer()
                    ProgressView().tint(Theme.accent)
                    Spacer()
                } else if vm.accounts.isEmpty {
                    noAccountsState
                } else if vm.filteredEntries.isEmpty {
                    noEntriesState
                } else {
                    entriesList
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        if !vm.accounts.isEmpty {
                            Button { showRecurring = true } label: {
                                Image(systemName: vm.activeRecurringCount > 0
                                    ? "arrow.trianglehead.2.clockwise.rotate.90.circle.fill"
                                    : "arrow.trianglehead.2.clockwise.rotate.90")
                                    .foregroundStyle(Theme.accent)
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            Button { showManageAccounts = true } label: {
                                Image(systemName: "slider.horizontal.3")
                                    .foregroundStyle(Theme.accent)
                                    .font(.system(size: 16, weight: .semibold))
                            }
                        }
                    // Always ask for an entry; the showForm handler diverts to account
                    // creation only if the workspace is confirmed to have no accounts.
                    Button { showForm = true } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(Theme.accent)
                            .font(.system(size: 18, weight: .semibold))
                    }
                }
            }
        }
        .sheet(isPresented: $showForm) {
            SavingsEntryFormSheet(
                workspaceId: workspaceId,
                accounts: vm.accounts,
                defaultAccountId: vm.selectedAccountId,
                onSave: { body in
                    Task { await vm.createEntry(workspaceId: workspaceId, body: body) }
                }
            )
        }
        .sheet(item: $entryToEdit) { entry in
            SavingsEntryFormSheet(
                workspaceId: workspaceId,
                accounts: vm.accounts,
                entry: entry,
                onSave: { body in
                    Task { await vm.updateEntry(workspaceId: workspaceId, entryId: entry.id, body: body) }
                }
            )
        }
            .sheet(isPresented: $showManageAccounts) {
                SavingsAccountsSheet(workspaceId: workspaceId, vm: vm)
            }
            .sheet(isPresented: $showRecurring) {
                SavingsRecurringSheet(workspaceId: workspaceId, vm: vm)
            }
        .overlay {
            if let entry = entryToDelete {
                DeleteConfirmDialog(
                    title: "Delete Entry?",
                    itemName: entry.description,
                    onConfirm: {
                        Task { await vm.deleteEntry(workspaceId: workspaceId, entryId: entry.id) }
                        entryToDelete = nil
                    },
                    onCancel: { entryToDelete = nil }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(.easeOut(duration: 0.2), value: entryToDelete != nil)
    }

    // MARK: - Balance header

    private var balanceHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(vm.selectedAccountId == nil ? "Total balance" : "Account balance")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.faint)
                .textCase(.uppercase)
                .tracking(0.8)

            AmountLabel(
                cents: vm.displayBalanceCents,
                font: .system(size: 34, weight: .bold, design: .rounded)
            )
            .foregroundStyle(Theme.ink)
            .contentTransition(.numericText())
            .animation(.snappy(duration: 0.25), value: vm.displayBalanceCents)

            Text("Transfers do not affect Net")
                .font(.system(size: 12))
                .foregroundStyle(Theme.faint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    // MARK: - Account chips

    private var accountChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                accountChip(
                    title: "All",
                    color: nil,
                    balanceCents: vm.totalBalanceCents,
                    selected: vm.selectedAccountId == nil
                ) {
                    vm.selectedAccountId = nil
                }

                ForEach(vm.accounts) { account in
                    accountChip(
                        title: account.name,
                        color: account.color,
                        balanceCents: account.balanceCents,
                        selected: vm.selectedAccountId == account.id
                    ) {
                        vm.selectedAccountId = account.id
                    }
                }
            }
            .padding(.horizontal, 24)
        }
    }

    private func accountChip(
        title: String,
        color: String?,
        balanceCents: Int,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let color {
                    Circle()
                        .fill(Color(hex: color))
                        .frame(width: 8, height: 8)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(selected ? Theme.bg : Theme.ink)
                        .lineLimit(1)
                    AmountLabel(cents: balanceCents, font: .system(size: 11, weight: .medium))
                        .foregroundStyle(selected ? Theme.bg.opacity(0.7) : Theme.muted)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(selected ? Theme.accent : Theme.surface2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(selected ? Color.clear : Theme.line, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Entries list

    private var entriesList: some View {
        List {
            ForEach(groupByDay(vm.filteredEntries, date: { $0.occurredAt }, cents: { $0.amountCents })) { section in
                Section {
                    ForEach(section.items) { entry in
                        LedgerSwipeRow(
                            onTap: { entryToEdit = entry },
                            onEdit: { entryToEdit = entry },
                            onDelete: { entryToDelete = entry }
                        ) {
                            SavingsEntryRow(
                                entry: entry,
                                account: vm.account(for: entry.accountId),
                                showAccount: vm.selectedAccountId == nil
                            )
                        }
                        .listRowBackground(Theme.surface)
                        .listRowSeparatorTint(Theme.line)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    }
                } header: {
                    DaySectionHeader(title: section.title, subtotalCents: section.subtotalCents)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                }
            }

            HStack {
                let count = vm.filteredEntries.count
                Text("\(count) entr\(count == 1 ? "y" : "ies")")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.faint)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            Spacer().frame(height: 100)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await vm.load(workspaceId: workspaceId) }
    }

    // MARK: - Empty states

    private var noAccountsState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "banknote")
                .font(.system(size: 36))
                .foregroundStyle(Theme.faint)
            Text("No savings accounts yet")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.muted)
            Text("Track yield accounts like Cajita Nu or Revolut.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.faint)
                .multilineTextAlignment(.center)
            Button { showManageAccounts = true } label: {
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
        .padding(.horizontal, 32)
    }

    private var noEntriesState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 36))
                .foregroundStyle(Theme.faint)
            Text("No entries yet")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.muted)
            Button { showForm = true } label: {
                Text("Add deposit or withdrawal")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.bg)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Theme.accent)
                    .clipShape(Capsule())
            }
            Spacer()
        }
        .padding(.horizontal, 32)
    }
}

// MARK: - Entry row

private struct SavingsEntryRow: View {
    let entry: SavingsEntry
    let account: SavingsAccount?
    let showAccount: Bool

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill((entry.isDeposit ? Theme.income : Theme.expense).opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: entry.isDeposit ? "arrow.down.left" : "arrow.up.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(entry.isDeposit ? Theme.income : Theme.expense)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.description)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(entry.isDeposit ? "Deposit" : "Withdrawal")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(entry.isDeposit ? Theme.income : Theme.expense)

                    if entry.isRecurring {
                        Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.faint)
                    }

                    if showAccount, let account {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color(hex: account.color ?? "#22c55e"))
                                .frame(width: 6, height: 6)
                            Text(account.name)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Theme.faint)
                                .lineLimit(1)
                        }
                    }
                }
            }

            Spacer()

            AmountLabel(cents: entry.amountCents, font: .system(size: 15, weight: .semibold))
                .foregroundStyle(entry.isDeposit ? Theme.income : Theme.expense)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Theme.surface)
    }
}

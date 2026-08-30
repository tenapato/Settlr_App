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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        .task { await vm.load(workspaceId: workspaceId) }
        .onChange(of: vm.selectedAccountId) { _, _ in
            Task { await vm.load(workspaceId: workspaceId) }
        }
        .onChange(of: showForm) { _, open in
            guard open else { return }
            // Only divert to account creation once we know the workspace really has no
            // accounts. Checking mid-load sent every "Add savings" tap to Manage Accounts.
            Task {
                if vm.isLoading && vm.loadedWorkspaceID == workspaceId {
                    await vm.awaitCurrentLoad()
                } else if vm.loadedWorkspaceID != workspaceId || !vm.accountsRequestIsSettled(for: workspaceId) {
                    await vm.load(workspaceId: workspaceId)
                } else {
                    await vm.awaitCurrentLoad()
                }
                guard vm.accountsRequestIsSettled(for: workspaceId), vm.hasLoadedAccounts else {
                    showForm = false
                    return
                }
                guard vm.accountsErrorMessage == nil, !vm.accounts.isEmpty else {
                    showForm = false
                    showManageAccounts = true
                    return
                }
            }
        }
    }

    private var savingsBody: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            if vm.isLoading && vm.accounts.isEmpty && !vm.hasLoadedAccounts {
                SettlrPulseLoadingView(message: "Getting your savings")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.accounts.isEmpty && vm.accountsErrorMessage != nil && !vm.hasLoadedAccounts {
                accountsErrorState
            } else if vm.accounts.isEmpty && vm.hasLoadedAccounts {
                noAccountsState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        balanceHeader
                        if vm.isLoading || vm.accountsErrorMessage != nil || vm.entriesErrorMessage != nil {
                            recoveryBanner
                        }
                        if !vm.accounts.isEmpty { accountChips }
                        accountObjects
                        recentEntries
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 120)
                }
                .refreshable { await vm.load(workspaceId: workspaceId) }
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
                                    .frame(width: 44, height: 44)
                            }
                            .accessibilityLabel("Manage recurring savings")
                            Button { showManageAccounts = true } label: {
                                Image(systemName: "slider.horizontal.3")
                                    .foregroundStyle(Theme.accent)
                                    .font(.system(size: 16, weight: .semibold))
                                    .frame(width: 44, height: 44)
                            }
                            .accessibilityLabel("Manage savings accounts")
                        }
                    // Always ask for an entry; the showForm handler diverts to account
                    // creation only if the workspace is confirmed to have no accounts.
                    Button { showForm = true } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(Theme.accent)
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Add savings entry")
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
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: entryToDelete != nil)
    }

    // MARK: - Balance header

    private var balanceHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
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
            .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: vm.displayBalanceCents)

            HStack(spacing: 20) {
                metric(label: "This month", cents: monthMovementCents, tint: monthMovementCents >= 0 ? Theme.income : Theme.expense)
                metric(label: "Accounts", text: "\(vm.accounts.count)", tint: Theme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    private func metric(label: String, cents: Int? = nil, text: String? = nil, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            SectionEyebrow(label, color: Theme.faint)
            if let cents {
                AmountLabel(cents: cents, font: .system(size: 16, weight: .semibold))
                    .foregroundStyle(tint)
            } else {
                Text(text ?? "—")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(tint)
            }
        }
    }

    private var monthMovementCents: Int {
        let calendar = Calendar.current
        let now = Date()
        let source = vm.selectedAccountId == nil ? vm.entries : vm.filteredEntries
        return source.reduce(into: 0) { result, entry in
            guard let date = Self.date(from: entry.occurredAt),
                  calendar.component(.year, from: date) == calendar.component(.year, from: now),
                  calendar.component(.month, from: date) == calendar.component(.month, from: now) else { return }
            result += entry.isDeposit ? entry.amountCents : -entry.amountCents
        }
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

    private var accountObjects: some View {
        VStack(alignment: .leading, spacing: 10) {
            let goals = vm.accounts.filter { $0.targetAmountCents != nil }
            let flexible = vm.accounts.filter { $0.targetAmountCents == nil }
            if !goals.isEmpty {
                SectionEyebrow("YOUR GOALS", color: Theme.faint)
                ForEach(goals) { account in
                    Button { vm.selectedAccountId = account.id } label: {
                        SavingsGoalCard(account: account, isSelected: vm.selectedAccountId == account.id)
                    }
                    .buttonStyle(.plain)
                }
            }
            if !flexible.isEmpty {
                SectionEyebrow("FLEXIBLE SAVINGS", color: Theme.faint)
                    .padding(.top, goals.isEmpty ? 0 : 8)
                ForEach(flexible) { account in
                    Button { vm.selectedAccountId = account.id } label: {
                        FlexibleSavingsCard(account: account, isSelected: vm.selectedAccountId == account.id)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var recentEntries: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionEyebrow("RECENT ENTRIES", color: Theme.faint)
                Spacer()
                if vm.selectedAccountId != nil {
                    Button("All") { vm.selectedAccountId = nil }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.accentText)
                }
            }
            if vm.filteredEntries.isEmpty {
                noEntriesState
                    .frame(minHeight: 170)
            } else {
                ForEach(Array(vm.filteredEntries.prefix(12))) { entry in
                    LedgerSwipeRow(
                        onTap: { entryToEdit = entry },
                        onEdit: { entryToEdit = entry },
                        onDelete: { entryToDelete = entry }
                    ) {
                        SavingsEntryRow(entry: entry, account: vm.account(for: entry.accountId), showAccount: vm.selectedAccountId == nil)
                    }
                    .background(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private var recoveryBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            SignalTraceLoadingView(lastUpdated: nil)
            if vm.accountsErrorMessage != nil || vm.entriesErrorMessage != nil {
                Text("Couldn’t refresh all savings data. Showing your last saved data.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.warning)
                Text(vm.accountsErrorMessage ?? vm.entriesErrorMessage ?? "")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.faint)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Savings refresh incomplete. Showing your last saved data.")
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
                        .foregroundStyle(selected ? Theme.buttonInk : Theme.ink)
                        .lineLimit(1)
                    AmountLabel(cents: balanceCents, font: .system(size: 11, weight: .medium))
                        .foregroundStyle(selected ? Theme.buttonInk.opacity(0.7) : Theme.muted)
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
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - Entries list

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
                    .foregroundStyle(Theme.buttonInk)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Theme.accent)
                    .clipShape(Capsule())
                    .frame(minHeight: 44)
            }
            Spacer()
        }
        .padding(.horizontal, 32)
    }

    private var accountsErrorState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 32))
                .foregroundStyle(Theme.warning)
            Text("Savings accounts unavailable")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Text("We couldn’t load this workspace’s accounts. Try again before creating an account.")
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
                    .foregroundStyle(Theme.buttonInk)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Theme.accent)
                    .clipShape(Capsule())
                    .frame(minHeight: 44)
            }
            Spacer()
        }
        .padding(.horizontal, 32)
    }

    private static func date(from raw: String) -> Date? {
        for format in ["yyyy-MM-dd'T'HH:mm:ss.SSSZ", "yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd"] {
            let formatter = DateFormatter()
            formatter.dateFormat = format
            if let date = formatter.date(from: raw) { return date }
        }
        return nil
    }
}

private struct FlexibleSavingsCard: View {
    let account: SavingsAccount
    let isSelected: Bool

    var body: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(Color(hex: account.color ?? "#c8ff5a"))
                        .frame(width: 10, height: 10)
                    Text(account.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "chevron.right")
                        .foregroundStyle(isSelected ? Theme.accentText : Theme.faint)
                }
                HStack(alignment: .firstTextBaseline) {
                    AmountLabel(cents: account.balanceCents, font: .system(size: 25, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Text("Flexible")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.muted)
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isSelected ? Theme.accent.opacity(0.65) : Color.clear, lineWidth: 1)
        )
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Presents server-owned goal progress. Flexible accounts never render a
/// progress track, and funded status is read from goalStatus rather than
/// inferred from balances on the device.
struct SavingsGoalCard: View {
    let account: SavingsAccount
    var isSelected = false

    private var progress: Double {
        min(max((account.progressPct ?? 0) / 100.0, 0), 1)
    }

    private var statusLabel: String {
        switch account.goalStatus {
        case "funded": return "Funded"
        case "past_due": return "Past due"
        case "in_progress": return "In progress"
        case "not_started", nil: return "Not started"
        default: return "Status unavailable"
        }
    }

    var body: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(Color(hex: account.color ?? "#c8ff5a"))
                        .frame(width: 10, height: 10)
                    Text(account.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Text(statusLabel.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.7)
                        .foregroundStyle(account.goalStatus == "funded" ? Theme.income : Theme.accentText)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "chevron.right")
                        .foregroundStyle(isSelected ? Theme.accentText : Theme.faint)
                }
                HStack(alignment: .firstTextBaseline) {
                    AmountLabel(cents: account.balanceCents, font: .system(size: 25, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    if let target = account.targetAmountCents {
                        Text("of ")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.faint)
                        AmountLabel(cents: target, font: .system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.muted)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(statusLabel)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(account.goalStatus == "funded" ? Theme.income : Theme.accentText)
                        Spacer()
                        if let progressPct = account.progressPct {
                            Text("\(progressPct.formatted(.number.precision(.fractionLength(0...1))))%")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundStyle(Theme.ink)
                        }
                    }
                    GeometryReader { proxy in
                        Capsule()
                            .fill(Theme.line)
                            .overlay(alignment: .leading) {
                                Capsule()
                                    .fill(account.goalStatus == "funded" ? Theme.income : Theme.accent)
                                    .frame(width: proxy.size.width * progress)
                            }
                    }
                    .frame(height: 5)
                    HStack(spacing: 14) {
                        if let remaining = account.remainingCents, remaining > 0 {
                            Text("\(AmountLabelText(cents: remaining)) remaining")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.muted)
                        } else if account.goalStatus == "funded" {
                            Text("Target reached")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.income)
                        }
                        if let targetDate = account.targetDate {
                            Text("by \(targetDate.prefix(10))")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.faint)
                        }
                    }
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isSelected ? Theme.accent.opacity(0.65) : Color.clear, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Savings goal for \(account.name)")
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var accessibilityValue: String {
        var parts = ["\(account.progressPct ?? 0) percent", statusLabel]
        if let remaining = account.remainingCents, remaining > 0 {
            parts.append("\(AmountLabelText(cents: remaining)) remaining")
        }
        if let targetDate = account.targetDate {
            parts.append("Target date \(targetDate.prefix(10))")
        }
        return parts.joined(separator: ", ")
    }
}

private func AmountLabelText(cents: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 2
    formatter.maximumFractionDigits = 2
    let number = formatter.string(from: NSNumber(value: Double(cents) / 100.0)) ?? "0.00"
    return "MXN $\(number)"
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

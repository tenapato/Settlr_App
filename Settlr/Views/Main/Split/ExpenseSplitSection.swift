import SwiftUI

/// Shown on an expense that mirrors a bill split.
///
/// What the expense means depends on who paid, and the two answers are not
/// variations on a phrase — they are different amounts of money:
///
/// - `me` — you fronted the whole bill, so the expense is the whole bill and on
///   its own it overstates what the meal cost you. The paybacks land separately
///   as income, and the number worth showing is what's left after them.
/// - `each_own` — everyone settled with the restaurant directly, so the expense
///   is only ever your share. Nobody owes you anything, and showing a "paid you
///   back" progress line here would invent a debt that does not exist.
struct ExpenseSplitSection: View {
    let workspaceId: String
    let splitId: String

    @State private var vm = BillSplitVM()
    @State private var isExpanded = false
    @State private var showFullSplit = false

    private var split: BillSplit? { vm.detail?.id == splitId ? vm.detail : nil }

    var body: some View {
        VStack(spacing: 0) {
            header
            if isExpanded {
                if let split {
                    detail(split)
                } else if vm.isLoading {
                    ProgressView()
                        .tint(Theme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                } else {
                    Text(vm.errorMessage ?? "Couldn't load this split.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Theme.line, lineWidth: 1)
                )
        )
        .sheet(isPresented: $showFullSplit) {
            NavigationStack {
                SplitDetailView(workspaceId: workspaceId, splitId: splitId, vm: vm)
            }
            .preferredColorScheme(.dark)
        }
        .task { await load() }
    }

    private var header: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            if isExpanded, split == nil { Task { await load() } }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Theme.accent.opacity(0.14)).frame(width: 32, height: 32)
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bill split")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.faint)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var subtitle: String {
        guard let split else { return "Tap to see how this was split" }
        let guests = split.guests
        if split.isEachOwn {
            // No debt to report on, so the useful fact is the size of the table.
            return guests.isEmpty
                ? "Everyone paid their own share"
                : "Split \(split.participants.count) ways · everyone paid their own"
        }
        let settled = guests.filter(\.isSettled).count
        if guests.isEmpty { return "Nobody has joined yet" }
        if settled == guests.count { return "Everyone settled up" }
        return "\(settled) of \(guests.count) paid you back"
    }

    @ViewBuilder
    private func detail(_ split: BillSplit) -> some View {
        VStack(spacing: 0) {
            Divider().overlay(Theme.line).padding(.leading, 16)

            // The number the ledger can't show on its own: bill minus paybacks.
            netRow(split)

            Divider().overlay(Theme.line).padding(.leading, 16)

            ForEach(split.participants) { person in
                if person.id != split.participants.first?.id {
                    Divider().overlay(Theme.line).padding(.leading, 16)
                }
                participantRow(split: split, person: person)
            }

            Divider().overlay(Theme.line).padding(.leading, 16)

            Button { showFullSplit = true } label: {
                HStack {
                    Text("Open split")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func netRow(_ split: BillSplit) -> some View {
        if split.isEachOwn { eachOwnRows(split) } else { paidItAllRows(split) }
    }

    /// You fronted the bill: the expense is the whole thing, and the number that
    /// matters is what it comes to once the paybacks are in.
    private func paidItAllRows(_ split: BillSplit) -> some View {
        let recovered = split.guests.filter(\.isSettled).reduce(0) { $0 + $1.owedCents }
        return VStack(spacing: 8) {
            amountRow("Bill total", split.totalCents, currency: split.currency)
            HStack {
                Text("Paid back to you").font(.system(size: 13)).foregroundStyle(Theme.muted)
                Spacer()
                Text("−\(formatSplitMoney(recovered, currency: split.currency))")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Theme.income)
            }
            emphasisRow("Your net cost", split.totalCents - recovered, currency: split.currency)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    /// Everyone paid the restaurant directly: only your share was ever your
    /// money, and that is the amount this expense records. The bill total is
    /// here as context for it, never as something you are owed back.
    private func eachOwnRows(_ split: BillSplit) -> some View {
        let yours = split.organizer?.owedCents ?? 0
        return VStack(spacing: 8) {
            amountRow("Bill total", split.totalCents, currency: split.currency)
            amountRow("Paid by everyone else", max(0, split.totalCents - yours), currency: split.currency)
            emphasisRow("Your share", yours, currency: split.currency)
            Text("Only your share was recorded as an expense.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.faint)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func amountRow(_ label: String, _ cents: Int, currency: String) -> some View {
        HStack {
            Text(label).font(.system(size: 13)).foregroundStyle(Theme.muted)
            Spacer()
            Text(formatSplitMoney(cents, currency: currency))
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(Theme.ink)
        }
    }

    private func emphasisRow(_ label: String, _ cents: Int, currency: String) -> some View {
        HStack {
            Text(label).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink)
            Spacer()
            Text(formatSplitMoney(cents, currency: currency))
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.accent)
        }
    }

    private func participantRow(split: BillSplit, person: BillSplitParticipant) -> some View {
        // On an `each_own` split nobody is behind on anything, so no row is
        // marked as owing and none of them is dimmed as "already handled".
        let isDebt = !split.isEachOwn && !person.isOrganizer && !person.isSettled
        let isDone = split.isEachOwn || person.isSettled

        return HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(isDone ? Theme.income.opacity(0.16) : Theme.surface2)
                    .frame(width: 26, height: 26)
                Text(splitInitials(person.name))
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(isDone ? Theme.income : Theme.muted)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(person.name)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text(status(split: split, person: person))
                    .font(.system(size: 11))
                    .foregroundStyle(isDebt ? Theme.warning : Theme.faint)
            }
            Spacer(minLength: 4)
            Text(formatSplitMoney(person.owedCents, currency: split.currency))
                .font(.system(size: 14, design: .monospaced))
                .foregroundStyle(person.isOrganizer || !isDone ? Theme.ink : Theme.faint)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    private func status(split: BillSplit, person: BillSplitParticipant) -> String {
        if split.isEachOwn {
            return person.isOrganizer ? "Your share" : "Paid their own"
        }
        if person.isOrganizer { return "Paid the bill" }
        return person.isSettled ? "Settled" : "Owes you"
    }

    private func load() async {
        await vm.loadDetail(workspaceId: workspaceId, splitId: splitId, silent: true)
    }
}

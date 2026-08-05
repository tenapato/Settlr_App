import SwiftUI

/// Shown on an expense that mirrors a bill split.
///
/// The expense is the whole bill, so on its own it overstates what the meal cost
/// you — the paybacks land separately as income. Expanding this says who is
/// covering which part of it, and how much has actually come back.
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
        guard let split else { return "Tap to see who owes what" }
        let guests = split.guests
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

    private func netRow(_ split: BillSplit) -> some View {
        let recovered = split.guests.filter(\.isSettled).reduce(0) { $0 + $1.owedCents }
        return VStack(spacing: 8) {
            HStack {
                Text("Bill total").font(.system(size: 13)).foregroundStyle(Theme.muted)
                Spacer()
                Text(formatSplitMoney(split.totalCents, currency: split.currency))
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Theme.ink)
            }
            HStack {
                Text("Paid back to you").font(.system(size: 13)).foregroundStyle(Theme.muted)
                Spacer()
                Text("−\(formatSplitMoney(recovered, currency: split.currency))")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Theme.income)
            }
            HStack {
                Text("Your net cost").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink)
                Spacer()
                Text(formatSplitMoney(split.totalCents - recovered, currency: split.currency))
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func participantRow(split: BillSplit, person: BillSplitParticipant) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(person.isSettled ? Theme.income.opacity(0.16) : Theme.surface2)
                    .frame(width: 26, height: 26)
                Text(splitInitials(person.name))
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(person.isSettled ? Theme.income : Theme.muted)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(person.name)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text(person.isOrganizer ? "Paid the bill" : (person.isSettled ? "Settled" : "Owes you"))
                    .font(.system(size: 11))
                    .foregroundStyle(person.isSettled || person.isOrganizer ? Theme.faint : Theme.warning)
            }
            Spacer(minLength: 4)
            Text(formatSplitMoney(person.owedCents, currency: split.currency))
                .font(.system(size: 14, design: .monospaced))
                .foregroundStyle(person.isSettled ? Theme.faint : Theme.ink)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    private func load() async {
        await vm.loadDetail(workspaceId: workspaceId, splitId: splitId, silent: true)
    }
}

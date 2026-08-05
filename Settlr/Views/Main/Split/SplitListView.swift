import SwiftUI

/// Entry point for the split feature, presented from the `+` quick actions.
struct SplitListView: View {
    let workspaceId: String
    /// Opens straight to this split — used right after one is created.
    var initialSplitId: String?

    @Environment(\.dismiss) private var dismiss
    @State private var vm = BillSplitVM()
    @State private var showCreate = false
    @State private var openSplitId: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()

                if vm.isLoading && !vm.hasLoaded {
                    ProgressView().tint(Theme.accent)
                } else if vm.splits.isEmpty && vm.hasLoaded {
                    emptyState
                } else {
                    splitList
                }
            }
            .navigationTitle("Bill Splits")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }.foregroundStyle(Theme.muted)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showCreate = true } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
            .navigationDestination(item: $openSplitId) { id in
                SplitDetailView(workspaceId: workspaceId, splitId: id, vm: vm)
            }
            .fullScreenCover(isPresented: $showCreate) {
                SplitScanFlow(workspaceId: workspaceId) { created in
                    openSplitId = created.id
                    Task { await vm.load(workspaceId: workspaceId) }
                }
            }
        }
        .preferredColorScheme(.dark)
        .task {
            if openSplitId == nil { openSplitId = initialSplitId }
            await vm.load(workspaceId: workspaceId)
        }
    }

    private var splitList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if let error = vm.errorMessage {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.expense)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(vm.splits) { split in
                    Button { openSplitId = split.id } label: { row(split) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .refreshable { await vm.load(workspaceId: workspaceId) }
    }

    private func row(_ split: BillSplitSummary) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(split.merchant)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(formatSplitDate(split.occurredAt))
                    Text("·")
                    Text("\(split.participantCount) people")
                }
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Text(formatSplitMoney(split.totalCents, currency: split.currency))
                    .font(.system(size: 16, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.ink)
                statusChip(split)
            }
        }
        .padding(14)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.line, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func statusChip(_ split: BillSplitSummary) -> some View {
        let (label, color): (String, Color) = {
            switch split.status {
            case "settled": return ("All settled", Theme.income)
            case "locked":
                let owed = split.outstandingCents ?? 0
                return owed > 0
                    ? ("\(formatSplitMoney(owed, currency: split.currency)) owed", Theme.warning)
                    : ("Collecting", Theme.warning)
            default: return ("Claiming", Theme.accent)
            }
        }()
        Text(label)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.14))
            .clipShape(Capsule())
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.2")
                .font(.system(size: 36))
                .foregroundStyle(Theme.faint)
            Text("No bill splits yet")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.muted)
            Text("Scan a receipt, pick what you ordered, and send everyone else a link.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.faint)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button { showCreate = true } label: {
                Text("Split a bill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.bg)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Theme.accent)
                    .clipShape(Capsule())
            }
            .padding(.top, 4)
        }
    }
}

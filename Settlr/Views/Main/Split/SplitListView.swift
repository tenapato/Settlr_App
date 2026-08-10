import SwiftUI

/// Entry point for the split feature, presented from the `+` quick actions.
struct SplitListView: View {
    let workspaceId: String
    /// Opens straight to this split — used right after one is created.
    var initialSplitId: String?

    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @State private var vm = BillSplitVM()
    @State private var showCreate = false
    @State private var openSplitId: String?
    @State private var discarding: PendingSplit?
    private let queue = PendingSplitQueue.shared
    private let network = NetworkMonitor.shared

    private var pending: [PendingSplit] {
        guard let userId = appState.currentUser?.id else { return [] }
        return queue.entries(userId: userId, workspaceId: workspaceId)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()

                // Anything waiting to upload is worth showing even when the
                // server list can't load — offline, that is the only content
                // there is, and the spinner would otherwise never end.
                if vm.isLoading && !vm.hasLoaded && pending.isEmpty {
                    ProgressView().tint(Theme.accent)
                } else if vm.splits.isEmpty && pending.isEmpty && vm.hasLoaded {
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
                SplitScanFlow(workspaceId: workspaceId) { outcome in
                    // A queued split has no server id, so there is nothing to
                    // open — it appears in the pending section instead.
                    if case .created(let split) = outcome { openSplitId = split.id }
                    Task { await vm.load(workspaceId: workspaceId) }
                }
            }
            .confirmationDialog(
                "Discard this split?",
                isPresented: Binding(get: { discarding != nil }, set: { if !$0 { discarding = nil } }),
                titleVisibility: .visible
            ) {
                Button("Discard", role: .destructive) {
                    if let discarding { queue.remove(discarding.id) }
                    discarding = nil
                }
                Button("Keep", role: .cancel) { discarding = nil }
            } message: {
                Text("It hasn't uploaded yet, so it will be gone for good.")
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
                if !network.isOnline {
                    offlineBanner
                } else if let error = vm.errorMessage {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.expense)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !pending.isEmpty { pendingSection }

                ForEach(vm.splits) { split in
                    Button { openSplitId = split.id } label: { row(split) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .refreshable {
            await syncPending()
            await vm.load(workspaceId: workspaceId)
        }
    }

    private var offlineBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash").font(.system(size: 12))
            Text("You're offline. New splits are saved here and upload themselves.")
                .font(.system(size: 12))
            Spacer(minLength: 0)
        }
        .foregroundStyle(Theme.muted)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Waiting to upload

    private var pendingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionEyebrow("Waiting to upload")
                Spacer()
                if network.isOnline {
                    Button("Sync now") { Task { await syncPending() } }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
            ForEach(pending) { entry in
                pendingRow(entry)
            }
        }
    }

    /// Deliberately not a navigation link: there is no split on the server yet,
    /// and `SplitDetailView` would spin forever on an id it can't fetch.
    private func pendingRow(_ entry: PendingSplit) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.body.merchant)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text(formatSplitDate(entry.body.occurredAt))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                if let reason = entry.blockedReason {
                    Text(reason.message)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.expense)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 6) {
                Text(formatSplitMoney(entry.body.totalCents))
                    .font(.system(size: 16, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.ink)
                pendingChip(entry)
            }
        }
        .padding(14)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(entry.blockedReason == nil ? Theme.line : Theme.expense.opacity(0.4), lineWidth: 1)
        )
        .contextMenu {
            if entry.blockedReason != nil {
                Button("Try again") {
                    queue.retry(entry.id)
                    Task { await syncPending() }
                }
            }
            Button("Discard", role: .destructive) { discarding = entry }
        }
    }

    @ViewBuilder
    private func pendingChip(_ entry: PendingSplit) -> some View {
        let (label, color): (String, Color) = {
            if entry.blockedReason != nil { return ("Needs attention", Theme.expense) }
            return network.isOnline ? ("Uploading…", Theme.accent) : ("Waiting for signal", Theme.warning)
        }()
        Text(label)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.14))
            .clipShape(Capsule())
    }

    private func syncPending() async {
        guard let userId = appState.currentUser?.id else { return }
        await queue.flush(userId: userId)
        await vm.load(workspaceId: workspaceId)
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

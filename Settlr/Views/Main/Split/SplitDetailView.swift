import SwiftUI
import UIKit

/// The organizer's view of one split: claim your own items, share the link, then
/// lock it and tick people off as they pay you back.
///
/// Locking is the hinge. While a split is open the shares move with every claim;
/// locking freezes them, and only then can a share be recorded as income — so a
/// number someone already paid can never change afterwards.
struct SplitDetailView: View {
    let workspaceId: String
    let splitId: String
    let vm: BillSplitVM

    @State private var confirmDelete = false
    @State private var copiedLink = false
    @State private var isRefreshing = false
    @State private var refreshSpin = 0.0
    @Environment(\.scenePhase) private var scenePhase
    @State private var participantToRemove: BillSplitParticipant?
    @Environment(\.dismiss) private var dismiss

    private var split: BillSplit? {
        vm.detail?.id == splitId ? vm.detail : nil
    }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            if let split {
                content(split)
            } else {
                ProgressView().tint(Theme.accent)
            }
        }
        .navigationTitle(split?.merchant ?? "Split")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { refresh() } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .rotationEffect(.degrees(refreshSpin))
                }
                .disabled(isRefreshing)
                .accessibilityLabel("Check for new claims")
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    if let link = split?.shareLink {
                        ShareLink(item: link.absoluteString) {
                            Label("Share link", systemImage: "square.and.arrow.up")
                        }
                        Button {
                            copyShareLink(link)
                        } label: {
                            Label(copiedLink ? "Copied" : "Copy link", systemImage: "doc.on.doc")
                        }
                    }
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Label("Delete split", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.ink)
                }
            }
        }
        .overlay {
            if confirmDelete, let split {
                DeleteConfirmDialog(
                    title: "Delete Split?",
                    itemName: "\(split.merchant) — the expense and any recorded paybacks go too",
                    onConfirm: {
                        confirmDelete = false
                        Task {
                            if await vm.delete(workspaceId: workspaceId, splitId: splitId) { dismiss() }
                        }
                    },
                    onCancel: { confirmDelete = false }
                )
            }
            if let participant = participantToRemove {
                DeleteConfirmDialog(
                    title: "Remove \(participant.name)?",
                    itemName: "Their claims go back into the pool",
                    onConfirm: {
                        participantToRemove = nil
                        Task {
                            await vm.removeParticipant(
                                workspaceId: workspaceId,
                                splitId: splitId,
                                participantId: participant.id
                            )
                        }
                    },
                    onCancel: { participantToRemove = nil }
                )
            }
        }
        .task { await vm.loadDetail(workspaceId: workspaceId, splitId: splitId) }
        // People claim on their own phones, so this screen has to keep up while
        // you watch it. Quiet refresh, foreground only.
        .task(id: splitId) {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if Task.isCancelled { return }
                guard scenePhase == .active else { continue }
                await vm.loadDetail(workspaceId: workspaceId, splitId: splitId, silent: true)
            }
        }
    }

    /// Explicit "have they claimed yet?" tap. Spins the glyph one full turn so a
    /// refresh that changes nothing still reads as having happened.
    private func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        withAnimation(.easeInOut(duration: 0.6)) { refreshSpin += 360 }
        Task {
            await vm.loadDetail(workspaceId: workspaceId, splitId: splitId, silent: true)
            try? await Task.sleep(nanoseconds: 300_000_000)
            isRefreshing = false
        }
    }

    private func content(_ split: BillSplit) -> some View {
        ScrollView {
            VStack(spacing: 18) {
                header(split)
                if let error = vm.errorMessage {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.expense)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if split.isOpen {
                    shareCard(split)
                    itemsSection(split)
                    peopleSection(split)
                } else {
                    collectProgress(split)
                    collectionSection(split)
                    closedItemsSection(split)
                }
                lockButton(split)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .refreshable { await vm.loadDetail(workspaceId: workspaceId, splitId: splitId) }
    }

    // MARK: - Header

    private func header(_ split: BillSplit) -> some View {
        VStack(spacing: 6) {
            Text(formatSplitMoney(split.totalCents, currency: split.currency))
                .font(.system(size: 34, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.ink)
            Text("\(formatSplitDate(split.occurredAt)) · \(split.participants.count) people")
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
            if !split.isOpen {
                let outstanding = split.outstandingCents
                Text(
                    outstanding > 0
                        ? "\(formatSplitMoney(outstanding, currency: split.currency)) still owed to you"
                        : "Everyone has settled up"
                )
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(outstanding > 0 ? Theme.warning : Theme.income)
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: - Share

    private func shareCard(_ split: BillSplit) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow("Invite the table")
            HStack(spacing: 10) {
                if let link = split.shareLink {
                    // Shared as a string, not a URL. `ShareLink(item: URL)` puts a
                    // `public.url` property list on the pasteboard, so "Copy" pastes
                    // `bplist00...` into anything reading plain text.
                    ShareLink(item: link.absoluteString) {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.up").font(.system(size: 15, weight: .semibold))
                            Text("Send link").font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundStyle(Theme.bg)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }

                    Button {
                        copyShareLink(link)
                    } label: {
                        Image(systemName: copiedLink ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(copiedLink ? Theme.income : Theme.ink)
                            .frame(width: 46, height: 44)
                            .background(Theme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Theme.line, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Copy link")
                }
            }
            Text("Anyone with the link picks their own items — no account, no install needed. It opens in the app if they have it.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.faint)
        }
    }

    /// Copies the link as plain text.
    ///
    /// Deliberately just `.string`. `UIPasteboard.items` only accepts property-list
    /// values, so including a `URL` under `public.url` makes the whole write fail
    /// silently and nothing gets copied. Plain text is also what we want: writing
    /// the URL type is what produced `bplist00…` when pasting into a text field.
    private func copyShareLink(_ link: URL) {
        UIPasteboard.general.string = link.absoluteString
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.easeOut(duration: 0.15)) { copiedLink = true }
        Task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            withAnimation(.easeOut(duration: 0.2)) { copiedLink = false }
        }
    }

    // MARK: - Collecting (locked / settled)

    /// How much of the table has actually paid up. Once claiming is closed this
    /// is the only number that changes, so it gets the space the invite card had.
    private func collectProgress(_ split: BillSplit) -> some View {
        let guests = split.guests
        let settled = guests.filter(\.isSettled).count
        let collected = guests.filter(\.isSettled).reduce(0) { $0 + $1.owedCents }
        let owed = guests.reduce(0) { $0 + $1.owedCents }
        let fraction = owed > 0 ? Double(collected) / Double(owed) : 1

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                SectionEyebrow("Collecting")
                Spacer()
                Text("\(settled) of \(guests.count) paid")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.muted)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.surface2)
                    Capsule()
                        .fill(fraction >= 1 ? Theme.income : Theme.accent)
                        .frame(width: max(0, geo.size.width * fraction))
                }
            }
            .frame(height: 6)
            HStack {
                Text("\(formatSplitMoney(collected, currency: split.currency)) collected")
                    .foregroundStyle(Theme.income)
                Spacer()
                Text("\(formatSplitMoney(owed - collected, currency: split.currency)) to go")
                    .foregroundStyle(owed - collected > 0 ? Theme.warning : Theme.faint)
            }
            .font(.system(size: 12, design: .monospaced))
        }
        .padding(14)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.line, lineWidth: 1)
        )
    }

    private func collectionSection(_ split: BillSplit) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionEyebrow("Who owes you")
            if split.guests.isEmpty {
                Text("Nobody joined this split, so there's nothing to collect.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.faint)
                    .padding(.horizontal, 4)
            } else {
                VStack(spacing: 10) {
                    ForEach(split.guests) { person in
                        debtorCard(split: split, person: person)
                    }
                }
            }
        }
    }

    /// One person's debt, with the two things you actually do about it: chase
    /// them, or record that they paid.
    private func debtorCard(split: BillSplit, person: BillSplitParticipant) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(person.isSettled ? Theme.income.opacity(0.16) : Theme.surface2)
                        .frame(width: 38, height: 38)
                    Text(splitInitials(person.name))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(person.isSettled ? Theme.income : Theme.muted)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(person.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Text(
                        person.isSettled
                            ? "Paid you back"
                            : "\(person.claimedItemIds.count) item\(person.claimedItemIds.count == 1 ? "" : "s")"
                    )
                    .font(.system(size: 12))
                    .foregroundStyle(person.isSettled ? Theme.income : Theme.faint)
                }
                Spacer(minLength: 4)
                Text(formatSplitMoney(person.owedCents, currency: split.currency))
                    .font(.system(size: 19, weight: .semibold, design: .monospaced))
                    .foregroundStyle(person.isSettled ? Theme.faint : Theme.ink)
                    .strikethrough(person.isSettled, color: Theme.faint)
            }

            if person.isSettled {
                Button {
                    setSettled(person, settled: false)
                } label: {
                    Text("Undo")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Theme.surface2)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(vm.isSaving)
            } else {
                HStack(spacing: 8) {
                    if let link = split.shareLink {
                        ShareLink(item: reminderText(split: split, person: person, link: link)) {
                            Text("Remind")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Theme.ink)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .background(Theme.surface2)
                                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                    }
                    Button {
                        setSettled(person, settled: true)
                    } label: {
                        Text("Mark paid")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.bg)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(Theme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(vm.isSaving)
                }
            }
        }
        .padding(14)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(person.isSettled ? Theme.income.opacity(0.3) : Theme.line, lineWidth: 1)
        )
        .contextMenu {
            if !person.isSettled {
                Button(role: .destructive) { participantToRemove = person } label: {
                    Label("Remove from split", systemImage: "person.badge.minus")
                }
            }
        }
    }

    /// A message that already says the amount, so chasing someone is one tap.
    private func reminderText(split: BillSplit, person: BillSplitParticipant, link: URL) -> String {
        """
        Hey \(person.name) — your share of \(split.merchant) comes to \(formatSplitMoney(person.owedCents, currency: split.currency)).
        \(link.absoluteString)
        """
    }

    private func setSettled(_ person: BillSplitParticipant, settled: Bool) {
        Task {
            await vm.setSettled(
                workspaceId: workspaceId,
                splitId: splitId,
                participantId: person.id,
                settled: settled
            )
        }
    }

    /// Items stay reachable once claiming closes, but folded away — the question
    /// on this screen is who owes what, not what was ordered.
    private func closedItemsSection(_ split: BillSplit) -> some View {
        DisclosureGroup {
            itemsCard(split).padding(.top, 8)
        } label: {
            HStack {
                SectionEyebrow("Items")
                Spacer()
                Text("\(split.items.count) · \(formatSplitMoney(split.totalCents, currency: split.currency))")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.muted)
            }
        }
        .tint(Theme.muted)
    }

    // MARK: - Items

    private func itemsSection(_ split: BillSplit) -> some View {
        let organizerId = split.organizer?.id
        let mine = Set(split.organizer?.claimedItemIds ?? [])
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionEyebrow(split.isOpen ? "Your items" : "Items")
                Spacer()
                if split.unclaimedItemsCents > 0 {
                    Text("\(formatSplitMoney(split.unclaimedItemsCents, currency: split.currency)) unclaimed")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.warning)
                }
            }

            itemsCard(split)
        }
    }

    private func itemsCard(_ split: BillSplit) -> some View {
        let organizerId = split.organizer?.id
        let mine = Set(split.organizer?.claimedItemIds ?? [])
        return VStack(spacing: 0) {
            ForEach(split.items) { item in
                if item.id != split.items.first?.id {
                    Rectangle().fill(Theme.line).frame(height: 1)
                }
                itemRow(split: split, item: item, mine: mine.contains(item.id), organizerId: organizerId)
            }
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.line, lineWidth: 1)
        )
    }

    private func itemRow(
        split: BillSplit,
        item: BillSplitItem,
        mine: Bool,
        organizerId: String?
    ) -> some View {
        let claimers = split.participants.filter { $0.claimedItemIds.contains(item.id) }
        return Button {
            guard split.isOpen else { return }
            Task {
                await vm.toggleClaim(
                    workspaceId: workspaceId,
                    splitId: splitId,
                    itemId: item.id,
                    claimed: !mine
                )
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: mine ? "checkmark.square.fill" : "square")
                    .font(.system(size: 19))
                    .foregroundStyle(mine ? Theme.accent : Theme.faint)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.quantity > 1 ? "\(item.quantity)× \(item.name)" : item.name)
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    if claimers.isEmpty {
                        Text("Unclaimed").font(.system(size: 11)).foregroundStyle(Theme.faint)
                    } else {
                        Text(
                            (claimers.count > 1 ? "Split \(claimers.count) ways · " : "")
                                + claimers.map(\.name).joined(separator: ", ")
                        )
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                    }
                }

                Spacer(minLength: 4)

                Text(formatSplitMoney(item.lineTotalCents, currency: split.currency))
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(Theme.ink)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!split.isOpen)
    }

    // MARK: - People

    private func peopleSection(_ split: BillSplit) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionEyebrow("Who owes what")

            VStack(spacing: 0) {
                ForEach(split.participants) { person in
                    if person.id != split.participants.first?.id {
                        Rectangle().fill(Theme.line).frame(height: 1)
                    }
                    personRow(split: split, person: person)
                }
            }
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.line, lineWidth: 1)
            )

            if split.isOpen && split.guests.isEmpty {
                Text("Nobody has joined yet. Send the link and their picks show up here.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.faint)
                    .padding(.horizontal, 4)
            }
        }
    }

    private func personRow(split: BillSplit, person: BillSplitParticipant) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Theme.surface2).frame(width: 32, height: 32)
                Text(splitInitials(person.name))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.muted)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(person.name)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text(
                    person.isOrganizer
                        ? "Paid the bill"
                        : "\(person.claimedItemIds.count) item\(person.claimedItemIds.count == 1 ? "" : "s")"
                )
                .font(.system(size: 11))
                .foregroundStyle(Theme.faint)
            }

            Spacer(minLength: 4)

            Text(formatSplitMoney(person.owedCents, currency: split.currency))
                .font(.system(size: 14, design: .monospaced))
                .foregroundStyle(person.isSettled ? Theme.income : Theme.ink)

            if !person.isOrganizer {
                settleControl(split: split, person: person)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contextMenu {
            if !person.isOrganizer && !person.isSettled {
                Button(role: .destructive) { participantToRemove = person } label: {
                    Label("Remove from split", systemImage: "person.badge.minus")
                }
            }
        }
    }

    @ViewBuilder
    private func settleControl(split: BillSplit, person: BillSplitParticipant) -> some View {
        if split.isOpen {
            // Shares are still moving; settling now would freeze a number that
            // the next claim would invalidate.
            Image(systemName: "lock.open")
                .font(.system(size: 13))
                .foregroundStyle(Theme.faint)
        } else {
            Button {
                Task {
                    await vm.setSettled(
                        workspaceId: workspaceId,
                        splitId: splitId,
                        participantId: person.id,
                        settled: !person.isSettled
                    )
                }
            } label: {
                Image(systemName: person.isSettled ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(person.isSettled ? Theme.income : Theme.faint)
            }
            .buttonStyle(.plain)
            .disabled(vm.isSaving)
        }
    }

    // MARK: - Lock / reopen

    @ViewBuilder
    private func lockButton(_ split: BillSplit) -> some View {
        VStack(spacing: 6) {
            Button {
                Task {
                    _ = await vm.setStatus(
                        workspaceId: workspaceId,
                        splitId: splitId,
                        status: split.isOpen ? "locked" : "open"
                    )
                }
            } label: {
                Text(split.isOpen ? "Close claiming & collect" : "Reopen for claiming")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(split.isOpen ? Theme.bg : Theme.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(split.isOpen ? Theme.accent : Theme.surface2)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .disabled(vm.isSaving)

            Text(
                split.isOpen
                    ? "Freezes everyone's share so you can start marking people as paid."
                    : "Un-settle everyone first if you need to change the items."
            )
            .font(.system(size: 12))
            .foregroundStyle(Theme.faint)
            .multilineTextAlignment(.center)
        }
    }
}

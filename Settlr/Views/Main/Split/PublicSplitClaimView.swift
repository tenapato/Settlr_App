import SwiftUI

/// What opens when someone taps `settlr://split/<token>` — a split *someone else*
/// organized, in a workspace this user has no access to.
///
/// It therefore talks to the public share-link API, exactly like the web page,
/// authorized by the share token plus a per-split claim secret. Having the app
/// installed is a nicer surface, not extra permission.
struct PublicSplitClaimView: View {
    let shareToken: String

    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var split: PublicSplit?
    @State private var participantId: String?
    @State private var name = ""
    @State private var loadError: String?
    @State private var actionError: String?
    @State private var isJoining = false
    @State private var pendingItemIds: Set<String> = []

    private var secret: String? { SplitGuestStore.secret(for: shareToken) }
    private var me: PublicSplitParticipant? {
        guard let participantId else { return nil }
        return split?.participants.first { $0.id == participantId }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()

                if let loadError {
                    errorState(loadError)
                } else if let split {
                    content(split)
                } else {
                    ProgressView().tint(Theme.accent)
                }
            }
            .navigationTitle(split?.merchant ?? "Bill Split")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }.foregroundStyle(Theme.muted)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let split, let me { shareFooter(split: split, me: me) }
            }
        }
        .preferredColorScheme(.dark)
        .task { await load() }
    }

    // MARK: - Loading

    private func load() async {
        do {
            let resp: PublicSplitResponse = try await APIClient.shared.fetch(
                Endpoints.publicSplit(shareToken),
                headers: secretHeader()
            )
            split = resp.split
            participantId = resp.split.viewerParticipantId
            // The organizer can remove someone; drop a stale secret so the screen
            // offers to rejoin instead of failing every tap.
            if resp.split.viewerParticipantId == nil, secret != nil {
                SplitGuestStore.clear(for: shareToken)
            }
            loadError = nil
        } catch let error as APIServerError {
            // A revoked or mistyped link 404s; anything else is worth showing as
            // the server worded it.
            loadError = error.status == 404 || error.message.contains("Not found")
                ? "This split link isn't valid any more."
                : error.localizedDescription
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func secretHeader() -> [String: String] {
        guard let secret else { return [:] }
        return ["X-Split-Secret": secret]
    }

    // MARK: - Actions

    private func join() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isJoining = true
        actionError = nil
        Task {
            defer { isJoining = false }
            do {
                let resp: PublicJoinResponse = try await APIClient.shared.fetch(
                    Endpoints.publicSplitJoin(shareToken),
                    method: "POST",
                    body: PublicJoinBody(name: trimmed)
                )
                SplitGuestStore.save(secret: resp.claimSecret, for: shareToken)
                participantId = resp.participantId
                if let joined = resp.split { split = joined }
            } catch {
                actionError = error.localizedDescription
            }
        }
    }

    private func setClaim(_ item: BillSplitItem, quantity: Int) {
        guard let secret, split?.isOpen == true, !pendingItemIds.contains(item.id) else { return }
        pendingItemIds.insert(item.id)
        actionError = nil
        Task {
            defer { pendingItemIds.remove(item.id) }
            do {
                let resp: PublicSplitResponse = try await APIClient.shared.fetch(
                    Endpoints.publicSplitClaims(shareToken),
                    method: "POST",
                    body: BillSplitClaimBody(itemId: item.id, quantity: max(0, quantity)),
                    headers: ["X-Split-Secret": secret]
                )
                split = resp.split
            } catch let error as APIServerError where error.status == 409 {
                actionError = error.code == "claim_capacity_changed"
                    ? "Someone else just claimed the remaining quantity. This item has been refreshed."
                    : error.localizedDescription
                // APIClient keeps all non-2xx bodies behind APIServerError, so
                // fetch the fresh public DTO that the conflict represents. The
                // claim secret resolves the same viewer and their quantity.
                await load()
            } catch {
                actionError = error.localizedDescription
                await load()
            }
        }
    }

    // MARK: - Content

    private func content(_ split: PublicSplit) -> some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 5) {
                    if let organizer = split.organizerName {
                        Text("\(organizer) paid")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.faint)
                    }
                    Text(formatSplitMoney(split.totalCents, currency: split.currency))
                        .font(.system(size: 32, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.ink)
                    Text(formatSplitDate(split.occurredAt))
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)

                if !split.isOpen {
                    noticeBanner(
                        split.status == "settled"
                            ? "Everyone has settled up."
                            : "The organizer closed this split, so items can't change now."
                    )
                }

                // Joining an even split would add a head and silently re-divide
                // everyone's share — including the shares of people who already
                // walked away with a number in mind. The organizer set the
                // headcount; the link only reports what it came to.
                if split.isEvenSplit {
                    evenShareCard(split)
                } else if participantId == nil {
                    joinCard(split)
                }

                itemsSection(split)

                if let actionError {
                    Text(actionError)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.expense)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .refreshable { await load() }
    }

    /// The whole answer for a guest on an even split: what one person pays.
    private func evenShareCard(_ split: PublicSplit) -> some View {
        let heads = max(1, split.participants.count)
        return VStack(spacing: 8) {
            Text("Split evenly between \(heads)")
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
            Text(formatSplitMoney(split.totalCents / heads, currency: split.currency))
                .font(.system(size: 40, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.accent)
            Text("each")
                .font(.system(size: 13))
                .foregroundStyle(Theme.faint)
            if split.isEachOwn {
                Text("Everyone pays the restaurant directly.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.faint)
                    .multilineTextAlignment(.center)
                    .padding(.top, 2)
            } else if let organizer = split.organizerName {
                Text("Pay \(organizer) back for your share.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.faint)
                    .multilineTextAlignment(.center)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.accent.opacity(0.35), lineWidth: 1)
        )
    }

    private func joinCard(_ split: PublicSplit) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Who are you?")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Text("Your name shows up for the rest of the table.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
            TextField(
                "",
                text: $name,
                prompt: Text(appState.currentUser?.name ?? "Your name").foregroundStyle(Theme.faint)
            )
            .font(.system(size: 15))
            .foregroundStyle(Theme.ink)
            .formFieldStyle()
            .disabled(!split.isOpen)

            Button(action: join) {
                HStack {
                    if isJoining { ProgressView().tint(Theme.bg) }
                    Text(split.isOpen ? "Join this split" : "This split is closed")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(Theme.bg)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(split.isOpen ? Theme.accent : Theme.faint)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .disabled(!split.isOpen || isJoining || name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(14)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.line, lineWidth: 1)
        )
        .onAppear {
            // Pre-fill with the signed-in name; it's almost always right.
            if name.isEmpty, let accountName = appState.currentUser?.name { name = accountName }
        }
    }

    private func itemsSection(_ split: PublicSplit) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // An even split is decided by the headcount, so there is nothing here
            // for a guest to pick — the lines are just the receipt.
            SectionEyebrow(
                split.isEvenSplit || participantId == nil
                    ? "What was ordered"
                    : "Select your items"
            )

            VStack(spacing: 0) {
                ForEach(split.items) { item in
                    if item.id != split.items.first?.id {
                        Rectangle().fill(Theme.line).frame(height: 1)
                    }
                    itemRow(split: split, item: item)
                }
            }
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.line, lineWidth: 1)
            )
        }
    }

    private func itemRow(split: PublicSplit, item: BillSplitItem) -> some View {
        let claimers = split.participants.filter { $0.claimedItemIds.contains(item.id) }
        let mineQuantity = me?.claimQuantities[item.id]
            ?? (me?.claimedItemIds.contains(item.id) == true ? 1 : 0)
        let control = SplitClaimControlState(
            allocationMode: item.allocationMode,
            totalQuantity: item.quantity,
            claimedQuantity: item.claimedQuantity,
            participantQuantity: mineQuantity
        )
        let claimable = !split.isEvenSplit
        let interactive = participantId != nil && split.isOpen && claimable
        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 12) {
                if pendingItemIds.contains(item.id) {
                    ProgressView().tint(Theme.muted).frame(width: 19)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.quantity > 1 ? "\(item.quantity)× \(item.name)" : item.name)
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    if !claimable {
                        EmptyView()
                    } else if claimers.isEmpty {
                        Text("Unclaimed").font(.system(size: 11)).foregroundStyle(Theme.faint)
                    } else if control.isShared {
                        Text("Sharing: " + claimers.map(\.name).joined(separator: ", "))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                    } else {
                        let holders = claimers.map { participant in
                            let quantity = participant.claimQuantities[item.id]
                                ?? (participant.claimedItemIds.contains(item.id) ? 1 : 0)
                            return quantity > 1 ? "\(participant.name) \(quantity)×" : participant.name
                        }
                        Text("\(item.claimedQuantity) of \(item.quantity) claimed · " + holders.joined(separator: ", "))
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

            if interactive {
                if control.isShared {
                    Button(control.sharedActionTitle) {
                        setClaim(item, quantity: control.sharedDesiredQuantity)
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(control.mine > 0 ? Theme.muted : Theme.bg)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(control.mine > 0 ? Theme.surface2 : Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .disabled(pendingItemIds.contains(item.id))
                } else {
                    HStack(spacing: 10) {
                        publicQuantityButton(
                            "minus",
                            enabled: control.canDecrement && !pendingItemIds.contains(item.id)
                        ) {
                            setClaim(item, quantity: control.decrementedQuantity)
                        }
                        Spacer()
                        publicQuantityLabel("Mine", control.mine)
                        publicQuantityLabel("Available", control.available)
                        publicQuantityLabel("Total", control.total)
                        Spacer()
                        publicQuantityButton(
                            "plus",
                            enabled: control.canIncrement && !pendingItemIds.contains(item.id)
                        ) {
                            setClaim(item, quantity: control.incrementedQuantity)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func publicQuantityButton(
        _ systemName: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .bold))
                .frame(width: 30, height: 30)
                .background(Theme.surface2)
                .clipShape(Circle())
        }
        .foregroundStyle(enabled ? Theme.accent : Theme.faint)
        .disabled(!enabled)
    }

    private func publicQuantityLabel(_ label: String, _ value: Int) -> some View {
        VStack(spacing: 1) {
            Text("\(value)")
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.ink)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(Theme.faint)
        }
    }

    private func shareFooter(split: PublicSplit, me: PublicSplitParticipant) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(me.settled ? "You settled" : "Your share")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.faint)
                Text(
                    me.claimedItemIds.isEmpty
                        ? "Pick what you ordered"
                        : "Includes your part of tax & tip"
                )
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
            }
            Spacer()
            Text(formatSplitMoney(me.owedCents, currency: split.currency))
                .font(.system(size: 24, weight: .semibold, design: .monospaced))
                .foregroundStyle(me.settled ? Theme.income : Theme.accent)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial)
        .overlay(Rectangle().fill(Theme.line).frame(height: 1), alignment: .top)
    }

    private func noticeBanner(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill").font(.system(size: 12)).foregroundStyle(Theme.warning)
            Text(text).font(.system(size: 13)).foregroundStyle(Theme.ink)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.warning.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "link.badge.plus")
                .font(.system(size: 34))
                .foregroundStyle(Theme.faint)
            Text("Nothing to see here")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.muted)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Theme.faint)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
}

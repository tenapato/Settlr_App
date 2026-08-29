import SwiftUI

/// Copy and capabilities for the final split screen. Keeping payer decisions
/// pure prevents an each-own split from ever growing reimbursement controls.
struct SplitResultPresentation: Equatable {
    let payerMode: BillSplitPayerMode

    var statusHeadline: String {
        switch payerMode {
        case .organizerPaid: return "Ready to settle."
        case .eachOwn: return "Everyone paid their own share"
        case .unavailable: return "Split mode unavailable — open to review"
        }
    }

    var organizerShareLabel: String { "Your share" }

    var otherSharesLabel: String? {
        payerMode == .eachOwn ? "Everyone else's shares" : nil
    }

    var amountToCollectLabel: String? {
        payerMode == .organizerPaid ? "Amount to collect" : nil
    }

    func participantStatus(isOrganizer: Bool, isSettled: Bool) -> String {
        switch payerMode {
        case .organizerPaid:
            if isOrganizer { return "Paid the bill" }
            return isSettled ? "Settled" : "Owes you"
        case .eachOwn:
            return isOrganizer ? "Your share" : "Paid their own"
        case .unavailable:
            return "Share needs review"
        }
    }
}

/// The final, table-readable answer to a split.
///
/// The optional organizer context is supplied by detail. A result reached from
/// a newly-created split or pass-the-phone remains a presentation-only screen,
/// so owner-only settlement controls cannot leak into those flows.
struct SplitResultView: View {
    let split: BillSplit
    var workspaceId: String? = nil
    var splitId: String? = nil
    var vm: BillSplitVM? = nil
    var onFinish: (() -> Void)? = nil

    @State private var showQR = false

    private var currentSplit: BillSplit {
        guard let vm, let splitId, let detail = vm.detail, detail.id == splitId else { return split }
        return detail
    }

    private var presentation: SplitResultPresentation {
        SplitResultPresentation(payerMode: currentSplit.payerMode)
    }

    private var ranked: [BillSplitParticipant] {
        currentSplit.participants.sorted { $0.owedCents > $1.owedCents }
    }

    private var organizerShareCents: Int {
        currentSplit.organizer?.owedCents ?? 0
    }

    private var amountToCollectCents: Int {
        // `outstandingCents` is server-owned and already includes the exact
        // extras allocation used by the settlement endpoint.
        currentSplit.outstandingCents
    }

    private var hasOwnerSettlementContext: Bool {
        workspaceId != nil && splitId != nil && vm != nil
    }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(spacing: 12) {
                        summaryCard
                        participantsSection
                        unclaimedNotice
                        editingSafeguard
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
                footer
            }
        }
        .navigationTitle("Split result")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showQR) {
            if let link = currentSplit.shareLink {
                SplitQRSheet(link: link, merchant: currentSplit.merchant)
            }
        }
    }

    // MARK: - Header and summary

    private var header: some View {
        VStack(spacing: 5) {
            Text(currentSplit.merchant)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.muted)
            Text(formatSplitMoney(currentSplit.totalCents, currency: currentSplit.currency))
                .font(.system(size: 38, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.ink)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(presentation.statusHeadline)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(
                    currentSplit.payerMode == .unavailable ? Theme.warning : Theme.accentText
                )
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(currentSplit.merchant), total \(formatSplitMoney(currentSplit.totalCents, currency: currentSplit.currency))")
        .accessibilityValue(presentation.statusHeadline)
    }

    @ViewBuilder
    private var summaryCard: some View {
        switch currentSplit.payerMode {
        case .organizerPaid:
            VStack(alignment: .leading, spacing: 10) {
                SectionEyebrow("Settlement")
                resultAmountRow("Bill total", currentSplit.totalCents)
                resultAmountRow(presentation.organizerShareLabel, organizerShareCents)
                resultAmountRow(presentation.amountToCollectLabel ?? "Amount to collect", amountToCollectCents, emphasis: true)
                Text("Share reminder when someone still owes you.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
            }
            .resultCard()
        case .eachOwn:
            VStack(alignment: .leading, spacing: 10) {
                SectionEyebrow("Individual shares")
                resultAmountRow("Bill total", currentSplit.totalCents)
                resultAmountRow(presentation.organizerShareLabel, organizerShareCents, emphasis: true)
                resultAmountRow(presentation.otherSharesLabel ?? "Everyone else's shares", max(0, currentSplit.totalCents - organizerShareCents))
                Text("Everyone pays the restaurant directly. No reimbursements are recorded.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
            }
            .resultCard()
        case .unavailable:
            VStack(alignment: .leading, spacing: 8) {
                Label("Split needs review", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.warning)
                Text("Choose who paid before showing balances or recording settlements.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
            }
            .resultCard()
        }
    }

    private func resultAmountRow(_ label: String, _ cents: Int, emphasis: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.system(size: emphasis ? 15 : 13, weight: emphasis ? .semibold : .regular))
                .foregroundStyle(emphasis ? Theme.ink : Theme.muted)
            Spacer()
            Text(formatSplitMoney(cents, currency: currentSplit.currency))
                .font(.system(size: emphasis ? 19 : 14, weight: emphasis ? .semibold : .regular, design: .monospaced))
                .foregroundStyle(emphasis ? Theme.accentText : Theme.ink)
        }
    }

    // MARK: - People

    private var participantsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionEyebrow(currentSplit.payerMode == .eachOwn ? "Everyone's share" : "Who owes what")
            VStack(spacing: 8) {
                ForEach(ranked) { person in
                    participantCard(person)
                }
            }
        }
    }

    private func participantCard(_ person: BillSplitParticipant) -> some View {
        VStack(spacing: 10) {
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
                    HStack(spacing: 6) {
                        Text(person.name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                        if person.isOrganizer {
                            Text("you")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Theme.buttonInk)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Theme.accent)
                                .clipShape(Capsule())
                        }
                    }
                    Text(presentation.participantStatus(isOrganizer: person.isOrganizer, isSettled: person.isSettled))
                        .font(.system(size: 12))
                        .foregroundStyle(
                            currentSplit.payerMode == .organizerPaid && !person.isOrganizer && !person.isSettled
                                ? Theme.warning
                                : Theme.muted
                        )
                }
                Spacer(minLength: 4)
                Text(formatSplitMoney(person.owedCents, currency: currentSplit.currency))
                    .font(.system(size: 19, weight: .semibold, design: .monospaced))
                    .foregroundStyle(person.isSettled ? Theme.faint : Theme.ink)
                    .strikethrough(person.isSettled && currentSplit.payerMode == .organizerPaid, color: Theme.faint)
            }

            if hasOwnerSettlementContext,
               currentSplit.payerMode == .organizerPaid,
               !person.isOrganizer {
                settlementButton(for: person)
            }
        }
        .padding(14)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(person.isSettled ? Theme.income.opacity(0.3) : Theme.line, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func settlementButton(for person: BillSplitParticipant) -> some View {
        if let workspaceId, let splitId, let vm {
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
                HStack(spacing: 8) {
                    Image(systemName: person.isSettled ? "arrow.uturn.backward" : "checkmark")
                    Text(person.isSettled ? "Undo" : "Mark paid")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(person.isSettled ? Theme.ink : Theme.buttonInk)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .background(person.isSettled ? Theme.surface2 : Theme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(vm.isSaving)
            .accessibilityLabel(person.isSettled ? "Undo paid status for \(person.name)" : "Mark \(person.name) paid")
        }
    }

    // MARK: - Safeguards and handoff

    @ViewBuilder
    private var editingSafeguard: some View {
        if currentSplit.participants.contains(where: \.isSettled) {
            Label("Money editing is locked while settlements exist. Undo settlements before changing amounts or items.", systemImage: "lock.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.warning)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Theme.warning.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    @ViewBuilder
    private var unclaimedNotice: some View {
        let missing = currentSplit.totalCents - currentSplit.participants.reduce(0) { $0 + $1.owedCents }
        if missing > 0 {
            Label("\(formatSplitMoney(missing, currency: currentSplit.currency)) hasn't been claimed yet.", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundStyle(Theme.warning)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Theme.warning.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            if let link = currentSplit.shareLink {
                HStack(spacing: 10) {
                    ShareLink(item: link.absoluteString) {
                        Label("Share split", systemImage: "square.and.arrow.up")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.buttonInk)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 52)
                            .background(Theme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    Button { showQR = true } label: {
                        Label("Show QR", systemImage: "qrcode")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                            .frame(minWidth: 112, minHeight: 52)
                            .background(Theme.surface2)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Show QR")
                }
                Text("Share reminder: anyone with the link can join without an account.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.faint)
                    .multilineTextAlignment(.center)
            }

            if let onFinish {
                Button("Done", action: onFinish)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.buttonInk)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
                    .background(Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(16)
        .background(Theme.bg)
    }
}

private extension View {
    func resultCard() -> some View {
        self
            .padding(14)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.line, lineWidth: 1)
            )
    }
}

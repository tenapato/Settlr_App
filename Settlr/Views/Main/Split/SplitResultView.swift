import SwiftUI

/// What everyone owes, once the tapping is done.
///
/// This is the screen the whole flow exists to produce, and the one that gets
/// held up so the table can read it — so it is built to be read from across a
/// table rather than from the reading distance every other screen assumes: big
/// amounts, one person per row, ranked so the largest share is at the top.
///
/// It also states the two things people ask out loud. Whether anything is still
/// unclaimed (the bill doesn't add up until it's zero) and, when everyone paid
/// their own share, that nobody owes the organizer anything.
struct SplitResultView: View {
    let split: BillSplit
    /// Nil when there's nothing left to do — the caller is already finished.
    var onFinish: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    /// Biggest share first: it is the number people look for, and it puts whoever
    /// ordered the most where they can't miss it.
    private var ranked: [BillSplitParticipant] {
        split.participants.sorted { $0.owedCents > $1.owedCents }
    }

    private var assignedCents: Int {
        split.participants.reduce(0) { $0 + $1.owedCents }
    }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(ranked) { person in
                            row(person)
                        }
                        unclaimedNotice
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
                footer
            }
        }
        .navigationTitle("Who pays what")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(spacing: 4) {
            Text(split.merchant)
                .font(.system(size: 15))
                .foregroundStyle(Theme.muted)
            Text(formatSplitMoney(split.totalCents, currency: split.currency))
                .font(.system(size: 34, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.ink)
            Text(
                split.isEvenSplit
                    ? "Split evenly between \(split.participants.count)"
                    : "\(split.participants.count) people"
            )
            .font(.system(size: 12))
            .foregroundStyle(Theme.faint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private func row(_ person: BillSplitParticipant) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(person.name)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    if person.isOrganizer {
                        Text("you")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.bg)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.accent)
                            .clipShape(Capsule())
                    }
                }
                // Only meaningful when people claimed things; an even split has
                // no per-person item list to summarise.
                if !split.isEvenSplit {
                    Text(
                        person.claimedItemIds.isEmpty
                            ? "nothing claimed"
                            : "\(person.claimedItemIds.count) item\(person.claimedItemIds.count == 1 ? "" : "s")"
                    )
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.faint)
                }
            }

            Spacer()

            Text(formatSplitMoney(person.owedCents, currency: split.currency))
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .foregroundStyle(person.owedCents > 0 ? Theme.accent : Theme.faint)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(person.isOrganizer ? Theme.accent.opacity(0.4) : Theme.line, lineWidth: 1)
        )
    }

    /// The shares only add up to the bill when everything has been taken. Saying
    /// so here is the last chance to catch it before the table empties.
    @ViewBuilder
    private var unclaimedNotice: some View {
        let missing = split.totalCents - assignedCents
        if missing > 0 {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.warning)
                Text("\(formatSplitMoney(missing, currency: split.currency)) hasn't been claimed by anyone yet.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                Spacer()
            }
            .padding(14)
            .background(Theme.warning.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Text(
                split.isEachOwn
                    ? "Everyone pays the restaurant directly. Nobody owes you anything."
                    : "You paid the bill, so these are the amounts owed back to you."
            )
            .font(.system(size: 12))
            .foregroundStyle(Theme.faint)
            .multilineTextAlignment(.center)

            if let onFinish {
                Button("Done", action: onFinish)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.bg)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(16)
        .background(Theme.bg)
    }
}

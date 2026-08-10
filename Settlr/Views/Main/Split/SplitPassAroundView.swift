import SwiftUI

/// One phone, passed around the table.
///
/// The share link assumes everyone has a phone out, data, and the patience to
/// open a web page. Often they don't — so this is the fallback that always
/// works: hand the phone over, they tap what they had, hand it back. Each person
/// gets the screen to themselves, which also means nobody is scrolling past
/// everyone else's dinner to find their own.
///
/// Claims are written through the organizer's own authenticated session, naming
/// each participant in turn, so no guest secrets are involved.
struct SplitPassAroundView: View {
    let workspaceId: String
    let split: BillSplit
    let vm: BillSplitVM

    @Environment(\.dismiss) private var dismiss
    @State private var index = 0
    @State private var showResult = false

    /// The live split, which the view model replaces on every claim.
    private var current: BillSplit { vm.detail ?? split }
    private var people: [BillSplitParticipant] { current.participants }
    private var person: BillSplitParticipant? {
        people.indices.contains(index) ? people[index] : nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()

                if let person {
                    VStack(spacing: 0) {
                        header(person)
                        itemList(person)
                        footer(person)
                    }
                } else {
                    Text("This split has nobody in it yet.")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.muted)
                }
            }
            .navigationTitle("Pass the phone")
            .navigationBarTitleDisplayMode(.inline)
            // The point of passing the phone around is the tally at the end, so
            // finishing lands on it rather than dropping straight back to the
            // detail screen with nothing to show the table.
            .navigationDestination(isPresented: $showResult) {
                SplitResultView(split: current, onFinish: { dismiss() })
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }.foregroundStyle(Theme.muted)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Pieces

    private func header(_ person: BillSplitParticipant) -> some View {
        VStack(spacing: 6) {
            Text("\(index + 1) of \(people.count)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.faint)
            Text(person.name)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Theme.ink)
            Text("Tap everything you had")
                .font(.system(size: 14))
                .foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private func itemList(_ person: BillSplitParticipant) -> some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(current.items) { item in
                    let mine = person.claimedItemIds.contains(item.id)
                    let sharedWith = current.participants
                        .filter { $0.id != person.id && $0.claimedItemIds.contains(item.id) }
                        .count

                    Button {
                        Task {
                            await vm.toggleClaim(
                                workspaceId: workspaceId,
                                splitId: current.id,
                                itemId: item.id,
                                claimed: !mine,
                                participantId: person.id
                            )
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: mine ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 20))
                                .foregroundStyle(mine ? Theme.accent : Theme.faint)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .font(.system(size: 16, weight: mine ? .semibold : .regular))
                                    .foregroundStyle(Theme.ink)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                // Says the split is happening, so nobody worries that
                                // tapping a shared plate charges them the whole thing.
                                if sharedWith > 0 {
                                    Text(
                                        mine
                                            ? "Split with \(sharedWith) other\(sharedWith == 1 ? "" : "s")"
                                            : "\(sharedWith) already took this"
                                    )
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.faint)
                                }
                            }

                            Text(formatSplitMoney(item.lineTotalCents))
                                .font(.system(size: 15, design: .monospaced))
                                .foregroundStyle(mine ? Theme.ink : Theme.muted)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(mine ? Theme.accent.opacity(0.12) : Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .disabled(vm.isSaving)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    private func footer(_ person: BillSplitParticipant) -> some View {
        VStack(spacing: 12) {
            HStack {
                Text("\(person.name) owes")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.muted)
                Spacer()
                Text(formatSplitMoney(person.owedCents))
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.accent)
            }

            // Anything nobody has taken yet would otherwise be discovered only
            // after the table has emptied.
            if current.unclaimedItemsCents > 0 {
                Text("\(formatSplitMoney(current.unclaimedItemsCents)) of the bill is still unclaimed.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 10) {
                if index > 0 {
                    Button("Back") { index -= 1 }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                Button(isLast ? "See the totals" : "Next person") {
                    if isLast { showResult = true } else { index += 1 }
                }
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

    private var isLast: Bool { index >= people.count - 1 }
}

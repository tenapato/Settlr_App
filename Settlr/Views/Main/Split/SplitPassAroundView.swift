import SwiftUI

/// One authenticated phone passed around the table. People are created on the
/// server before claims start, so every tap belongs to a stable participant id.
struct SplitPassAroundView: View {
    let workspaceId: String
    let split: BillSplit
    let vm: BillSplitVM

    @Environment(\.dismiss) private var dismiss
    @State private var passState: PassAroundState
    @State private var isShowingSetup = true
    @State private var participantNames: [String: String]
    @State private var newPersonName = ""
    @State private var notice: String?
    @State private var showResult = false

    init(workspaceId: String, split: BillSplit, vm: BillSplitVM) {
        self.workspaceId = workspaceId
        self.split = split
        self.vm = vm
        _passState = State(initialValue: PassAroundState(
            participantIDs: split.participants.map(\.id)
        ))
        _participantNames = State(initialValue: Dictionary(
            uniqueKeysWithValues: split.participants.map { ($0.id, $0.name) }
        ))
    }

    private var current: BillSplit { vm.detail?.id == split.id ? vm.detail! : split }
    private var people: [BillSplitParticipant] {
        passState.orderedParticipantIDs.compactMap { id in
            current.participants.first { $0.id == id }
        }
    }
    private var person: BillSplitParticipant? {
        guard let id = passState.currentParticipantID else { return nil }
        return current.participants.first { $0.id == id }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()

                if isShowingSetup {
                    setupView
                } else if let person {
                    VStack(spacing: 0) {
                        header(person)
                        itemList(person)
                        footer(person)
                    }
                } else {
                    ContentUnavailableView(
                        "No people at the table",
                        systemImage: "person.badge.plus",
                        description: Text("Add somebody before starting pass the phone.")
                    )
                    .foregroundStyle(Theme.muted)
                }
            }
            .navigationTitle("Pass the phone")
            .navigationBarTitleDisplayMode(.inline)
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
        .onAppear { adoptCurrentParticipants() }
        .onChange(of: current.version) { _, _ in adoptCurrentParticipants() }
    }

    // MARK: - Table setup

    private var setupView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Who's at the table?")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(Theme.ink)
                        Text("Add everyone, fix their names, and choose the order the phone goes around.")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.muted)
                    }

                    if let notice {
                        Text(notice)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.warning)
                    } else if let error = vm.errorMessage {
                        Text(error)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.expense)
                    }

                    VStack(spacing: 0) {
                        ForEach(Array(people.enumerated()), id: \.element.id) { index, participant in
                            if index > 0 { Rectangle().fill(Theme.line).frame(height: 1) }
                            participantSetupRow(participant, index: index)
                        }
                    }
                    .background(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Theme.line, lineWidth: 1)
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Add person")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                        HStack(spacing: 8) {
                            TextField("Person \(people.count + 1)", text: $newPersonName)
                                .font(.system(size: 15))
                                .foregroundStyle(Theme.ink)
                                .textInputAutocapitalization(.words)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 11)
                                .background(Theme.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                            Button("Add") { addPerson() }
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.bg)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 11)
                                .background(Theme.accent)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .disabled(vm.isSaving || !current.isOpen)
                        }
                    }
                }
                .padding(16)
            }

            setupFooter
        }
    }

    private func participantSetupRow(
        _ participant: BillSplitParticipant,
        index: Int
    ) -> some View {
        HStack(spacing: 8) {
            VStack(spacing: 4) {
                Button { passState.moveParticipant(id: participant.id, by: -1) } label: {
                    Image(systemName: "chevron.up")
                }
                .disabled(index == 0)
                Button { passState.moveParticipant(id: participant.id, by: 1) } label: {
                    Image(systemName: "chevron.down")
                }
                .disabled(index == people.count - 1)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.muted)
            .frame(width: 24)

            TextField(participant.name, text: participantNameBinding(participant))
                .font(.system(size: 15))
                .foregroundStyle(Theme.ink)
                .textInputAutocapitalization(.words)
                .onSubmit { rename(participant) }

            if normalizedDraftName(participant) != participant.name {
                Button { rename(participant) } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.accent)
                }
                .disabled(vm.isSaving)
            }

            if !participant.isOrganizer {
                Button(role: .destructive) { remove(participant) } label: {
                    Image(systemName: "minus.circle")
                        .foregroundStyle(Theme.expense)
                }
                .disabled(vm.isSaving || !current.isOpen)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var setupFooter: some View {
        VStack(spacing: 8) {
            if people.count >= 2 {
                Button(passState.hasStarted ? "Back to claims" : "Start passing") {
                    if passState.start() { isShowingSetup = false }
                }
                .primaryPassButton()
            } else if people.count == 1 {
                Text("Add at least one other person, or explicitly continue alone.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                Button("Continue with just me") {
                    passState.continueWithJustMe()
                    if passState.start() { isShowingSetup = false }
                }
                .primaryPassButton()
            }
        }
        .padding(16)
        .background(Theme.bg)
    }

    // MARK: - Claim screens

    private func header(_ person: BillSplitParticipant) -> some View {
        VStack(spacing: 6) {
            Text("\(passState.position) of \(people.count)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.faint)
            Text(person.name)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Theme.ink)
            Text("Choose exactly what you had")
                .font(.system(size: 14))
                .foregroundStyle(Theme.muted)
            if let notice {
                Text(notice)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.warning)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            } else if let error = vm.errorMessage {
                Text(error)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.expense)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .padding(.horizontal, 16)
    }

    private func itemList(_ person: BillSplitParticipant) -> some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(current.items) { item in
                    claimRow(item, person: person)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    private func claimRow(_ item: BillSplitItem, person: BillSplitParticipant) -> some View {
        let control = claimState(item, person: person)
        let sharers = current.participants.filter { claimQuantity($0, item: item) > 0 }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name)
                        .font(.system(size: 16, weight: control.mine > 0 ? .semibold : .regular))
                        .foregroundStyle(Theme.ink)
                    if control.isShared {
                        Text(sharers.isEmpty ? "Nobody is sharing yet" : "Sharing: \(sharers.map(\.name).joined(separator: ", "))")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.faint)
                            .lineLimit(2)
                    } else {
                        Text("\(formatSplitMoney(item.unitPriceCents)) each")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.faint)
                    }
                }
                Spacer(minLength: 4)
                Text(formatSplitMoney(item.lineTotalCents))
                    .font(.system(size: 15, design: .monospaced))
                    .foregroundStyle(Theme.muted)
            }

            if control.isShared {
                Button(control.sharedActionTitle) {
                    setClaim(item, person: person, quantity: control.sharedDesiredQuantity)
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(control.mine > 0 ? Theme.muted : Theme.bg)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(control.mine > 0 ? Theme.surface2 : Theme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .disabled(vm.isSaving)
            } else {
                HStack(spacing: 12) {
                    quantityButton("minus", enabled: control.canDecrement) {
                        setClaim(item, person: person, quantity: control.decrementedQuantity)
                    }
                    Spacer()
                    quantityLabel("Mine", control.mine)
                    quantityLabel("Available", control.available)
                    quantityLabel("Total", control.total)
                    Spacer()
                    quantityButton("plus", enabled: control.canIncrement) {
                        setClaim(item, person: person, quantity: control.incrementedQuantity)
                    }
                }
            }
        }
        .padding(14)
        .background(control.mine > 0 ? Theme.accent.opacity(0.1) : Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(control.mine > 0 ? Theme.accent.opacity(0.35) : Theme.line, lineWidth: 1)
        )
    }

    private func quantityButton(
        _ systemName: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .bold))
                .frame(width: 34, height: 34)
                .background(Theme.surface2)
                .clipShape(Circle())
        }
        .foregroundStyle(enabled ? Theme.accent : Theme.faint)
        .disabled(!enabled || vm.isSaving)
    }

    private func quantityLabel(_ label: String, _ value: Int) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.ink)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Theme.faint)
        }
    }

    private func footer(_ person: BillSplitParticipant) -> some View {
        VStack(spacing: 10) {
            HStack {
                Text(passAmountLabel(split: current, person: person))
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.muted)
                Spacer()
                Text(formatSplitMoney(person.owedCents))
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.accent)
            }

            if current.unclaimedItemsCents > 0 {
                Text("\(formatSplitMoney(current.unclaimedItemsCents)) of the bill is still unassigned.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if current.isOpen {
                Button("Add person or change order") { isShowingSetup = true }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.accent)
            }

            HStack(spacing: 10) {
                if passState.position > 1 {
                    Button("Back") { passState.selectPrevious() }
                        .secondaryPassButton()
                }

                Button(passState.isLast ? "See the totals" : "Next person") {
                    if passState.isLast { showResult = true } else { passState.selectNext() }
                }
                .primaryPassButton()
            }
        }
        .padding(16)
        .background(Theme.bg)
    }

    private func passAmountLabel(split: BillSplit, person: BillSplitParticipant) -> String {
        switch split.payerMode {
        case .eachOwn:
            return "\(person.name)'s share"
        case .organizerPaid:
            return "\(person.name) owes"
        case .unavailable:
            return "Share needs review"
        }
    }

    // MARK: - Actions and derived state

    private func claimQuantity(_ participant: BillSplitParticipant, item: BillSplitItem) -> Int {
        participant.claimQuantities[item.id]
            ?? (participant.claimedItemIds.contains(item.id) ? 1 : 0)
    }

    private func claimState(
        _ item: BillSplitItem,
        person: BillSplitParticipant
    ) -> SplitClaimControlState {
        SplitClaimControlState(
            allocationMode: item.allocationMode,
            totalQuantity: item.quantity,
            claimedQuantity: item.claimedQuantity,
            participantQuantity: claimQuantity(person, item: item)
        )
    }

    private func setClaim(
        _ item: BillSplitItem,
        person: BillSplitParticipant,
        quantity: Int
    ) {
        let participantID = person.id
        notice = nil
        Task {
            let result = await vm.setClaimQuantity(
                workspaceId: workspaceId,
                splitId: current.id,
                itemId: item.id,
                quantity: quantity,
                participantId: participantID
            )
            adoptCurrentParticipants()
            if result == .capacityChanged {
                notice = "Someone else just claimed the remaining quantity. Nothing was changed for \(person.name)."
            }
        }
    }

    private func participantNameBinding(_ participant: BillSplitParticipant) -> Binding<String> {
        Binding(
            get: { participantNames[participant.id] ?? participant.name },
            set: { participantNames[participant.id] = $0 }
        )
    }

    private func normalizedDraftName(_ participant: BillSplitParticipant) -> String {
        let name = (participantNames[participant.id] ?? participant.name)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? participant.name : name
    }

    private func addPerson() {
        let fallback = "Person \(people.count + 1)"
        let entered = newPersonName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = entered.isEmpty ? fallback : entered
        notice = nil
        Task {
            if await vm.addParticipant(workspaceId: workspaceId, splitId: current.id, name: name) {
                newPersonName = ""
            }
            adoptCurrentParticipants()
        }
    }

    private func rename(_ participant: BillSplitParticipant) {
        let name = normalizedDraftName(participant)
        guard name != participant.name else { return }
        notice = nil
        Task {
            _ = await vm.renameParticipant(
                workspaceId: workspaceId,
                splitId: current.id,
                participantId: participant.id,
                name: name
            )
            adoptCurrentParticipants()
        }
    }

    private func remove(_ participant: BillSplitParticipant) {
        notice = nil
        Task {
            _ = await vm.removeParticipant(
                workspaceId: workspaceId,
                splitId: current.id,
                participantId: participant.id
            )
            adoptCurrentParticipants()
        }
    }

    private func adoptCurrentParticipants() {
        passState.adoptParticipantIDs(current.participants.map(\.id))
        for participant in current.participants {
            participantNames[participant.id] = participant.name
        }
        participantNames = participantNames.filter { id, _ in
            current.participants.contains { $0.id == id }
        }
    }
}

private extension View {
    func primaryPassButton() -> some View {
        self
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Theme.bg)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.accent)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    func secondaryPassButton() -> some View {
        self
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

import SwiftUI

struct CardDetailSheet: View {
    let workspaceId: String
    let card: CreditCard
    let onSave: (UpdateCreditCardBody) async throws -> CreditCard

    @Environment(\.dismiss) private var dismiss

    @State private var label: String
    @State private var lastFour: String
    @State private var network: String
    @State private var limitStr: String
    @State private var issuer: String
    @State private var cutoffDayStr: String
    @State private var dueDayStr: String
    @State private var notes: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let networks = [("", "None"), ("visa", "Visa"), ("mastercard", "MC"), ("amex", "Amex"), ("other", "Other")]

    init(
        workspaceId: String,
        card: CreditCard,
        onSave: @escaping (UpdateCreditCardBody) async throws -> CreditCard
    ) {
        self.workspaceId = workspaceId
        self.card = card
        self.onSave = onSave
        _label = State(initialValue: card.label)
        _lastFour = State(initialValue: card.lastFour ?? "")
        _network = State(initialValue: card.network ?? "")
        _limitStr = State(initialValue: card.creditLimitCents.map { String($0 / 100) } ?? "")
        _issuer = State(initialValue: card.issuer ?? "")
        _cutoffDayStr = State(initialValue: card.statementCutoffDay.map(String.init) ?? "")
        _dueDayStr = State(initialValue: card.paymentDueDay.map(String.init) ?? "")
        _notes = State(initialValue: card.notes ?? "")
    }

    private var previewCard: CreditCard {
        CreditCard(
            id: card.id,
            label: label.trimmingCharacters(in: .whitespaces).isEmpty ? card.label : label,
            lastFour: lastFour.isEmpty ? nil : lastFour,
            network: network.isEmpty ? nil : network,
            issuer: issuer.isEmpty ? nil : issuer,
            creditLimitCents: Int(limitStr.replacingOccurrences(of: ",", with: "")).map { $0 * 100 },
            statementCutoffDay: Int(cutoffDayStr),
            paymentDueDay: Int(dueDayStr),
            notes: notes.isEmpty ? nil : notes
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#0e0f11").ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        VirtualCardFace(card: previewCard, style: .hero)

                        VStack(spacing: 18) {
                            CardFormField(label: "Card Name *") {
                                TextField("e.g. Amex Platinum", text: $label)
                                    .foregroundStyle(Color(hex: "#ecedee"))
                            }

                            CardFormField(label: "Last 4 Digits") {
                                TextField("1234", text: $lastFour)
                                    .keyboardType(.numberPad)
                                    .foregroundStyle(Color(hex: "#ecedee"))
                                    .onChange(of: lastFour) { _, newValue in
                                        lastFour = String(newValue.filter(\.isNumber).prefix(4))
                                    }
                            }

                            networkPicker

                            CardFormField(label: "Issuer (optional)") {
                                TextField("e.g. American Express", text: $issuer)
                                    .foregroundStyle(Color(hex: "#ecedee"))
                            }

                            CardFormField(label: "Credit Limit (optional)") {
                                TextField("e.g. 50000", text: $limitStr)
                                    .keyboardType(.numberPad)
                                    .foregroundStyle(Color(hex: "#ecedee"))
                            }

                            HStack(spacing: 12) {
                                CardFormField(label: "Cutoff Day") {
                                    TextField("1–31", text: $cutoffDayStr)
                                        .keyboardType(.numberPad)
                                        .foregroundStyle(Color(hex: "#ecedee"))
                                        .onChange(of: cutoffDayStr) { _, newValue in
                                            cutoffDayStr = String(newValue.filter(\.isNumber).prefix(2))
                                        }
                                }

                                CardFormField(label: "Due Day") {
                                    TextField("1–31", text: $dueDayStr)
                                        .keyboardType(.numberPad)
                                        .foregroundStyle(Color(hex: "#ecedee"))
                                        .onChange(of: dueDayStr) { _, newValue in
                                            dueDayStr = String(newValue.filter(\.isNumber).prefix(2))
                                        }
                                }
                            }

                            CardFormField(label: "Notes (optional)") {
                                TextField("Optional notes", text: $notes, axis: .vertical)
                                    .lineLimit(3...5)
                                    .foregroundStyle(Color(hex: "#ecedee"))
                            }

                            if let errorMessage {
                                Text(errorMessage)
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color(hex: "#ff6b6b"))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
                .contentMargins(.bottom, 24, for: .scrollContent)
            }
            .navigationTitle("Card Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color(hex: "#8e9197"))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView().tint(Color(hex: "#c8ff5a"))
                        } else {
                            Text("Save")
                                .fontWeight(.semibold)
                                .foregroundStyle(Color(hex: "#c8ff5a"))
                        }
                    }
                    .disabled(isSaving || label.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(hex: "#0e0f11"))
        .presentationCornerRadius(24)
        .preferredColorScheme(.dark)
    }

    private var networkPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Network")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(hex: "#8e9197"))
                .tracking(1)
                .textCase(.uppercase)

            HStack(spacing: 8) {
                ForEach(networks, id: \.0) { val, networkLabel in
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { network = val }
                    } label: {
                        Text(networkLabel)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(network == val ? Color(hex: "#0e0f11") : Color(hex: "#8e9197"))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 9)
                                    .fill(network == val ? Color(hex: "#c8ff5a") : Color(hex: "#15171a"))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @MainActor
    private func save() async {
        let trimmedLabel = label.trimmingCharacters(in: .whitespaces)
        guard !trimmedLabel.isEmpty else {
            errorMessage = "Card name is required."
            return
        }

        let limitCents: Int? = {
            let raw = limitStr.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
            guard !raw.isEmpty, let value = Int(raw), value > 0 else { return nil }
            return value * 100
        }()

        let cutoff = Int(cutoffDayStr)
        if let cutoff, !(1...31).contains(cutoff) {
            errorMessage = "Cutoff day must be between 1 and 31."
            return
        }
        let due = Int(dueDayStr)
        if let due, !(1...31).contains(due) {
            errorMessage = "Due day must be between 1 and 31."
            return
        }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            _ = try await onSave(UpdateCreditCardBody(
                label: trimmedLabel,
                lastFour: lastFour.isEmpty ? nil : lastFour,
                network: network.isEmpty ? nil : network,
                issuer: issuer.isEmpty ? nil : issuer,
                creditLimitCents: limitCents,
                statementCutoffDay: cutoff,
                paymentDueDay: due,
                notes: notes.isEmpty ? nil : notes
            ))
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct CardFormField<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(hex: "#8e9197"))
                .tracking(1)
                .textCase(.uppercase)
            content()
                .font(.system(size: 16))
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(hex: "#15171a"))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color(hex: "#2a2d32"), lineWidth: 1)
                        )
                )
        }
    }
}

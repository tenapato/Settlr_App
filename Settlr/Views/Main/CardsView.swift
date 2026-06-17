import SwiftUI
import Observation

// MARK: - ViewModel

@Observable
final class CardsVM {
    var cards: [CreditCard] = []
    var isLoading = false
    var isCreating = false
    var errorMessage: String?
    var showCreateSheet = false

    var newLabel = ""
    var newLastFour = ""
    var newNetwork = ""
    var newLimitStr = ""

    private let api = APIClient.shared

    @MainActor
    func load(workspaceId: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let resp: CreditCardsResponse = try await api.fetch(Endpoints.creditCards(workspaceId))
            cards = resp.creditCards
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func createCard(workspaceId: String) async {
        let label = newLabel.trimmingCharacters(in: .whitespaces)
        guard !label.isEmpty else { return }
        isCreating = true
        defer { isCreating = false }
        let lastFour = newLastFour.trimmingCharacters(in: .whitespaces).isEmpty ? nil : newLastFour
        let network = newNetwork.isEmpty ? nil : newNetwork
        let limitCents: Int? = Int(newLimitStr.replacingOccurrences(of: ",", with: "")).map { $0 * 100 }
        do {
            let resp: CreditCardsResponse = try await api.fetch(
                Endpoints.creditCards(workspaceId),
                method: "POST",
                body: CreateCreditCardBody(label: label, lastFour: lastFour, network: network, creditLimitCents: limitCents)
            )
            cards = resp.creditCards
            resetForm()
            showCreateSheet = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func deleteCard(workspaceId: String, cardId: String) async {
        do {
            try await api.send(Endpoints.creditCard(workspaceId, cardId), method: "DELETE")
            cards.removeAll { $0.id == cardId }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func resetForm() {
        newLabel = ""; newLastFour = ""; newNetwork = ""; newLimitStr = ""
    }
}

// MARK: - View

struct CardsView: View {
    let workspaceId: String
    @State private var vm = CardsVM()

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#0e0f11").ignoresSafeArea()

                ZStack {
                    if vm.isLoading {
                        ProgressView()
                            .tint(Color(hex: "#c8ff5a"))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .transition(.opacity)
                    } else if let err = vm.errorMessage {
                        CardsErrorView(message: err) { Task { await vm.load(workspaceId: workspaceId) } }
                            .transition(.opacity)
                    } else if vm.cards.isEmpty {
                        CardsEmptyView { vm.showCreateSheet = true }
                            .transition(.opacity)
                    } else {
                        cardList.transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: 0.22), value: vm.isLoading)
            }
            .navigationTitle("Cards")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { vm.showCreateSheet = true } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color(hex: "#c8ff5a"))
                    }
                }
            }
            .sheet(isPresented: $vm.showCreateSheet) {
                CreateCardSheet(vm: vm, workspaceId: workspaceId)
            }
        }
        .preferredColorScheme(.dark)
        .task { await vm.load(workspaceId: workspaceId) }
    }

    private var cardList: some View {
        List {
            ForEach(vm.cards) { card in
                CardTile(card: card)
                    .listRowInsets(EdgeInsets(top: 8, leading: 24, bottom: 8, trailing: 24))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            Task { await vm.deleteCard(workspaceId: workspaceId, cardId: card.id) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
            Spacer().frame(height: 100)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await vm.load(workspaceId: workspaceId) }
    }
}

// MARK: - Card Tile

private struct CardTile: View {
    let card: CreditCard
    @State private var appeared = false

    private var gradientColors: [Color] {
        switch card.network?.lowercased() {
        case "visa":       return [Color(hex: "#1a1f71"), Color(hex: "#2d3561")]
        case "mastercard": return [Color(hex: "#1a0000"), Color(hex: "#3d0000")]
        case "amex":       return [Color(hex: "#003366"), Color(hex: "#005599")]
        default:           return [Color(hex: "#1c1f23"), Color(hex: "#23262b")]
        }
    }

    private var networkLabel: String {
        switch card.network?.lowercased() {
        case "visa":       return "VISA"
        case "mastercard": return "Mastercard"
        case "amex":       return "AMEX"
        default:           return ""
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 20)
                .fill(LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
                .frame(height: 160)

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(card.label)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    if !networkLabel.isEmpty {
                        Text(networkLabel)
                            .font(.system(size: 13, weight: .bold))
                            .tracking(1.5)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }

                Spacer()

                Text(card.lastFour.map { "•••• •••• •••• \($0)" } ?? "•••• •••• •••• ••••")
                    .font(.system(size: 18, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(card.lastFour != nil ? 0.85 : 0.3))

                if let limit = card.creditLimitCents {
                    Spacer().frame(height: 10)
                    HStack(spacing: 4) {
                        Text("Limit")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.45))
                        AmountLabel(cents: limit, font: .system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.65))
                    }
                }
            }
            .padding(22)
            .frame(height: 160)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 16)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { appeared = true }
        }
    }
}

// MARK: - Create Sheet

private struct CreateCardSheet: View {
    let vm: CardsVM
    let workspaceId: String
    @FocusState private var focused: Bool

    private let networks = [("", "None"), ("visa", "Visa"), ("mastercard", "MC"), ("amex", "Amex"), ("other", "Other")]

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#0e0f11").ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 18) {
                        CardFormField(label: "Card Name *") {
                            TextField("e.g. Chase Sapphire", text: Binding(get: { vm.newLabel }, set: { vm.newLabel = $0 }))
                                .focused($focused)
                                .foregroundStyle(Color(hex: "#ecedee"))
                        }

                        CardFormField(label: "Last 4 Digits") {
                            TextField("1234", text: Binding(get: { vm.newLastFour }, set: { vm.newLastFour = String($0.prefix(4)) }))
                                .keyboardType(.numberPad)
                                .foregroundStyle(Color(hex: "#ecedee"))
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Network")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color(hex: "#8e9197"))
                                .tracking(1).textCase(.uppercase)

                            HStack(spacing: 8) {
                                ForEach(networks, id: \.0) { val, label in
                                    Button {
                                        withAnimation(.snappy(duration: 0.2)) { vm.newNetwork = val }
                                    } label: {
                                        Text(label)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(vm.newNetwork == val ? Color(hex: "#0e0f11") : Color(hex: "#8e9197"))
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 10)
                                            .background(RoundedRectangle(cornerRadius: 9)
                                                .fill(vm.newNetwork == val ? Color(hex: "#c8ff5a") : Color(hex: "#15171a")))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        CardFormField(label: "Credit Limit (optional)") {
                            TextField("e.g. 50000", text: Binding(get: { vm.newLimitStr }, set: { vm.newLimitStr = $0 }))
                                .keyboardType(.numberPad)
                                .foregroundStyle(Color(hex: "#ecedee"))
                        }

                        Button {
                            Task { await vm.createCard(workspaceId: workspaceId) }
                        } label: {
                            Group {
                                if vm.isCreating { ProgressView().tint(Color(hex: "#0e0f11")) }
                                else { Text("Add Card").font(.system(size: 16, weight: .semibold)).foregroundStyle(Color(hex: "#0e0f11")) }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Color(hex: "#c8ff5a")))
                        }
                        .disabled(vm.newLabel.trimmingCharacters(in: .whitespaces).isEmpty || vm.isCreating)
                        .opacity(vm.newLabel.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
                    }
                    .padding(24)
                }
            }
            .navigationTitle("New Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { vm.showCreateSheet = false; vm.resetForm() }
                        .foregroundStyle(Color(hex: "#8e9197"))
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(Color(hex: "#0e0f11"))
        .presentationCornerRadius(24)
        .onAppear { focused = true }
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
                .tracking(1).textCase(.uppercase)
            content()
                .font(.system(size: 16))
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12)
                    .fill(Color(hex: "#15171a"))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(hex: "#2a2d32"), lineWidth: 1)))
        }
    }
}

// MARK: - Empty / Error

private struct CardsEmptyView: View {
    let onAdd: () -> Void
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "creditcard").font(.system(size: 48)).foregroundStyle(Color(hex: "#5a5d63"))
            VStack(spacing: 8) {
                Text("No cards yet").font(.system(size: 18, weight: .semibold)).foregroundStyle(Color(hex: "#ecedee"))
                Text("Add a credit card to track spending").font(.system(size: 14)).foregroundStyle(Color(hex: "#8e9197"))
            }
            Button(action: onAdd) {
                Text("Add Card").font(.system(size: 15, weight: .semibold)).foregroundStyle(Color(hex: "#0e0f11"))
                    .padding(.horizontal, 28).padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: "#c8ff5a")))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct CardsErrorView: View {
    let message: String; let onRetry: () -> Void
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 32)).foregroundStyle(Color(hex: "#ffb547"))
            Text(message).font(.system(size: 14)).foregroundStyle(Color(hex: "#8e9197")).multilineTextAlignment(.center)
            Button("Retry", action: onRetry).foregroundStyle(Color(hex: "#c8ff5a")).font(.system(size: 15, weight: .semibold))
        }
        .padding(.horizontal, 32).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

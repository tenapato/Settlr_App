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
    func updateCard(workspaceId: String, cardId: String, body: UpdateCreditCardBody) async throws -> CreditCard {
        let resp: CreditCardResponse = try await api.fetch(
            Endpoints.creditCard(workspaceId, cardId),
            method: "PATCH",
            body: body
        )
        if let idx = cards.firstIndex(where: { $0.id == cardId }) {
            cards[idx] = resp.creditCard
        }
        return resp.creditCard
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
    @State private var searchText = ""
    @State private var selectedCard: CreditCard?

    private var filteredCards: [CreditCard] {
        guard !searchText.isEmpty else { return vm.cards }
        return vm.cards.filter {
            $0.label.localizedCaseInsensitiveContains(searchText) ||
            ($0.lastFour?.contains(searchText) ?? false) ||
            ($0.network?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

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
                        CardsErrorView(message: err) {
                            Task { await vm.load(workspaceId: workspaceId) }
                        }
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
            .sheet(item: $selectedCard) { card in
                CardDetailSheet(workspaceId: workspaceId, card: card) { body in
                    try await vm.updateCard(workspaceId: workspaceId, cardId: card.id, body: body)
                }
            }
        }
        .preferredColorScheme(.dark)
        .task { await vm.load(workspaceId: workspaceId) }
    }

    private var cardList: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                // Search bar pinned at top
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color(hex: "#5a5d63"))
                    TextField("Search by name, network, or last 4", text: $searchText)
                        .font(.system(size: 15))
                        .foregroundStyle(Color(hex: "#ecedee"))
                        .autocorrectionDisabled()
                        .autocapitalization(.none)
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(Color(hex: "#5a5d63"))
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(hex: "#15171a"))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color(hex: "#2a2d32"), lineWidth: 1))
                )
                .padding(.horizontal, 20)
                .padding(.top, 4)

                if filteredCards.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 32))
                            .foregroundStyle(Color(hex: "#5a5d63"))
                        Text("No results for \"\(searchText)\"")
                            .font(.system(size: 15))
                            .foregroundStyle(Color(hex: "#8e9197"))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                } else {
                    ForEach(Array(filteredCards.enumerated()), id: \.element.id) { i, card in
                        Button {
                            selectedCard = card
                        } label: {
                            CardTile(card: card, rank: i)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 20)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                Task { await vm.deleteCard(workspaceId: workspaceId, cardId: card.id) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                Spacer().frame(height: 100)
            }
            .padding(.top, 8)
        }
        .scrollContentBackground(.hidden)
        .refreshable { await vm.load(workspaceId: workspaceId) }
    }
}

// MARK: - Card Tile

private struct CardTile: View {
    let card: CreditCard
    let rank: Int
    @State private var appeared = false

    var body: some View {
        VirtualCardFace(card: card, style: .compact)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 14)
            .onAppear {
                let delay = Double(rank) * 0.06
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(delay)) {
                    appeared = true
                }
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
                                if vm.isCreating {
                                    ProgressView().tint(Color(hex: "#0e0f11"))
                                } else {
                                    Text("Add Card")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(Color(hex: "#0e0f11"))
                                }
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
            Image(systemName: "creditcard")
                .font(.system(size: 48))
                .foregroundStyle(Color(hex: "#5a5d63"))
            VStack(spacing: 8) {
                Text("No cards yet")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color(hex: "#ecedee"))
                Text("Add a credit card to track spending")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(hex: "#8e9197"))
            }
            Button(action: onAdd) {
                Text("Add Card")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(hex: "#0e0f11"))
                    .padding(.horizontal, 28).padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: "#c8ff5a")))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct CardsErrorView: View {
    let message: String
    let onRetry: () -> Void
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundStyle(Color(hex: "#ffb547"))
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(Color(hex: "#8e9197"))
                .multilineTextAlignment(.center)
            Button("Retry", action: onRetry)
                .foregroundStyle(Color(hex: "#c8ff5a"))
                .font(.system(size: 15, weight: .semibold))
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

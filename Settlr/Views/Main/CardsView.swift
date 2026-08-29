import SwiftUI
import Observation

// MARK: - ViewModel

@MainActor
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
    @discardableResult
    func createCard(workspaceId: String) async -> Bool {
        let label = newLabel.trimmingCharacters(in: .whitespaces)
        guard !label.isEmpty else { return false }
        isCreating = true
        errorMessage = nil
        defer { isCreating = false }
        let lastFour = newLastFour.trimmingCharacters(in: .whitespaces).isEmpty ? nil : newLastFour
        let network = newNetwork.isEmpty ? nil : newNetwork
        let limitCents: Int? = Int(newLimitStr.replacingOccurrences(of: ",", with: "")).map { $0 * 100 }
        do {
            let resp: CreditCardResponse = try await api.fetch(
                Endpoints.creditCards(workspaceId),
                method: "POST",
                body: CreateCreditCardBody(label: label, lastFour: lastFour, network: network, creditLimitCents: limitCents)
            )
            cards.append(resp.creditCard)
            resetForm()
            showCreateSheet = false
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
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
    @discardableResult
    func deleteCard(workspaceId: String, cardId: String) async -> Bool {
        do {
            try await api.send(Endpoints.creditCard(workspaceId, cardId), method: "DELETE")
            cards.removeAll { $0.id == cardId }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func resetForm() {
        newLabel = ""; newLastFour = ""; newNetwork = ""; newLimitStr = ""
    }
}

// MARK: - View

struct CardsView: View {
    let workspaceId: String
    var embedded: Bool = false
    var onCardMutated: (() async -> Void)? = nil
    private let ownsViewModel: Bool
    @State private var vm = CardsVM()
    @State private var searchText = ""
    @State private var selectedCard: CreditCard?

    init(
        workspaceId: String,
        embedded: Bool = false,
        vm: CardsVM? = nil,
        onCardMutated: (() async -> Void)? = nil
    ) {
        self.workspaceId = workspaceId
        self.embedded = embedded
        self.onCardMutated = onCardMutated
        self.ownsViewModel = vm == nil
        _vm = State(initialValue: vm ?? CardsVM())
    }

    private var filteredCards: [CreditCard] {
        guard !searchText.isEmpty else { return vm.cards }
        return vm.cards.filter {
            $0.label.localizedCaseInsensitiveContains(searchText) ||
            ($0.lastFour?.contains(searchText) ?? false) ||
            ($0.network?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    var body: some View {
        Group {
            if embedded {
                cardsBody
            } else {
                NavigationStack {
                    cardsBody
                        .navigationTitle("Cards")
                        .navigationBarTitleDisplayMode(.large)
                }
            }
        }
        .task {
            guard ownsViewModel else { return }
            await vm.load(workspaceId: workspaceId)
        }
    }

    private var cardsBody: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            ZStack {
                if vm.isLoading && vm.cards.isEmpty {
                    ProgressView()
                        .tint(Theme.accent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.opacity)
                } else if let err = vm.errorMessage, vm.cards.isEmpty {
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
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { vm.showCreateSheet = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.accentText)
                }
            }
        }
        .sheet(isPresented: $vm.showCreateSheet) {
            CreateCardSheet(vm: vm, workspaceId: workspaceId) {
                await onCardMutated?()
            }
        }
        .sheet(item: $selectedCard) { card in
            CardDetailSheet(workspaceId: workspaceId, card: card) { body in
                let updated = try await vm.updateCard(workspaceId: workspaceId, cardId: card.id, body: body)
                await onCardMutated?()
                return updated
            }
        }
    }

    private var cardList: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                if vm.errorMessage != nil, !vm.cards.isEmpty {
                    SignalRefreshWarning(message: "Showing saved card data. Refresh failed.") {
                        Task { await vm.load(workspaceId: workspaceId) }
                    }
                    .padding(.horizontal, 20)
                }

                // Search bar pinned at top
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.faint)
                    TextField("Search by name, network, or last 4", text: $searchText)
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.ink)
                        .autocorrectionDisabled()
                        .autocapitalization(.none)
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.faint)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Theme.surface)
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.line, lineWidth: 1))
                )
                .padding(.horizontal, 20)
                .padding(.top, 4)

                if filteredCards.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 32))
                            .foregroundStyle(Theme.faint)
                        Text("No results for \"\(searchText)\"")
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.muted)
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
                                Task {
                                    if await vm.deleteCard(workspaceId: workspaceId, cardId: card.id) {
                                        await onCardMutated?()
                                    }
                                }
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
    let onCreated: () async -> Void
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case name, lastFour, limit
    }

    private let networks = [("", "None"), ("visa", "Visa"), ("mastercard", "MC"), ("amex", "Amex"), ("other", "Other")]

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 18) {
                        CardFormField(label: "Card Name *") {
                            TextField("e.g. Chase Sapphire", text: Binding(get: { vm.newLabel }, set: { vm.newLabel = $0 }))
                                .focused($focusedField, equals: .name)
                                .foregroundStyle(Theme.ink)
                        }

                        CardFormField(label: "Last 4 Digits") {
                            TextField("1234", text: Binding(get: { vm.newLastFour }, set: { vm.newLastFour = String($0.prefix(4)) }))
                                .keyboardType(.numberPad)
                                .focused($focusedField, equals: .lastFour)
                                .foregroundStyle(Theme.ink)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Network")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.muted)
                                .tracking(1).textCase(.uppercase)

                            HStack(spacing: 8) {
                                ForEach(networks, id: \.0) { val, label in
                                    Button {
                                        withAnimation(.snappy(duration: 0.2)) { vm.newNetwork = val }
                                    } label: {
                                        Text(label)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(vm.newNetwork == val ? Theme.buttonInk : Theme.muted)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 10)
                                            .background(RoundedRectangle(cornerRadius: 9)
                                                .fill(vm.newNetwork == val ? Theme.accent : Theme.surface))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        CardFormField(label: "Credit Limit (optional)") {
                            TextField("e.g. 50000", text: Binding(get: { vm.newLimitStr }, set: { vm.newLimitStr = $0 }))
                                .keyboardType(.numberPad)
                                .focused($focusedField, equals: .limit)
                                .foregroundStyle(Theme.ink)
                        }

                        if let err = vm.errorMessage {
                            Text(err)
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.expense)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Button {
                            Task {
                                if await vm.createCard(workspaceId: workspaceId) {
                                    await onCreated()
                                }
                            }
                        } label: {
                            Group {
                                if vm.isCreating {
                                    ProgressView().tint(Theme.buttonInk)
                                } else {
                                    Text("Add Card")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(Theme.buttonInk)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.accent))
                        }
                        .disabled(vm.newLabel.trimmingCharacters(in: .whitespaces).isEmpty || vm.isCreating)
                        .opacity(vm.newLabel.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
                    }
                    .padding(24)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("New Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { vm.showCreateSheet = false; vm.resetForm(); vm.errorMessage = nil }
                        .foregroundStyle(Theme.muted)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                        .foregroundStyle(Theme.accentText)
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(Theme.bg)
        .presentationCornerRadius(24)
        .onAppear { focusedField = .name; vm.errorMessage = nil }
    }
}

private struct CardFormField<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.muted)
                .tracking(1).textCase(.uppercase)
            content()
                .font(.system(size: 16))
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12)
                    .fill(Theme.surface)
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.line, lineWidth: 1)))
        }
    }
}

// MARK: - Empty / Error

struct CardsEmptyView: View {
    let onAdd: () -> Void
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "creditcard")
                .font(.system(size: 48))
                .foregroundStyle(Theme.faint)
            VStack(spacing: 8) {
                Text("No cards yet")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text("Add a credit card to track spending")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.muted)
            }
            Button(action: onAdd) {
                Text("Add Card")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.buttonInk)
                    .padding(.horizontal, 28).padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.accent))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct CardsErrorView: View {
    let message: String
    let onRetry: () -> Void
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundStyle(Theme.warning)
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
            Button("Retry", action: onRetry)
                .foregroundStyle(Theme.accentText)
                .font(.system(size: 15, weight: .semibold))
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

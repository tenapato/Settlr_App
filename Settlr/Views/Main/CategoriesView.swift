import Foundation
import Observation
import SwiftUI

// MARK: - ViewModel

@MainActor
@Observable
final class CategoriesVM {
    var categories: [Category] = []
    var summaryItems: [CategorySummary] = []
    var summary: SummaryResponse?
    var isLoading = false
    var isCreating = false
    var errorMessage: String?
    var selectedMonth: String = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        return f.string(from: Date())
    }()

    var newName = ""
    var newScope = "expense"
    var showCreateSheet = false

    private let api = APIClient.shared

    struct MergedCategory: Identifiable {
        let id: String
        let name: String
        let color: String?
        let totalCents: Int
    }

    var merged: [MergedCategory] {
        let summaryMap = Dictionary(
            summaryItems.compactMap { item -> (String, CategorySummary)? in
                guard let id = item.categoryId else { return nil }
                return (id, item)
            },
            uniquingKeysWith: { first, _ in first }
        )
        return categories.map { cat in
            MergedCategory(
                id: cat.id,
                name: cat.name,
                color: cat.color,
                totalCents: summaryMap[cat.id]?.totalCents ?? 0
            )
        }
        .sorted { $0.totalCents > $1.totalCents }
    }

    var maxCents: Int { merged.map(\.totalCents).max() ?? 1 }

    @MainActor
    func load(workspaceId: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            async let catsTask: CategoriesResponse = api.fetch(Endpoints.categories(workspaceId))
            async let summaryTask: SummaryResponse = api.fetch(
                Endpoints.summary(workspaceId) + MonthRangeQuery.summaryQuery(month: selectedMonth)
            )
            let (catsResp, summaryResp) = try await (catsTask, summaryTask)
            categories = catsResp.categories
            summary = summaryResp
            summaryItems = summaryResp.expensesByCategory
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func createCategory(workspaceId: String) async {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        isCreating = true
        defer { isCreating = false }
        struct Body: Encodable { let name: String; let scope: String }
        do {
            let resp: CategoriesResponse = try await api.fetch(
                Endpoints.categories(workspaceId),
                method: "POST",
                body: Body(name: name, scope: newScope)
            )
            newName = ""
            showCreateSheet = false
            categories = resp.categories
            // Reload summary so totals refresh
            let refreshed: SummaryResponse = try await api.fetch(
                Endpoints.summary(workspaceId) + MonthRangeQuery.summaryQuery(month: selectedMonth)
            )
            summary = refreshed
            summaryItems = refreshed.expensesByCategory
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func deleteCategory(workspaceId: String, categoryId: String) async {
        do {
            try await api.send(Endpoints.category(workspaceId, categoryId), method: "DELETE")
            categories.removeAll { $0.id == categoryId }
            summaryItems.removeAll { $0.categoryId == categoryId }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - View

struct CategoriesView: View {
    let workspaceId: String
    var embedded: Bool = false
    @State private var vm = CategoriesVM()

    var body: some View {
        Group {
            if embedded {
                categoriesBody
            } else {
                NavigationStack {
                    categoriesBody
                        .navigationTitle("Categories")
                        .navigationBarTitleDisplayMode(.large)
                }
            }
        }
        .task { await vm.load(workspaceId: workspaceId) }
        .onChange(of: vm.selectedMonth) { _, _ in
            Task { await vm.load(workspaceId: workspaceId) }
        }
    }

    private var categoriesBody: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                CatMonthPicker(selectedMonth: $vm.selectedMonth) {
                    Task { await vm.load(workspaceId: workspaceId) }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 8)

                ZStack {
                    if vm.isLoading && vm.categories.isEmpty {
                        SettlrPulseLoadingView(message: "Getting your categories")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .transition(.opacity)
                    } else if let err = vm.errorMessage, vm.categories.isEmpty {
                        CatErrorView(message: err) {
                            Task { await vm.load(workspaceId: workspaceId) }
                        }
                        .transition(.opacity)
                    } else if vm.categories.isEmpty {
                        CatEmptyView { vm.showCreateSheet = true }
                            .transition(.opacity)
                    } else {
                        categoryList
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.easeOut(duration: 0.22), value: vm.isLoading)
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    vm.showCreateSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.accentText)
                        .frame(width: 44, height: 44)
                }
            }
        }
        .sheet(isPresented: $vm.showCreateSheet) {
            CreateCategorySheet(vm: vm, workspaceId: workspaceId)
        }
    }

    private var categoryList: some View {
        ScrollView {
            VStack(spacing: 20) {
                if vm.isLoading {
                    SignalTraceLoadingView(lastUpdated: nil)
                        .padding(.horizontal, 24)
                }
                if vm.errorMessage != nil {
                    SignalRefreshWarning(message: "Showing saved category data. It may be from another month because refresh failed.") {
                        Task { await vm.load(workspaceId: workspaceId) }
                    }
                    .padding(.horizontal, 24)
                }
                if let summary = vm.summary {
                    SpendingBreakdownCard(summary: summary)
                        .padding(.horizontal, 24)
                }

                // Summary card
                let total = vm.merged.reduce(0) { $0 + $1.totalCents }
                if total > 0 {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Total spent")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.muted)
                                .tracking(1.2)
                                .textCase(.uppercase)
                            AmountLabel(cents: total, font: .system(size: 26, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.ink)
                        }
                        Spacer()
                        Text("\(vm.merged.count) categor\(vm.merged.count == 1 ? "y" : "ies")")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.muted)
                    }
                    .padding(.horizontal, 24)
                }

                // Category rows
                VStack(spacing: 0) {
                    ForEach(Array(vm.merged.enumerated()), id: \.element.id) { idx, cat in
                        CatRow(cat: cat, maxCents: vm.maxCents, rank: idx)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    Task { await vm.deleteCategory(workspaceId: workspaceId, categoryId: cat.id) }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }

                        if idx < vm.merged.count - 1 {
                            Divider()
                                .background(Theme.line)
                                .padding(.horizontal, 20)
                        }
                    }
                }
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Theme.line, lineWidth: 1)
                )
                .padding(.horizontal, 24)

                Spacer().frame(height: 130)
            }
            .padding(.top, 8)
        }
        .refreshable { await vm.load(workspaceId: workspaceId) }
    }
}

// MARK: - Category Row

private struct CatRow: View {
    let cat: CategoriesVM.MergedCategory
    let maxCents: Int
    let rank: Int
    @State private var animatedRatio: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var targetRatio: Double {
        guard maxCents > 0 else { return 0 }
        return Double(cat.totalCents) / Double(maxCents)
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(cat.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.ink)
                Spacer()
                AmountLabel(cents: cat.totalCents, font: .system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .contentTransition(.numericText(countsDown: true))
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.line).frame(height: 4)
                    Capsule()
                        .fill(Theme.expense.opacity(0.8))
                        .frame(width: max(6, geo.size.width * animatedRatio), height: 4)
                }
            }
            .frame(height: 4)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Theme.surface)
        .onAppear {
            if reduceMotion { animatedRatio = targetRatio }
            else {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.1 + Double(rank) * 0.06)) {
                    animatedRatio = targetRatio
                }
            }
        }
        .onChange(of: targetRatio) { _, new in
            if reduceMotion { animatedRatio = new }
            else { withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { animatedRatio = new } }
        }
    }
}

// MARK: - Create Sheet

private struct CreateCategorySheet: View {
    let vm: CategoriesVM
    let workspaceId: String
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()

                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Name")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                            .tracking(1)
                            .textCase(.uppercase)

                        TextField("e.g. Food, Transport…", text: Binding(
                            get: { vm.newName },
                            set: { vm.newName = $0 }
                        ))
                        .focused($focused)
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.ink)
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Theme.surface)
                                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.line, lineWidth: 1))
                        )
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Type")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                            .tracking(1)
                            .textCase(.uppercase)

                        HStack(spacing: 10) {
                            ForEach([("expense", "Expense"), ("income", "Income")], id: \.0) { val, label in
                                Button {
                                    if reduceMotion { vm.newScope = val }
                                    else { withAnimation(.snappy(duration: 0.2)) { vm.newScope = val } }
                                } label: {
                                    Text(label)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(vm.newScope == val ? Theme.buttonInk : Theme.muted)
                                        .frame(maxWidth: .infinity)
                                        .frame(minHeight: 44)
                                        .background(
                                            RoundedRectangle(cornerRadius: 10)
                                                .fill(vm.newScope == val ? Theme.accent : Theme.surface)
                                        )
                                }
                                .buttonStyle(.plain)
                                .accessibilityValue(vm.newScope == val ? "Selected" : "Not selected")
                                .accessibilityAddTraits(vm.newScope == val ? .isSelected : [])
                            }
                        }
                    }

                    Button {
                        Task { await vm.createCategory(workspaceId: workspaceId) }
                    } label: {
                        HStack {
                            if vm.isCreating {
                                ProgressView().tint(Theme.buttonInk)
                            } else {
                                Text("Create Category")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Theme.buttonInk)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Theme.accent)
                        )
                    }
                    .disabled(vm.newName.trimmingCharacters(in: .whitespaces).isEmpty || vm.isCreating)
                    .opacity(vm.newName.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)

                    Spacer()
                }
                .padding(24)
            }
            .navigationTitle("New Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { vm.showCreateSheet = false }
                        .foregroundStyle(Theme.muted)
                }
            }
        }
        .presentationDetents([.height(320)])
        .presentationBackground(Theme.bg)
        .presentationCornerRadius(24)
        .onAppear { focused = true }
    }
}

// MARK: - Empty / Error

private struct CatEmptyView: View {
    let onCreate: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "tag")
                .font(.system(size: 40))
                .foregroundStyle(Theme.faint)
            Text("No expenses this month")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.muted)
            Text("Create a category to organize new transactions.")
                .font(.subheadline)
                .foregroundStyle(Theme.faint)
                .multilineTextAlignment(.center)
            Button("Create category", action: onCreate)
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct CatErrorView: View {
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
                .frame(minWidth: 44, minHeight: 44)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Month Picker

private struct CatMonthPicker: View {
    @Binding var selectedMonth: String
    let onChanged: () -> Void

    var body: some View {
        HStack {
            Button { change(by: -1) } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 44, height: 44)
            }
            Spacer()
            Button {
                let f = DateFormatter(); f.dateFormat = "yyyy-MM"
                selectedMonth = f.string(from: Date())
                onChanged()
            } label: {
                Text(displayLabel)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(minHeight: 44)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.2), value: selectedMonth)
            }
            .buttonStyle(.plain)
            Spacer()
            Button { change(by: 1) } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.vertical, 12)
    }

    private var displayLabel: String {
        let parts = selectedMonth.split(separator: "-")
        guard parts.count == 2, let y = Int(parts[0]), let m = Int(parts[1]) else { return selectedMonth }
        var comps = DateComponents(); comps.year = y; comps.month = m; comps.day = 1
        guard let date = Calendar.current.date(from: comps) else { return selectedMonth }
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"
        return f.string(from: date)
    }

    private func change(by delta: Int) {
        let parts = selectedMonth.split(separator: "-")
        guard parts.count == 2, let y = Int(parts[0]), let m = Int(parts[1]) else { return }
        var comps = DateComponents(); comps.year = y; comps.month = m + delta; comps.day = 1
        guard let date = Calendar.current.date(from: comps) else { return }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM"
        selectedMonth = f.string(from: date)
        onChanged()
    }
}

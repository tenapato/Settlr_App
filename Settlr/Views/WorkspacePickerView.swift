import SwiftUI

struct WorkspacePickerView: View {
    @Environment(AppState.self) private var appState
    @State private var vm = WorkspacePickerVM()

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Image("SettlrLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 48, height: 48)
                        .accessibilityHidden(true)
                    Text("Your workspaces")
                        .font(.largeTitle.bold())
                        .foregroundStyle(Theme.ink)
                    Text("Choose where you want to work.")
                        .font(.body)
                        .foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, 24)
                .padding(.top, 44)
                .padding(.bottom, 24)

                if vm.isLoading {
                    SettlrPulseLoadingView(message: "Loading your workspaces")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = vm.errorMessage, vm.workspaces.isEmpty {
                    workspaceError(error)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(vm.workspaces) { workspace in
                                WorkspaceRow(workspace: workspace) {
                                    appState.select(workspace)
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 20)
                    }
                }

                if vm.errorMessage == nil || !vm.workspaces.isEmpty {
                    Button { vm.showCreateSheet = true } label: {
                        Label("Create workspace", systemImage: "plus")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                }

                Button(role: .destructive) {
                    Task { await appState.signOut() }
                } label: {
                    Text("Sign out")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
        }
        .task { await vm.load() }
        .sheet(isPresented: $vm.showCreateSheet) {
            CreateWorkspaceSheet(vm: vm) { workspace in
                appState.select(workspace)
            }
        }
    }

    private func workspaceError(_ message: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "wifi.exclamationmark")
                .font(.title)
                .foregroundStyle(Theme.warning)
            Text("Workspaces unavailable")
                .font(.headline)
                .foregroundStyle(Theme.ink)
            Text("We couldn't load your workspaces. Your account is still signed in.")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.footnote)
                .foregroundStyle(Theme.faint)
                .multilineTextAlignment(.center)
            Button("Retry") { Task { await vm.load() } }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, 4)
            Spacer()
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct WorkspaceRow: View {
    let workspace: WorkspaceWithRole
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Theme.accent.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Text(String(workspace.name.prefix(1)).uppercased())
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.accentText)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(workspace.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    Text(workspace.role.capitalized)
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.faint)
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Theme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(Theme.line, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(workspace.name), \(workspace.role)")
        .accessibilityHint("Selects this workspace")
    }
}

private struct CreateWorkspaceSheet: View {
    @Bindable var vm: WorkspacePickerVM
    let onCreated: (WorkspaceWithRole) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()

                VStack(spacing: 20) {
                    StyledTextField(placeholder: "Workspace name", text: $vm.newWorkspaceName)
                        .padding(.horizontal, 24)
                        .padding(.top, 8)

                    if let error = vm.errorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(Theme.expense)
                            .padding(.horizontal, 28)
                    }

                    Spacer()
                }
            }
            .navigationTitle("New Workspace")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.muted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task {
                            if let ws = await vm.createWorkspace() {
                                onCreated(ws)
                            }
                        }
                    }
                    .foregroundStyle(Theme.accentText)
                    .disabled(vm.isCreating)
                }
            }
        }
        .presentationBackground(Theme.bg)
        .interactiveDismissDisabled(vm.isCreating)
    }
}

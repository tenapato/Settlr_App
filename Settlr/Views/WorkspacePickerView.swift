import SwiftUI

struct WorkspacePickerView: View {
    @Environment(AppState.self) private var appState
    @State private var vm = WorkspacePickerVM()

    var body: some View {
        ZStack {
            Color(hex: "#0e0f11").ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                // Header
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your Workspaces")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Color(hex: "#ecedee"))
                    Text("Select a workspace to continue")
                        .font(.system(size: 15))
                        .foregroundStyle(Color(hex: "#8e9197"))
                }
                .padding(.horizontal, 24)
                .padding(.top, 60)
                .padding(.bottom, 32)

                if vm.isLoading {
                    Spacer()
                    ProgressView()
                        .tint(Color(hex: "#c8ff5a"))
                        .frame(maxWidth: .infinity)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(vm.workspaces) { workspace in
                                WorkspaceRow(workspace: workspace) {
                                    appState.select(workspace)
                                }
                            }

                            Button {
                                vm.showCreateSheet = true
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 22))
                                        .foregroundStyle(Color(hex: "#c8ff5a"))
                                    Text("New Workspace")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundStyle(Color(hex: "#c8ff5a"))
                                    Spacer()
                                }
                                .padding(18)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .strokeBorder(Color(hex: "#c8ff5a").opacity(0.3), lineWidth: 1)
                                )
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 40)
                    }
                }

                // Sign out
                Button {
                    Task { await appState.signOut() }
                } label: {
                    Text("Sign Out")
                        .font(.system(size: 14))
                        .foregroundStyle(Color(hex: "#8e9197"))
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 32)
                }
            }
        }
        .task { await vm.load() }
        .sheet(isPresented: $vm.showCreateSheet) {
            CreateWorkspaceSheet(vm: vm) { workspace in
                appState.select(workspace)
            }
        }
        .preferredColorScheme(.dark)
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
                        .fill(Color(hex: "#c8ff5a").opacity(0.12))
                        .frame(width: 44, height: 44)
                    Text(String(workspace.name.prefix(1)).uppercased())
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color(hex: "#c8ff5a"))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(workspace.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color(hex: "#ecedee"))
                    Text(workspace.role.capitalized)
                        .font(.system(size: 13))
                        .foregroundStyle(Color(hex: "#8e9197"))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(hex: "#5a5d63"))
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(hex: "#15171a"))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(Color(hex: "#2a2d32"), lineWidth: 1)
                    )
            )
        }
    }
}

private struct CreateWorkspaceSheet: View {
    @Bindable var vm: WorkspacePickerVM
    let onCreated: (WorkspaceWithRole) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#0e0f11").ignoresSafeArea()

                VStack(spacing: 20) {
                    StyledTextField(placeholder: "Workspace name", text: $vm.newWorkspaceName)
                        .padding(.horizontal, 24)
                        .padding(.top, 8)

                    if let error = vm.errorMessage {
                        Text(error)
                            .font(.system(size: 13))
                            .foregroundStyle(Color(hex: "#ff6b6b"))
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
                        .foregroundStyle(Color(hex: "#8e9197"))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task {
                            if let ws = await vm.createWorkspace() {
                                onCreated(ws)
                            }
                        }
                    }
                    .foregroundStyle(Color(hex: "#c8ff5a"))
                    .disabled(vm.isCreating)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var showSignOutConfirm = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#0e0f11").ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // User section
                        if let user = appState.currentUser {
                            SectionCard {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Account")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Color(hex: "#8e9197"))
                                        .textCase(.uppercase)
                                        .tracking(0.8)

                                    HStack(spacing: 14) {
                                        ZStack {
                                            Circle()
                                                .fill(Color(hex: "#c8ff5a").opacity(0.12))
                                                .frame(width: 48, height: 48)
                                            Text(String(user.name.prefix(1)).uppercased())
                                                .font(.system(size: 20, weight: .semibold))
                                                .foregroundStyle(Color(hex: "#c8ff5a"))
                                        }
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(user.name)
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundStyle(Color(hex: "#ecedee"))
                                            Text(user.email)
                                                .font(.system(size: 13))
                                                .foregroundStyle(Color(hex: "#8e9197"))
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }

                        // Workspace section
                        if let workspace = appState.activeWorkspace {
                            SectionCard {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Workspace")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Color(hex: "#8e9197"))
                                        .textCase(.uppercase)
                                        .tracking(0.8)

                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(workspace.name)
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundStyle(Color(hex: "#ecedee"))
                                            Text(workspace.kind.capitalized)
                                                .font(.system(size: 13))
                                                .foregroundStyle(Color(hex: "#8e9197"))
                                        }
                                        Spacer()
                                        Text(workspace.role.capitalized)
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundStyle(Color(hex: "#c8ff5a"))
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 4)
                                            .background(
                                                Capsule().fill(Color(hex: "#c8ff5a").opacity(0.12))
                                            )
                                    }

                                    Button {
                                        appState.activeWorkspace = nil
                                    } label: {
                                        HStack(spacing: 10) {
                                            Image(systemName: "arrow.left.arrow.right")
                                                .font(.system(size: 14, weight: .semibold))
                                            Text("Switch Workspace")
                                                .font(.system(size: 15, weight: .medium))
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundStyle(Color(hex: "#5a5d63"))
                                        }
                                        .foregroundStyle(Color(hex: "#ecedee"))
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 12)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(Color(hex: "#1c1f23"))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 12)
                                                        .strokeBorder(Color(hex: "#3a3d44"), lineWidth: 1)
                                                )
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.top, 4)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            TelegramSettingsSection(
                                workspaceId: workspace.id,
                                role: workspace.role
                            )
                        }

                        // Sign out
                        SectionCard {
                            Button {
                                showSignOutConfirm = true
                            } label: {
                                HStack {
                                    Image(systemName: "rectangle.portrait.and.arrow.right")
                                        .font(.system(size: 16))
                                    Text("Sign Out")
                                        .font(.system(size: 16, weight: .medium))
                                    Spacer()
                                }
                                .foregroundStyle(Color(hex: "#ff6b6b"))
                            }
                        }

                        Spacer().frame(height: 60)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color(hex: "#c8ff5a"))
                }
            }
            .confirmationDialog("Sign Out", isPresented: $showSignOutConfirm) {
                Button("Sign Out", role: .destructive) {
                    Task { await appState.signOut() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You'll need to sign in again to access your workspaces.")
            }
        }
        .preferredColorScheme(.dark)
    }
}

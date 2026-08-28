import SwiftUI

enum AppPreferenceKey {
    static let saveCapturedReceiptsToPhotos = "saveCapturedReceiptsToPhotos"
    static let receiptParser = ReceiptParserPreference.storageKey
}

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var showSignOutConfirm = false
    @State private var showDeleteAccountConfirm = false
    @State private var isDeletingAccount = false
    @State private var deleteAccountError: String?
    @AppStorage(AppPreferenceKey.saveCapturedReceiptsToPhotos)
    private var saveCapturedReceiptsToPhotos = true
    @AppStorage(AppPreferenceKey.receiptParser)
    private var receiptParser = ReceiptParserPreference.automatic.rawValue
    @AppStorage("settlr.appearance")
    private var appearanceRawValue = SettlrAppearance.dark.rawValue

    private var appearance: SettlrAppearance {
        SettlrAppearance(rawValue: appearanceRawValue) ?? .dark
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // User section
                        if let user = appState.currentUser {
                            SectionCard {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Account")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Theme.muted)
                                        .textCase(.uppercase)
                                        .tracking(0.8)

                                    HStack(spacing: 14) {
                                        ZStack {
                                            Circle()
                                                .fill(Theme.accent.opacity(0.12))
                                                .frame(width: 48, height: 48)
                                            Text(String(user.name.prefix(1)).uppercased())
                                                .font(.system(size: 20, weight: .semibold))
                                                .foregroundStyle(Theme.accentText)
                                        }
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(user.name)
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundStyle(Theme.ink)
                                            Text(user.email)
                                                .font(.system(size: 13))
                                                .foregroundStyle(Theme.muted)
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }

                        SectionCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Appearance")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Theme.muted)
                                    .textCase(.uppercase)
                                    .tracking(0.8)

                                Picker("Appearance", selection: $appearanceRawValue) {
                                    ForEach(SettlrAppearance.allCases) { option in
                                        Text(option.title).tag(option.rawValue)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .tint(Theme.accent)
                                .accessibilityValue(appearance.title)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        // Workspace section
                        if let workspace = appState.activeWorkspace {
                            SectionCard {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Workspace")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Theme.muted)
                                        .textCase(.uppercase)
                                        .tracking(0.8)

                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(workspace.name)
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundStyle(Theme.ink)
                                            Text(workspace.kind.capitalized)
                                                .font(.system(size: 13))
                                                .foregroundStyle(Theme.muted)
                                        }
                                        Spacer()
                                        Text(workspace.role.capitalized)
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundStyle(Theme.accentText)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 4)
                                            .background(
                                                Capsule().fill(Theme.accent.opacity(0.12))
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
                                                .foregroundStyle(Theme.faint)
                                        }
                                        .foregroundStyle(Theme.ink)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 12)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(Theme.surface2)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 12)
                                                        .strokeBorder(Theme.line, lineWidth: 1)
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

                        SectionCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Receipts")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Theme.muted)
                                    .textCase(.uppercase)
                                    .tracking(0.8)

                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text("Receipt parsing")
                                                .font(.system(size: 16, weight: .medium))
                                                .foregroundStyle(Theme.ink)
                                            Text("Automatic keeps parsing on your device when possible.")
                                                .font(.system(size: 13))
                                                .foregroundStyle(Theme.muted)
                                        }
                                        Spacer()
                                        Picker("Receipt parsing", selection: $receiptParser) {
                                            ForEach(ReceiptParserPreference.allCases) { preference in
                                                Text(preference.displayName)
                                                    .tag(preference.rawValue)
                                            }
                                        }
                                        .labelsHidden()
                                        .tint(Theme.accent)
                                    }

                                    if receiptParser == ReceiptParserPreference.serverPhoto.rawValue {
                                        Text("Experimental")
                                            .font(.system(size: 9, weight: .bold))
                                            .textCase(.uppercase)
                                            .foregroundStyle(Theme.accentText)
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 3)
                                            .background(
                                                Theme.accent.opacity(0.14),
                                                in: Capsule()
                                            )
                                            .accessibilityLabel("Experimental receipt parser")
                                    }

                                    if receiptParser == ReceiptParserPreference.onDevice.rawValue {
                                        Text("Receipt text stays on this phone. If the device model is unavailable, you'll be offered Automatic or On server instead.")
                                            .font(.system(size: 12))
                                            .foregroundStyle(Theme.muted)
                                    } else if receiptParser == ReceiptParserPreference.server.rawValue {
                                        Text("Only recognized receipt text is sent for parsing. The photo stays on this phone.")
                                            .font(.system(size: 12))
                                            .foregroundStyle(Theme.muted)
                                    } else if receiptParser == ReceiptParserPreference.serverPhoto.rawValue {
                                        Text("The receipt photo and recognized text are sent securely to the server for AI parsing. The server does not store the photo. If Save captures to Photos is enabled, a local copy is saved to your photo library. The AI provider does not use it to train its models.")
                                            .font(.system(size: 12))
                                            .foregroundStyle(Theme.muted)
                                    }
                                }

                                Divider().overlay(Theme.line)

                                Toggle(isOn: $saveCapturedReceiptsToPhotos) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("Save captures to Photos")
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundStyle(Theme.ink)
                                        Text("Keep a copy of new receipt photos in your library.")
                                            .font(.system(size: 13))
                                            .foregroundStyle(Theme.muted)
                                    }
                                }
                                .tint(Theme.accent)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
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
                                .foregroundStyle(Theme.expense)
                            }
                        }

                        // Delete account
                        SectionCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Danger Zone")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Theme.muted)
                                    .textCase(.uppercase)
                                    .tracking(0.8)

                                if let error = deleteAccountError {
                                    Text(error)
                                        .font(.system(size: 13))
                                        .foregroundStyle(Theme.expense)
                                }

                                Button {
                                    showDeleteAccountConfirm = true
                                } label: {
                                    HStack {
                                        Image(systemName: "person.crop.circle.badge.minus")
                                            .font(.system(size: 16))
                                        Text("Delete Account")
                                            .font(.system(size: 16, weight: .medium))
                                        Spacer()
                                        if isDeletingAccount {
                                            ProgressView().tint(Theme.expense)
                                        }
                                    }
                                    .foregroundStyle(Theme.expense)
                                }
                                .disabled(isDeletingAccount)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
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
                        .foregroundStyle(Theme.accentText)
                }
            }
            .confirmationDialog("Sign Out", isPresented: $showSignOutConfirm) {
                Button("Sign Out", role: .destructive) {
                    Task { await appState.signOut() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                // Queued splits are kept, not deleted — they're stamped with the
                // user id, so they stay invisible to anyone else who signs in on
                // this phone and upload themselves when their owner returns.
                let waiting = appState.currentUser.map {
                    PendingSplitQueue.shared.pendingCount(userId: $0.id)
                } ?? 0
                Text(
                    waiting > 0
                        ? "\(waiting) split\(waiting == 1 ? "" : "s") haven't uploaded yet. They'll still be here when you sign back in."
                        : "You'll need to sign in again to access your workspaces."
                )
            }
            .confirmationDialog("Delete Account", isPresented: $showDeleteAccountConfirm, titleVisibility: .visible) {
                Button("Delete My Account", role: .destructive) {
                    Task {
                        isDeletingAccount = true
                        deleteAccountError = nil
                        do {
                            try await appState.deleteAccount()
                        } catch {
                            isDeletingAccount = false
                            deleteAccountError = error.localizedDescription
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes your account and all workspaces you own. This cannot be undone.")
            }
        }
    }
}

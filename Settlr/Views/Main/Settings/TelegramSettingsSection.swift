import SwiftUI

struct TelegramSettingsSection: View {
    let workspaceId: String
    let role: String

    @State private var vm = TelegramSettingsVM()
    @State private var showDisconnectConfirm = false

    private var canManage: Bool {
        role == "owner" || role == "admin" || role == "member"
    }

    var body: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Theme.accent.opacity(0.12))
                            .frame(width: 38, height: 38)
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.accentText)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Telegram")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                        Text("Log expenses and income from chat.")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.muted)
                    }

                    Spacer(minLength: 8)

                    statusBadge
                }

                if vm.isLoading && vm.status == nil {
                    ProgressView()
                        .tint(Theme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                } else if vm.isConnected {
                    connectedContent
                } else {
                    disconnectedContent
                }

                if let error = vm.errorMessage {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.expense)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task {
            await vm.load(workspaceId: workspaceId)
        }
        .confirmationDialog("Disconnect Telegram?", isPresented: $showDisconnectConfirm) {
            Button("Disconnect", role: .destructive) {
                Task { await vm.disconnect(workspaceId: workspaceId) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You will need a new link to connect again.")
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        Text(vm.isConnected ? "Connected" : "Not connected")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(vm.isConnected ? Theme.income : Theme.muted)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(
                    (vm.isConnected ? Theme.income : Theme.muted).opacity(0.12)
                )
            )
    }

    @ViewBuilder
    private var connectedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                if let username = vm.status?.telegramUsername, !username.isEmpty {
                    HStack(spacing: 4) {
                        Text("Account")
                            .foregroundStyle(Theme.muted)
                        Text("@\(username)")
                            .foregroundStyle(Theme.ink)
                            .fontWeight(.medium)
                    }
                    .font(.system(size: 14))
                } else {
                    Text("Linked chat (no username)")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.muted)
                }

                if let connectedAt = vm.status?.connectedAt {
                    Text("Since \(formatTelegramDate(connectedAt))")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.faint)
                }
            }

            if canManage {
                Button {
                    showDisconnectConfirm = true
                } label: {
                    HStack(spacing: 8) {
                        if vm.isDisconnecting {
                            ProgressView()
                                .tint(Theme.expense)
                                .scaleEffect(0.85)
                        } else {
                            Image(systemName: "link.badge.minus")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        Text("Disconnect")
                            .font(.system(size: 15, weight: .medium))
                    }
                    .foregroundStyle(Theme.expense)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
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
                .disabled(vm.isDisconnecting)
            }
        }
    }

    @ViewBuilder
    private var disconnectedContent: some View {
        Text("Connect Telegram from the Settlr web panel to log expenses and income by chat.")
            .font(.system(size: 13))
            .foregroundStyle(Theme.muted)
    }
}

private func formatTelegramDate(_ raw: String) -> String {
    let formats = ["yyyy-MM-dd'T'HH:mm:ss.SSSZ", "yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd"]
    let out = DateFormatter()
    out.dateStyle = .medium
    out.timeStyle = .short
    for fmt in formats {
        let f = DateFormatter()
        f.dateFormat = fmt
        if let d = f.date(from: raw) { return out.string(from: d) }
    }
    if let ms = Double(raw) {
        return out.string(from: Date(timeIntervalSince1970: ms / 1000))
    }
    return String(raw.prefix(16))
}

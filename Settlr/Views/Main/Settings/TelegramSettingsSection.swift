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
                            .fill(Color(hex: "#c8ff5a").opacity(0.12))
                            .frame(width: 38, height: 38)
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color(hex: "#c8ff5a"))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Telegram")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color(hex: "#ecedee"))
                        Text("Log expenses and income from chat.")
                            .font(.system(size: 13))
                            .foregroundStyle(Color(hex: "#8e9197"))
                    }

                    Spacer(minLength: 8)

                    statusBadge
                }

                if vm.isLoading && vm.status == nil {
                    ProgressView()
                        .tint(Color(hex: "#c8ff5a"))
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
                        .foregroundStyle(Color(hex: "#ff6b6b"))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task {
            await vm.load(workspaceId: workspaceId)
        }
        .task(id: vm.pendingConnect) {
            guard vm.pendingConnect else { return }
            await vm.pollWhilePending(workspaceId: workspaceId)
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
            .foregroundStyle(vm.isConnected ? Color(hex: "#5ddf8a") : Color(hex: "#8e9197"))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(
                    (vm.isConnected ? Color(hex: "#5ddf8a") : Color(hex: "#8e9197")).opacity(0.12)
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
                            .foregroundStyle(Color(hex: "#8e9197"))
                        Text("@\(username)")
                            .foregroundStyle(Color(hex: "#ecedee"))
                            .fontWeight(.medium)
                    }
                    .font(.system(size: 14))
                } else {
                    Text("Linked chat (no username)")
                        .font(.system(size: 14))
                        .foregroundStyle(Color(hex: "#8e9197"))
                }

                if let connectedAt = vm.status?.connectedAt {
                    Text("Since \(formatTelegramDate(connectedAt))")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: "#5a5d63"))
                }
            }

            if canManage {
                Button {
                    showDisconnectConfirm = true
                } label: {
                    HStack(spacing: 8) {
                        if vm.isDisconnecting {
                            ProgressView()
                                .tint(Color(hex: "#ff6b6b"))
                                .scaleEffect(0.85)
                        } else {
                            Image(systemName: "link.badge.minus")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        Text("Disconnect")
                            .font(.system(size: 15, weight: .medium))
                    }
                    .foregroundStyle(Color(hex: "#ff6b6b"))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
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
                .disabled(vm.isDisconnecting)
            }
        }
    }

    @ViewBuilder
    private var disconnectedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Generate a one-time link, open it in Telegram, and tap Start on the bot. The link expires in 24 hours.")
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: "#8e9197"))

            if let connectUrl = vm.connectUrl {
                VStack(alignment: .leading, spacing: 10) {
                    Text("WAITING FOR CONNECTION")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color(hex: "#5a5d63"))
                        .tracking(0.8)

                    Text(connectUrl)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color(hex: "#8e9197"))
                        .lineLimit(3)

                    HStack(spacing: 10) {
                        Button {
                            UIPasteboard.general.string = connectUrl
                        } label: {
                            secondaryButtonLabel(title: "Copy link", icon: "doc.on.doc")
                        }
                        .buttonStyle(.plain)

                        Button {
                            Task { await vm.openConnectUrl() }
                        } label: {
                            secondaryButtonLabel(title: "Open Telegram", icon: "arrow.up.right")
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(hex: "#1c1f23"))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color(hex: "#2a2d32"), lineWidth: 1)
                        )
                )
            }

            if canManage {
                Button {
                    Task { await vm.connect(workspaceId: workspaceId) }
                } label: {
                    HStack(spacing: 8) {
                        if vm.isConnecting {
                            ProgressView()
                                .tint(Color(hex: "#0e0f11"))
                                .scaleEffect(0.85)
                        } else {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        Text(vm.connectUrl == nil ? "Connect Telegram" : "Link generated")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(Color(hex: "#0e0f11"))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(hex: "#c8ff5a"))
                    )
                }
                .buttonStyle(.plain)
                .disabled(vm.isConnecting || (vm.pendingConnect && vm.connectUrl != nil))
            } else {
                Text("Members can connect Telegram for this workspace.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: "#5a5d63"))
            }
        }
    }

    private func secondaryButtonLabel(title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
            Text(title)
                .font(.system(size: 13, weight: .medium))
        }
        .foregroundStyle(Color(hex: "#ecedee"))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(hex: "#15171a"))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color(hex: "#3a3d44"), lineWidth: 1)
                )
        )
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

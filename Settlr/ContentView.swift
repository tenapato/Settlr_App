import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase
    private let network = NetworkMonitor.shared

    var body: some View {
        @Bindable var appState = appState
        return Group {
            if appState.isLoading {
                SplashView()
            } else if let notice = appState.deactivation {
                // Ahead of the auth check: a deactivated account may or may not
                // still have a decoded user, and either way the login screen is
                // the wrong answer — signing in again cannot succeed.
                AccountDeactivatedView(reason: notice.reason) {
                    await appState.signOut()
                }
            } else if !appState.isAuthenticated {
                LoginView()
            } else if appState.activeWorkspace == nil {
                if appState.isRestoringWorkspace {
                    SplashView()
                } else {
                    WorkspacePickerView()
                }
            } else {
                MainTabView()
            }
        }
        .task {
            await appState.initialize()
            // Anything composed while offline goes out as soon as there is a
            // session to send it under.
            NetworkMonitor.shared.onBecameReachable = { flushPendingSplits() }
            flushPendingSplits()
        }
        .onChange(of: appState.isAuthenticated) { _, authenticated in
            if authenticated {
                Task { await appState.restoreLastWorkspaceIfNeeded() }
                // Signing back in is what unblocks a queue that stopped on a 401.
                flushPendingSplits()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // The app has no background modes, so coming to the foreground is
            // the only other moment a queued split can move — and the only
            // cheap moment to notice an admin changed this account's features
            // or switched it off, short of waiting for a cold launch.
            guard phase == .active else { return }
            flushPendingSplits()
            Task { await appState.refreshSession() }
        }
        // A shared split belongs to someone else's workspace, so it opens over
        // whatever is on screen rather than inside the workspace navigation.
        .sheet(
            isPresented: Binding(
                get: { appState.pendingSplitShareToken != nil },
                set: { if !$0 { appState.pendingSplitShareToken = nil } }
            )
        ) {
            if let token = appState.pendingSplitShareToken {
                PublicSplitClaimView(shareToken: token)
                    .environment(appState)
            }
        }
    }

    private func flushPendingSplits() {
        guard let userId = appState.currentUser?.id else { return }
        Task { await PendingSplitQueue.shared.flush(userId: userId) }
    }
}

private struct SplashView: View {
    var body: some View {
        ZStack {
            Color(hex: "#0e0f11").ignoresSafeArea()
            VStack(spacing: 12) {
                Image("SettlrLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)
                Text("Settlr")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Color(hex: "#ecedee"))
            }
        }
    }
}

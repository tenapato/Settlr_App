import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        return Group {
            if appState.isLoading {
                SplashView()
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
        }
        .onChange(of: appState.isAuthenticated) { _, authenticated in
            if authenticated {
                Task { await appState.restoreLastWorkspaceIfNeeded() }
            }
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

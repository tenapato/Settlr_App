import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
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

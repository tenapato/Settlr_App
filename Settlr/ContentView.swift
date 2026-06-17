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
                WorkspacePickerView()
            } else {
                MainTabView()
            }
        }
        .task {
            await appState.initialize()
        }
    }
}

private struct SplashView: View {
    var body: some View {
        ZStack {
            Color(hex: "#0e0f11").ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: "creditcard.and.123")
                    .font(.system(size: 52, weight: .light))
                    .foregroundStyle(Color(hex: "#c8ff5a"))
                Text("Settlr")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Color(hex: "#ecedee"))
            }
        }
    }
}

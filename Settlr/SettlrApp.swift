import SwiftUI

@main
struct SettlrApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    // `settlr://` also carries OAuth callbacks, but those are
                    // consumed by ASWebAuthenticationSession and never reach here.
                    if let token = AppState.splitShareToken(from: url) {
                        appState.pendingSplitShareToken = token
                    }
                }
        }
    }
}

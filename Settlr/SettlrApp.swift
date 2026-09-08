import SwiftUI

@main
struct SettlrApp: App {
    @State private var appState = AppState()
    @AppStorage("settlr.appearance") private var appearanceRawValue = SettlrAppearance.dark.rawValue

    private var appearance: SettlrAppearance {
        SettlrAppearance(rawValue: appearanceRawValue) ?? .dark
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .preferredColorScheme(appearance.colorScheme)
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

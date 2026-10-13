import SwiftUI
import UserNotifications
import UIKit

struct PushPreferences: Codable, Equatable {
    var enabled = false
    var splitUpdates = true
    var cardReminders = true
}

@MainActor
@Observable
final class PushNotifications {
    static let shared = PushNotifications()
    private(set) var preferences = PushPreferences()
    private(set) var authorization: UNAuthorizationStatus = .notDetermined
    private(set) var isBusy = false
    var errorMessage: String?
    struct Destination: Equatable {
        let recipientID: String
        let workspaceID: String
        let splitID: String?
        let kind: String
    }
    var destination: Destination?
    private(set) var userID: String?
    private var deviceToken: String?
    private var needsReconcile = false
    private func finishOperation() {
        isBusy = false
        if needsReconcile {
            needsReconcile = false
            Task { await reconcile(userID: userID) }
        }
    }
    private let defaults = UserDefaults.standard
    private let center = UNUserNotificationCenter.current()
    private var installationID: String {
        if let value = defaults.string(forKey: "settlr.push.installation") { return value }
        let value = UUID().uuidString
        defaults.set(value, forKey: "settlr.push.installation")
        return value
    }
    private func save() {
        guard let userID else { return }
        defaults.set(try? JSONEncoder().encode(preferences), forKey: "settlr.push.\(userID)")
    }
    var canPresent: Bool { userID != nil && preferences.enabled && authorization != .denied }

    func reconcile(userID: String?) async {
        if self.userID != userID {
            self.userID = userID
            preferences = userID.flatMap { defaults.data(forKey: "settlr.push.\($0)") }
                .flatMap { try? JSONDecoder().decode(PushPreferences.self, from: $0) } ?? PushPreferences()
            errorMessage = nil
        }
        guard !isBusy else { needsReconcile = true; return }
        isBusy = true
        defer { finishOperation() }
        authorization = await center.notificationSettings().authorizationStatus
        guard self.userID == userID, userID != nil, !Task.isCancelled else { return }
        do {
            if preferences.enabled && authorization != .denied && authorization != .notDetermined {
                UIApplication.shared.registerForRemoteNotifications()
                if deviceToken != nil { try await sync() }
            } else {
                // Also retries a removal after a failed/offline sign-out.
                try await APIClient.shared.send("/api/push/devices/\(installationID)", method: "DELETE")
            }
        } catch { errorMessage = error.localizedDescription }
    }

    func setEnabled(_ enabled: Bool) async {
        guard !isBusy, let expectedUserID = userID else { return }
        isBusy = true
        errorMessage = nil
        defer { finishOperation() }
        do {
            if enabled {
                let allowed = try await center.requestAuthorization(options: [.alert, .sound])
                authorization = await center.notificationSettings().authorizationStatus
                guard allowed, self.userID == expectedUserID, !Task.isCancelled else { return }
                preferences.enabled = true
                save()
                UIApplication.shared.registerForRemoteNotifications()
                if deviceToken != nil { try await sync() }
            } else {
                // Keep the switch on if the server could not confirm the opt-out.
                try await APIClient.shared.send("/api/push/devices/\(installationID)", method: "DELETE")
                guard self.userID == expectedUserID else { return }
                preferences.enabled = false
                save()
                center.removeAllDeliveredNotifications()
            }
        } catch { errorMessage = error.localizedDescription }
    }

    func setCategory(splitUpdates: Bool? = nil, cardReminders: Bool? = nil) async {
        guard !isBusy else { return }
        let expectedUserID = userID
        let previous = preferences
        isBusy = true
        errorMessage = nil
        defer { finishOperation() }
        preferences.splitUpdates = splitUpdates ?? preferences.splitUpdates
        preferences.cardReminders = cardReminders ?? preferences.cardReminders
        do {
            try await sync()
            save()
        } catch {
            guard userID == expectedUserID else { return }
            preferences = previous
            errorMessage = error.localizedDescription
        }
    }

    func received(token: Data) async {
        deviceToken = token.map { String(format: "%02x", $0) }.joined()
        guard preferences.enabled, userID != nil else { return }
        guard !isBusy else { needsReconcile = true; return }
        isBusy = true
        defer { finishOperation() }
        do { try await sync(); errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }

    private func sync() async throws {
        guard preferences.enabled, let deviceToken, userID != nil else { return }
        struct Registration: Encodable {
            let installationId: String
            let token: String
            let environment: String
            let splitUpdates: Bool
            let cardReminders: Bool
            let timeZone: String
        }
        #if DEBUG
        let environment = "sandbox"
        #else
        let environment = "production"
        #endif
        try await APIClient.shared.send("/api/push/devices", method: "PUT", body: Registration(
            installationId: installationID, token: deviceToken, environment: environment,
            splitUpdates: preferences.splitUpdates, cardReminders: preferences.cardReminders,
            timeZone: TimeZone.current.identifier
        ))
    }

    func beforeSignOut() async {
        try? await APIClient.shared.send("/api/push/devices/\(installationID)", method: "DELETE")
        clearSession()
    }

    func clearSession() {
        userID = nil
        destination = nil
        preferences = PushPreferences()
        center.removeAllDeliveredNotifications()
    }
}

final class PushAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken token: Data) {
        Task { @MainActor in await PushNotifications.shared.received(token: token) }
    }
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Task { @MainActor in PushNotifications.shared.errorMessage = "Couldn't register for push notifications. Try again when connected." }
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        guard let recipient = info["recipientId"] as? String,
              let workspace = info["workspaceId"] as? String,
              let kind = info["kind"] as? String, ["split", "cards"].contains(kind) else {
            completionHandler()
            return
        }
        let destination = PushNotifications.Destination(recipientID: recipient, workspaceID: workspace, splitID: info["splitId"] as? String, kind: kind)
        Task { @MainActor in
            PushNotifications.shared.destination = destination
            completionHandler()
        }
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        Task { @MainActor in
            let push = PushNotifications.shared
            let payload = notification.request.content.userInfo
            let allowedCategory = payload["kind"] as? String == "cards" ? push.preferences.cardReminders : push.preferences.splitUpdates
            let belongsToUser = payload["recipientId"] as? String == push.userID
            completionHandler(push.canPresent && allowedCategory && belongsToUser ? [.banner, .sound] : [])
        }
    }
}

struct PushNotificationSettings: View {
    @Environment(AppState.self) private var appState
    private let push = PushNotifications.shared

    var body: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Notifications")
                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
                    .textCase(.uppercase).tracking(0.8)
                Toggle("Push notifications", isOn: Binding(
                    get: { push.preferences.enabled },
                    set: { value in Task { await push.setEnabled(value) } }
                ))
                .font(.body.weight(.medium)).foregroundStyle(Theme.ink)
                .disabled(push.isBusy)
                Text("Get updates on shared splits and reminders before card payments are due on this device.")
                    .font(.footnote).foregroundStyle(Theme.muted)
                if push.preferences.enabled {
                    Toggle("Shared split updates", isOn: Binding(
                        get: { push.preferences.splitUpdates },
                        set: { value in Task { await push.setCategory(splitUpdates: value) } }
                    ))
                    Toggle("Card payment reminders", isOn: Binding(
                        get: { push.preferences.cardReminders },
                        set: { value in Task { await push.setCategory(cardReminders: value) } }
                    ))
                    Text("Reminders arrive at 9 AM in your device's time zone, three days before and on the due date.")
                        .font(.footnote).foregroundStyle(Theme.muted)
                }
                if push.authorization == .denied {
                    Text("Notifications are blocked in iOS Settings.")
                        .font(.footnote).foregroundStyle(Theme.muted)
                    Button("Open iOS Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    .frame(minHeight: 44)
                }
                if let error = push.errorMessage {
                    Text(error).font(.footnote).foregroundStyle(Theme.expense)
                    Button("Retry") { Task { await push.reconcile(userID: appState.currentUser?.id) } }
                        .frame(minHeight: 44)
                }
                if push.isBusy { ProgressView().accessibilityLabel("Updating notification settings") }
            }
            .tint(Theme.accent)
            .disabled(push.isBusy)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

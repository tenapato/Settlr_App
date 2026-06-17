import Foundation
import Observation

@Observable
final class AuthViewModel {
    var email = ""
    var password = ""
    var name = ""
    var isLoading = false
    var errorMessage: String?

    private let api = APIClient.shared

    @MainActor
    func signIn(appState: AppState) async {
        guard !email.isEmpty, !password.isEmpty else {
            errorMessage = "Email and password are required."
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let user = try await api.signIn(email: email, password: password)
            appState.currentUser = user
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func signUp(appState: AppState) async {
        guard !name.isEmpty, !email.isEmpty, !password.isEmpty else {
            errorMessage = "All fields are required."
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let user = try await api.signUp(name: name, email: email, password: password)
            appState.currentUser = user
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func signInWithGoogle(appState: AppState) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let user = try await api.signInWithGoogle()
            appState.currentUser = user
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

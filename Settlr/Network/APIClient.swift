import AuthenticationServices
import Foundation

enum APIError: LocalizedError {
    case unauthorized
    case server(String)
    case decoding(Error)
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "Session expired. Please sign in again."
        case .server(let msg): return msg
        case .decoding(let e): return "Data error: \(e.localizedDescription)"
        case .network(let e): return e.localizedDescription
        }
    }
}

private struct APIErrorBody: Decodable { let error: String }

final class APIClient {
    static let shared = APIClient()
    private init() {}

    var onUnauthorized: (@Sendable () -> Void)?

    private let baseURL: String = {
        #if DEBUG
        return "http://localhost:8787"
        #else
        return "https://settlr.tenapatricio.com"
        #endif
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    private let encoder = JSONEncoder()

    private func makeRequest(_ path: String, method: String = "GET", body: (any Encodable)? = nil) throws -> URLRequest {
        guard let url = URL(string: baseURL + path) else {
            throw APIError.server("Invalid endpoint: \(path)")
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(baseURL, forHTTPHeaderField: "Origin")
        if let token = TokenStore.get() {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try encoder.encode(body)
        }
        return req
    }

    func fetch<T: Decodable>(_ path: String, method: String = "GET", body: (any Encodable)? = nil) async throws -> T {
        let req = try makeRequest(path, method: method, body: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw APIError.server("No response") }

        if http.statusCode == 401 {
            onUnauthorized?()
            throw APIError.unauthorized
        }
        guard (200..<300).contains(http.statusCode) else {
            let msg = (try? decoder.decode(APIErrorBody.self, from: data))?.error ?? "HTTP \(http.statusCode)"
            throw APIError.server(msg)
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    func send(_ path: String, method: String, body: (any Encodable)? = nil) async throws {
        let req = try makeRequest(path, method: method, body: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw APIError.server("No response") }
        if http.statusCode == 401 { onUnauthorized?(); throw APIError.unauthorized }
        guard (200..<300).contains(http.statusCode) else {
            let msg = (try? decoder.decode(APIErrorBody.self, from: data))?.error ?? "HTTP \(http.statusCode)"
            throw APIError.server(msg)
        }
    }

    // Sign-in: captures bearer token from set-auth-token response header, then fetches /api/me
    func signIn(email: String, password: String) async throws -> MeUser {
        struct Body: Encodable { let email: String; let password: String }
        let req = try makeRequest(Endpoints.signIn, method: "POST", body: Body(email: email, password: password))
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw APIError.server("No response") }
        if !(200..<300).contains(http.statusCode) {
            let msg = (try? decoder.decode(APIErrorBody.self, from: data))?.error ?? "Sign in failed"
            throw APIError.server(msg)
        }
        if let token = http.value(forHTTPHeaderField: "set-auth-token"), !token.isEmpty {
            TokenStore.save(token)
        }
        let me: MeResponse = try await fetch(Endpoints.me)
        return me.user
    }

    func signUp(name: String, email: String, password: String) async throws -> MeUser {
        struct Body: Encodable { let name: String; let email: String; let password: String }
        let req = try makeRequest(Endpoints.signUp, method: "POST", body: Body(name: name, email: email, password: password))
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw APIError.server("No response") }
        if !(200..<300).contains(http.statusCode) {
            let msg = (try? decoder.decode(APIErrorBody.self, from: data))?.error ?? "Sign up failed"
            throw APIError.server(msg)
        }
        if let token = http.value(forHTTPHeaderField: "set-auth-token"), !token.isEmpty {
            TokenStore.save(token)
        }
        let me: MeResponse = try await fetch(Endpoints.me)
        return me.user
    }

    func signInWithGoogle() async throws -> MeUser {
        // Step 1: ask better-auth for the Google OAuth URL without auto-redirect
        struct SocialBody: Encodable {
            let provider: String
            let callbackURL: String
            let disableRedirect: Bool
        }
        struct SocialResponse: Decodable {
            let url: String
        }
        let nativeCallback = "\(baseURL)/api/native-callback"
        let socialResp: SocialResponse = try await fetch(
            "/api/auth/sign-in/social",
            method: "POST",
            body: SocialBody(provider: "google", callbackURL: nativeCallback, disableRedirect: true)
        )
        guard let authURL = URL(string: socialResp.url) else {
            throw APIError.server("Invalid OAuth URL from server")
        }

        // Step 2: open Google OAuth in browser; server will redirect through
        // /api/native-callback which appends the token before hitting settlr://
        let callbackScheme = "settlr"
        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            let coordinator = WebAuthCoordinator()
            let session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: callbackScheme) { [coordinator] url, error in
                _ = coordinator
                if let err = error as? ASWebAuthenticationSessionError, err.code == .canceledLogin {
                    continuation.resume(throwing: APIError.server("Sign-in cancelled"))
                } else if let error {
                    continuation.resume(throwing: APIError.network(error))
                } else if let url {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: APIError.server("Google sign-in: missing callback URL"))
                }
            }
            session.presentationContextProvider = coordinator
            session.prefersEphemeralWebBrowserSession = false
            DispatchQueue.main.async { session.start() }
        }

        // Step 3: extract token from settlr://oauth-callback?token=...
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let token = components.queryItems?.first(where: { $0.name == "token" })?.value,
              !token.isEmpty else {
            let errorMsg = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "error" })?.value ?? "no token"
            throw APIError.server("Google sign-in failed: \(errorMsg)")
        }

        TokenStore.save(token)
        let me: MeResponse = try await fetch(Endpoints.me)
        return me.user
    }
}

// MARK: - OAuth helper

private class WebAuthCoordinator: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}

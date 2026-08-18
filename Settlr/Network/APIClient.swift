@preconcurrency import AuthenticationServices
import Foundation

enum APIError: LocalizedError {
    case unauthorized
    /// An admin switched this account off. Distinct from `.unauthorized`
    /// because there is nothing the user can do about it by signing in again,
    /// and they deserve to be told that rather than shown a login form.
    case accountDeactivated(reason: String?)
    case server(String)
    case decoding(Error)
    case network(Error)
    /// The request never reached the server. Distinct from `.network` because
    /// callers act on it: it is the difference between "this failed" and "this
    /// hasn't happened yet", and the whole pending-split queue turns on it.
    case offline

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "Session expired. Please sign in again."
        case .accountDeactivated(let reason):
            return reason.map { "This account has been deactivated: \($0)" }
                ?? "This account has been deactivated."
        case .server(let msg): return msg
        case .decoding(let e): return "Data error: \(e.localizedDescription)"
        case .network(let e): return e.localizedDescription
        case .offline: return "You're offline."
        }
    }

    /// URLSession failures that mean "no usable connection right now", as
    /// opposed to a server that answered with something we didn't like.
    static func isOffline(_ error: Error) -> Bool {
        if case .offline = error as? APIError ?? .unauthorized { return true }
        return offlineCodes.contains((error as? URLError)?.code ?? .unknown)
    }

    fileprivate static let offlineCodes: Set<URLError.Code> = [
        .notConnectedToInternet,
        .networkConnectionLost,
        .timedOut,
        .cannotConnectToHost,
        .cannotFindHost,
        .dnsLookupFailed,
        .dataNotAllowed,
        .internationalRoamingOff,
        .secureConnectionFailed,
    ]
}

private struct APIErrorBody: Decodable {
    let error: String
    /// Machine-readable discriminator the server sends on the refusals a client
    /// has to tell apart — `bill_split_quota` (wait for next month) versus
    /// `bill_split_limit` (edit the split), which share a 403.
    let code: String?
    /// `requireFeature` sends this instead of `code`.
    let feature: String?
    /// The admin's note on a deactivation, when they left one.
    let reason: String?
}

/// Better Auth answers with `{ code, message }` rather than the `{ error }`
/// shape the rest of the API uses, so its refusals need their own reader —
/// without one, "You have been banned from this application" arrived at the
/// login screen as a generic "Sign in failed".
private struct AuthErrorBody: Decodable {
    let code: String?
    let message: String?

    static let bannedCode = "BANNED_USER"
}

/// The server's discriminator for an account an admin deactivated. Must match
/// `ACCOUNT_DEACTIVATED` in `Server/src/middleware/withSession.ts`.
private let accountDeactivatedCode = "account_deactivated"

/// A refusal the server made deliberately, with enough detail to decide whether
/// retrying it could ever work.
struct APIServerError: LocalizedError {
    let status: Int
    let code: String?
    let feature: String?
    let message: String

    var errorDescription: String? { message }
    /// True when trying again unchanged might succeed later — a server fault or
    /// a rate limit, never a rejected payload.
    var isRetryable: Bool { status >= 500 || status == 429 }
}

final class APIClient {
    @MainActor
    static let shared = APIClient()
    private init() {}

    var onUnauthorized: (@Sendable () -> Void)?
    /// Fired instead of `onUnauthorized` when the 401 came with the server's
    /// deactivation code, carrying the admin's reason if they left one.
    var onAccountDeactivated: (@Sendable (String?) -> Void)?

    private let baseURL: String = {
        #if DEBUG
        return "https://api-dev.settlr.cash"
        #else
        return "https://api.settlr.cash"
        #endif
    }()

    /// Must match Server `BETTER_AUTH_URL` (panel/web origin). OAuth session cookies are
    /// set on this host — not on `api.*`. Using the API host for Google sign-in yields `no_session`.
    private let authBaseURL: String = {
        #if DEBUG
        return "https://settlr-api-dev.deamon.workers.dev"
        #else
        return "https://web.settlr.cash"
        #endif
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    private let encoder = JSONEncoder()

    private func makeRequest(
        _ path: String,
        method: String = "GET",
        body: (any Encodable)? = nil,
        origin: String? = nil,
        headers: [String: String] = [:],
        timeout: TimeInterval? = nil
    ) throws -> URLRequest {
        let apiOrigin = origin ?? baseURL
        guard let url = URL(string: apiOrigin + path) else {
            throw APIError.server("Invalid endpoint: \(path)")
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        // Only when a caller asks. The default 60s is right for receipt
        // scanning, whose route gives its AI model 45 seconds on its own.
        if let timeout { req.timeoutInterval = timeout }
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(apiOrigin, forHTTPHeaderField: "Origin")
        if let token = TokenStore.get() {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        for (key, value) in headers {
            req.setValue(value, forHTTPHeaderField: key)
        }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try encoder.encode(body)
        }
        return req
    }

    /// Every request goes through here so that "there is no connection" is
    /// reported as `APIError.offline` instead of escaping as a raw `URLError`.
    ///
    /// Until this existed, being in a basement and the server being broken were
    /// indistinguishable at every call site — both got flattened to
    /// `error.localizedDescription`. That distinction is the whole basis for
    /// queueing a split instead of losing it, and for not deleting someone's
    /// session because `/api/me` timed out.
    ///
    /// Deliberately leaves `timeoutInterval` at the default: receipt scanning
    /// posts to a route that gives its AI model 45 seconds, so a short blanket
    /// timeout here would break it. Callers that need to give up sooner race
    /// their own deadline.
    private static func transport(_ req: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await URLSession.shared.data(for: req)
        } catch let error as URLError where APIError.offlineCodes.contains(error.code) {
            throw APIError.offline
        } catch {
            throw APIError.network(error)
        }
    }

    /// Turns a non-2xx response into an error carrying the server's own
    /// discriminators, so a caller can tell "you're over your monthly limit"
    /// from "this split has too many items" — both of which arrive as 403.
    private func serverError(status: Int, data: Data) -> APIServerError {
        let body = try? decoder.decode(APIErrorBody.self, from: data)
        return APIServerError(
            status: status,
            code: body?.code,
            feature: body?.feature,
            message: body?.error ?? "HTTP \(status)"
        )
    }

    /// Notifies the right handler for a 401 and returns the error to throw.
    /// Both live here so `fetch` and `send` cannot disagree about which one a
    /// deactivated account gets.
    private func unauthorized(data: Data) -> APIError {
        let body = try? decoder.decode(APIErrorBody.self, from: data)
        guard body?.code == accountDeactivatedCode else {
            onUnauthorized?()
            return .unauthorized
        }
        onAccountDeactivated?(body?.reason)
        return .accountDeactivated(reason: body?.reason)
    }

    /// Reads a Better Auth refusal, mapping a ban to the same error the app
    /// shows mid-session so the two paths can't describe it differently.
    private func authError(data: Data, fallback: String) -> APIError {
        let body = try? decoder.decode(AuthErrorBody.self, from: data)
        if body?.code == AuthErrorBody.bannedCode {
            return .accountDeactivated(reason: nil)
        }
        let apiMessage = (try? decoder.decode(APIErrorBody.self, from: data))?.error
        return .server(apiMessage ?? body?.message ?? fallback)
    }

    func fetch<T: Decodable>(
        _ path: String,
        method: String = "GET",
        body: (any Encodable)? = nil,
        origin: String? = nil,
        headers: [String: String] = [:],
        timeout: TimeInterval? = nil
    ) async throws -> T {
        let req = try makeRequest(
            path, method: method, body: body, origin: origin, headers: headers, timeout: timeout
        )
        let (data, response) = try await Self.transport(req)
        guard let http = response as? HTTPURLResponse else { throw APIError.server("No response") }

        if http.statusCode == 401 { throw unauthorized(data: data) }
        guard (200..<300).contains(http.statusCode) else {
            throw serverError(status: http.statusCode, data: data)
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    func send(_ path: String, method: String, body: (any Encodable)? = nil) async throws {
        let req = try makeRequest(path, method: method, body: body)
        let (data, response) = try await Self.transport(req)
        guard let http = response as? HTTPURLResponse else { throw APIError.server("No response") }
        if http.statusCode == 401 { throw unauthorized(data: data) }
        guard (200..<300).contains(http.statusCode) else {
            throw serverError(status: http.statusCode, data: data)
        }
    }

    func uploadReceiptPhoto<Response: Decodable>(
        _ path: String,
        photo: PreparedReceiptPhoto,
        ocrText: String,
        timeout: TimeInterval = 75
    ) async throws -> Response {
        let boundary = "SettlrReceipt-\(UUID().uuidString)"
        let body = ReceiptPhotoUpload.multipartBody(
            boundary: boundary,
            photo: photo,
            ocrText: ocrText
        )
        var req = try makeRequest(
            path,
            method: "POST",
            headers: [
                "Content-Type": "multipart/form-data; boundary=\(boundary)",
            ],
            timeout: timeout
        )
        req.setValue(String(body.count), forHTTPHeaderField: "Content-Length")
        req.httpBody = body

        let (data, response) = try await Self.transport(req)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.server("No response")
        }
        if http.statusCode == 401 { throw unauthorized(data: data) }
        guard (200..<300).contains(http.statusCode) else {
            throw serverError(status: http.statusCode, data: data)
        }
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    // Sign-in: captures bearer token from set-auth-token response header, then fetches /api/me
    func signIn(email: String, password: String) async throws -> MeUser {
        struct Body: Encodable { let email: String; let password: String }
        let req = try makeRequest(Endpoints.signIn, method: "POST", body: Body(email: email, password: password))
        let (data, response) = try await Self.transport(req)
        guard let http = response as? HTTPURLResponse else { throw APIError.server("No response") }
        if !(200..<300).contains(http.statusCode) {
            throw authError(data: data, fallback: "Sign in failed")
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
        let (data, response) = try await Self.transport(req)
        guard let http = response as? HTTPURLResponse else { throw APIError.server("No response") }
        if !(200..<300).contains(http.statusCode) {
            throw authError(data: data, fallback: "Sign up failed")
        }
        if let token = http.value(forHTTPHeaderField: "set-auth-token"), !token.isEmpty {
            TokenStore.save(token)
        }
        let me: MeResponse = try await fetch(Endpoints.me)
        return me.user
    }

    func signInWithApple(credential: ASAuthorizationAppleIDCredential) async throws -> MeUser {
        guard let tokenData = credential.identityToken,
              let identityToken = String(data: tokenData, encoding: .utf8) else {
            throw APIError.server("Apple Sign-In: missing identity token")
        }
        struct AppleBody: Encodable {
            let provider: String
            let idToken: IdToken
            struct IdToken: Encodable { let token: String }
        }
        let req = try makeRequest(
            "/api/auth/sign-in/social",
            method: "POST",
            body: AppleBody(provider: "apple", idToken: .init(token: identityToken)),
            origin: authBaseURL
        )
        let (data, response) = try await Self.transport(req)
        guard let http = response as? HTTPURLResponse else { throw APIError.server("No response") }
        if !(200..<300).contains(http.statusCode) {
            throw authError(data: data, fallback: "Apple sign-in failed")
        }
        // Better Auth's bearer plugin sets set-auth-token; the idToken branch also returns { token } in the JSON body.
        struct AppleSignInResponse: Decodable { let token: String? }
        let sessionToken = http.value(forHTTPHeaderField: "set-auth-token")
            ?? (try? decoder.decode(AppleSignInResponse.self, from: data))?.token
        guard let sessionToken, !sessionToken.isEmpty else {
            throw APIError.server("Apple sign-in: no session token returned")
        }
        TokenStore.save(sessionToken)
        let me: MeResponse = try await fetch(Endpoints.me)
        return me.user
    }

    func deleteAccount() async throws {
        try await send(Endpoints.me, method: "DELETE")
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
        let nativeCallback = "\(authBaseURL)/api/native-callback"
        let socialResp: SocialResponse = try await fetch(
            "/api/auth/sign-in/social",
            method: "POST",
            body: SocialBody(provider: "google", callbackURL: nativeCallback, disableRedirect: true),
            origin: authBaseURL
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
            // better-auth redirects a banned user back with `error=banned`.
            if errorMsg == "banned" { throw APIError.accountDeactivated(reason: nil) }
            throw APIError.server("Google sign-in failed: \(errorMsg)")
        }

        TokenStore.save(token)
        let me: MeResponse = try await fetch(Endpoints.me)
        return me.user
    }
}

// MARK: - OAuth helpers

private class WebAuthCoordinator: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}

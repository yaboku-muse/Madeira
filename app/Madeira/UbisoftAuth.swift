// SPDX-License-Identifier: GPL-3.0-or-later
// Madeira Converter Exception: see LICENSE-EXCEPTION.md
//
// Ubisoft Connect authentication for Madeira Dock.
//
// Ubisoft uses a ticket-based web API (not Steam-style refresh tokens).
// The user logs in once via an embedded browser (WKWebView) pointed at
// Ubisoft's login page; we capture the session ticket + remember-me token
// from the redirect, store them in the Keychain, and refresh the ticket
// programmatically from then on.
//
// Endpoints and header shapes were taken from the actively-maintained
// GOG Galaxy Ubisoft plugin (melcom-creations/galaxy-integration-uplay).
import Foundation
import WebKit
import Security

/// Ubisoft session credentials, Keychain-backed.
struct UbisoftSession {
    var ticket: String       // Ubi_v1 ticket, short-lived
    var sessionID: String    // Ubi-SessionId
    var rememberMeTicket: String // rm_v1 ticket, long-lived
    var userID: String
    var username: String
    var expiresAt: Date
}

/// Errors surfaced to the UI.
enum UbisoftAuthError: Error, LocalizedError {
    case notLoggedIn
    case loginCancelled
    case loginFailed(String)
    case refreshFailed
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .notLoggedIn: return "Sign in to Ubisoft Connect first."
        case .loginCancelled: return "Ubisoft sign-in was cancelled."
        case .loginFailed(let s): return "Ubisoft sign-in failed: \(s)"
        case .refreshFailed: return "Could not refresh the Ubisoft session. Please sign in again."
        case .keychain(let st): return "Keychain error (\(st))."
        }
    }
}

final class UbisoftAuth: NSObject {
    static let shared = UbisoftAuth()

    // Ubisoft's public API. App IDs from the GOG Galaxy plugin source.
    private static let sessionsURL = URL(string: "https://public-ubiservices.ubi.com/v3/profiles/sessions")!
    private static let loginURL = URL(string: "https://connect.ubisoft.com/login?appId=314d4fef-e568-454a-ae06-43e3bece12a6&genomeId=85c31714-0941-4876-a18d-87c488c69bea&lang=en-US")!
    private static let appID = "314d4fef-e568-454a-ae06-43e3bece12a6"

    private static let keychainService = "com.willfaust.madeora.ubisoft"

    private var session: UbisoftSession?
    private var loginCompletion: ((Result<UbisoftSession, Error>) -> Void)?

    private override init() { super.init() }

    // MARK: - Keychain

    private func saveToKeychain(_ s: UbisoftSession) throws {
        let dict: [String: Any] = [
            "ticket": s.ticket, "sessionID": s.sessionID,
            "rememberMeTicket": s.rememberMeTicket, "userID": s.userID,
            "username": s.username, "expiresAt": s.expiresAt.timeIntervalSince1970,
        ]
        let data = try JSONSerialization.data(withJSONObject: dict)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: s.userID,
        ]
        SecItemDelete(query as CFDictionary)
        let add: [String: Any] = query.merging([
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]) { $1 }
        let st = SecItemAdd(add as CFDictionary, nil)
        guard st == errSecSuccess else { throw UbisoftAuthError.keychain(st) }
    }

    private func loadFromKeychain() -> UbisoftSession? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ticket = dict["ticket"] as? String,
              let sessionID = dict["sessionID"] as? String,
              let rm = dict["rememberMeTicket"] as? String,
              let userID = dict["userID"] as? String,
              let username = dict["username"] as? String,
              let exp = dict["expiresAt"] as? Double else { return nil }
        return UbisoftSession(ticket: ticket, sessionID: sessionID, rememberMeTicket: rm,
                              userID: userID, username: username,
                              expiresAt: Date(timeIntervalSince1970: exp))
    }

    func signOut() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
        ]
        SecItemDelete(query as CFDictionary)
        session = nil
    }

    // MARK: - Session

    /// Returns a valid session, refreshing the ticket if needed.
    func validSession() async throws -> UbisoftSession {
        if let s = session, s.expiresAt > Date().addingTimeInterval(300) { return s }
        if let s = loadFromKeychain() {
            session = s
            if s.expiresAt > Date().addingTimeInterval(300) { return s }
            return try await refresh(s)
        }
        throw UbisoftAuthError.notLoggedIn
    }

    /// Refresh the short-lived ticket using the remember-me token.
    private func refresh(_ s: UbisoftSession) async throws -> UbisoftSession {
        var req = URLRequest(url: Self.sessionsURL)
        req.httpMethod = "POST"
        req.setValue("rm_v1 t=\(s.rememberMeTicket)", forHTTPHeaderField: "Authorization")
        req.setValue(Self.appID, forHTTPHeaderField: "Ubi-AppId")
        req.setValue(s.sessionID, forHTTPHeaderField: "Ubi-SessionId")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["rememberMe": true])

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ticket = json["ticket"] as? String else {
            signOut()
            throw UbisoftAuthError.refreshFailed
        }
        var updated = s
        updated.ticket = ticket
        if let sid = json["sessionId"] as? String { updated.sessionID = sid }
        if let exp = json["expiration"] as? String {
            let fmt = ISO8601DateFormatter()
            if let d = fmt.date(from: exp) { updated.expiresAt = d }
        }
        if let rm = json["rememberMeTicket"] as? String { updated.rememberMeTicket = rm }
        try saveToKeychain(updated)
        session = updated
        return updated
    }

    // MARK: - Interactive login (WKWebView)

    /// Presents the Ubisoft login page. The completion fires with the
    /// captured session. Call from the main actor.
    @MainActor func beginLogin() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = self
        web.load(URLRequest(url: Self.loginURL))
        return web
    }

    func cancelLogin() {
        let cb = loginCompletion; loginCompletion = nil
        cb?(.failure(UbisoftAuthError.loginCancelled))
    }

    func onLoginComplete(_ cb: @escaping (Result<UbisoftSession, Error>) -> Void) {
        loginCompletion = cb
    }
}

// MARK: - WKNavigationDelegate: capture the session from the login redirect
extension UbisoftAuth: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // Ubisoft redirects to connect.ubisoft.com/change_domain/... on success.
        // The session is established via cookies; we then hit the sessions
        // endpoint to mint our own ticket from the authenticated context.
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = webView.url?.absoluteString else { return }
        // Login completed when we land back on connect.ubisoft.com outside /login.
        guard url.contains("connect.ubisoft.com"),
              !url.contains("/login"),
              loginCompletion != nil else { return }
        Task { @MainActor in
            do {
                let s = try await self.mintSessionFromCookies(webView)
                try self.saveToKeychain(s)
                self.session = s
                let cb = self.loginCompletion; self.loginCompletion = nil
                cb?(.success(s))
            } catch {
                let cb = self.loginCompletion; self.loginCompletion = nil
                cb?(.failure(error))
            }
        }
    }

    /// Uses the web view's cookies to create a session via the remember-me endpoint.
    @MainActor private func mintSessionFromCookies(_ webView: WKWebView) async throws -> UbisoftSession {
        let store = webView.configuration.websiteDataStore.httpCookieStore
        let cookies = await store.allCookies()
        // The login flow sets an authenticated session; exchange it for a ticket.
        var req = URLRequest(url: Self.sessionsURL)
        req.httpMethod = "POST"
        req.setValue(Self.appID, forHTTPHeaderField: "Ubi-AppId")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("https://connect.ubisoft.com", forHTTPHeaderField: "Origin")
        let cookieHeader = cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        req.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["rememberMe": true])

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ticket = json["ticket"] as? String,
              let sessionID = json["sessionId"] as? String,
              let userID = json["userId"] as? String else {
            throw UbisoftAuthError.loginFailed("could not mint a session ticket")
        }
        let username = (json["username"] as? String) ?? userID
        let rememberMe = (json["rememberMeTicket"] as? String) ?? ""
        var expiresAt = Date().addingTimeInterval(3600)
        if let exp = json["expiration"] as? String,
           let d = ISO8601DateFormatter().date(from: exp) { expiresAt = d }
        return UbisoftSession(ticket: ticket, sessionID: sessionID, rememberMeTicket: rememberMe,
                              userID: userID, username: username, expiresAt: expiresAt)
    }
}

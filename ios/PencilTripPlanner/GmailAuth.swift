import Foundation
import AuthenticationServices
import CryptoKit
import Security
import UIKit

// MARK: - Gmail OAuth 2.0 (manual PKCE flow, zero third-party deps)
//
// Setup needed (done once by whoever builds the app):
//   1. Google Cloud Console -> OAuth client ID (type iOS) -> Client ID
//   2. Info.plist: GmailClientID = "<id>.apps.googleusercontent.com" (String)
//   3. Xcode URL Types: scheme = com.googleusercontent.apps.<id-without-suffix>

enum GmailAuthError: Error, LocalizedError {
    case missingClientID
    case userCancelled
    case network(Error)
    case server(String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .missingClientID:
            return "GmailClientID is not set in Info.plist."
        case .userCancelled:
            return "Sign-in was cancelled."
        case .network(let e):
            return "Network error: \(e.localizedDescription)"
        case .server(let s):
            return "Google error: \(s)"
        case .badResponse:
            return "Google returned an unexpected response."
        }
    }
}

/// Presents the ASWebAuthenticationSession on the key window.
final class WebAuthPresenter: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = WebAuthPresenter()

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes {
            if let w = scene.windows.first(where: { $0.isKeyWindow }) { return w }
        }
        return scenes.first?.windows.first ?? ASPresentationAnchor()
    }
}

/// Keeps the auth session alive until its callback fires.
private final class SessionHolder {
    var session: ASWebAuthenticationSession?
}

private struct TokenResponse: Decodable {
    let access_token: String
    let expires_in: Int
    let refresh_token: String?
}

private struct TokenErrorResponse: Decodable {
    let error: String?
    let error_description: String?
}

/// Manual Google OAuth 2.0 with PKCE.
/// Access token lives in memory only; the refresh token lives in the Keychain.
@MainActor
final class GmailAuth: ObservableObject {
    static let shared = GmailAuth()

    @Published private(set) var isSignedIn = false
    @Published private(set) var userEmail: String?

    private var accessToken: String?
    private var accessTokenExpiry: Date?

    private let keychainService = "pencil-trip-planner.gmail"
    private let refreshAccount = "refresh_token"
    private let emailAccount = "user_email"

    private init() {
        isSignedIn = loadFromKeychain(account: refreshAccount) != nil
        userEmail = loadFromKeychain(account: emailAccount)
    }

    // MARK: - Config

    /// OAuth client ID from Info.plist (`GmailClientID`).
    static func clientID() -> String? {
        guard let s = Bundle.main.object(forInfoDictionaryKey: "GmailClientID") as? String,
              !s.isEmpty else { return nil }
        return s
    }

    /// Reversed client-ID URL scheme, e.g. com.googleusercontent.apps.12345-abcde
    static func urlScheme(clientID: String) -> String {
        let prefix = clientID.replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
        return "com.googleusercontent.apps.\(prefix)"
    }

    // MARK: - Sign in (PKCE)

    func signIn() async throws {
        guard let clientID = Self.clientID() else { throw GmailAuthError.missingClientID }
        let scheme = Self.urlScheme(clientID: clientID)
        let redirectURI = "\(scheme):/oauth2redirect"
        let verifier = Self.makeVerifier()
        let challenge = Self.codeChallenge(for: verifier)

        var comps = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        comps.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "https://www.googleapis.com/auth/gmail.readonly"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
        ]
        guard let authURL = comps.url else { throw GmailAuthError.badResponse }

        let holder = SessionHolder()
        let code: String = try await withCheckedThrowingContinuation { cont in
            let session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: scheme) { url, error in
                holder.session = nil
                if let error = error {
                    if (error as NSError).code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        cont.resume(throwing: GmailAuthError.userCancelled)
                    } else {
                        cont.resume(throwing: GmailAuthError.network(error))
                    }
                    return
                }
                guard let url = url,
                      let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else {
                    cont.resume(throwing: GmailAuthError.badResponse)
                    return
                }
                if let c = items.first(where: { $0.name == "code" })?.value {
                    cont.resume(returning: c)
                } else {
                    let desc = items.first(where: { $0.name == "error_description" })?.value
                        ?? items.first(where: { $0.name == "error" })?.value
                        ?? "unknown"
                    cont.resume(throwing: GmailAuthError.server(desc))
                }
            }
            holder.session = session
            session.presentationContextProvider = WebAuthPresenter.shared
            session.prefersEphemeralWebBrowserSession = true
            _ = session.start()
        }

        let tokens = try await exchangeToken(params: [
            "grant_type": "authorization_code",
            "code": code,
            "client_id": clientID,
            "code_verifier": verifier,
            "redirect_uri": redirectURI,
        ])
        accessToken = tokens.access_token
        accessTokenExpiry = Date().addingTimeInterval(TimeInterval(tokens.expires_in))
        if let rt = tokens.refresh_token { saveToKeychain(account: refreshAccount, value: rt) }
        if let email = try? await GmailAPI.fetchProfileEmail(token: tokens.access_token), !email.isEmpty {
            userEmail = email
            saveToKeychain(account: emailAccount, value: email)
        }
        isSignedIn = true
    }

    func signOut() {
        accessToken = nil
        accessTokenExpiry = nil
        deleteFromKeychain(account: refreshAccount)
        deleteFromKeychain(account: emailAccount)
        userEmail = nil
        isSignedIn = false
    }

    /// Valid access token, refreshing silently when needed.
    func validAccessToken() async throws -> String {
        if let t = accessToken, let exp = accessTokenExpiry, exp > Date().addingTimeInterval(60) {
            return t
        }
        guard let refresh = loadFromKeychain(account: refreshAccount) else {
            throw GmailAuthError.userCancelled
        }
        guard let clientID = Self.clientID() else { throw GmailAuthError.missingClientID }
        let tokens = try await exchangeToken(params: [
            "grant_type": "refresh_token",
            "refresh_token": refresh,
            "client_id": clientID,
        ])
        accessToken = tokens.access_token
        accessTokenExpiry = Date().addingTimeInterval(TimeInterval(tokens.expires_in))
        if let rt = tokens.refresh_token { saveToKeychain(account: refreshAccount, value: rt) }
        return tokens.access_token
    }

    // MARK: - Token endpoint

    private func exchangeToken(params: [String: String]) async throws -> TokenResponse {
        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = params
            .map { key, value in "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)
        let data: Data
        let resp: URLResponse
        do {
            (data, resp) = try await URLSession.shared.data(for: req)
        } catch {
            throw GmailAuthError.network(error)
        }
        guard let http = resp as? HTTPURLResponse else { throw GmailAuthError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            let errBody = try? JSONDecoder().decode(TokenErrorResponse.self, from: data)
            throw GmailAuthError.server(errBody?.error_description ?? errBody?.error ?? "HTTP \(http.statusCode)")
        }
        do {
            return try JSONDecoder().decode(TokenResponse.self, from: data)
        } catch {
            throw GmailAuthError.badResponse
        }
    }

    // MARK: - PKCE

    private static func makeVerifier() -> String {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return String((0..<64).map { _ in chars.randomElement()! })
    }

    private static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: - Keychain (refresh token + email only; never the access token)

    private func saveToKeychain(account: String, value: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecService as String: keychainService,
            kSecAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    private func loadFromKeychain(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecService as String: keychainService,
            kSecAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let s = String(data: data, encoding: .utf8), !s.isEmpty else { return nil }
        return s
    }

    private func deleteFromKeychain(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecService as String: keychainService,
            kSecAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

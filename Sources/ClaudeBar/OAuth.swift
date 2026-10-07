import Foundation
import CryptoKit

struct Token: Codable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date

    var needsRefresh: Bool { expiresAt.timeIntervalSinceNow < 300 }

    static func load(accountID: String) -> Token? {
        Keychain.load(accountID: accountID).flatMap { try? JSONDecoder().decode(Token.self, from: $0) }
    }

    /// Accepts Claude Code's credentials JSON (`{"claudeAiOauth": {...}}` from the
    /// "Claude Code-credentials" Keychain item, or `.claude/.credentials.json` on Linux),
    /// a bare `{accessToken, refreshToken, expiresAt}`, or an OAuth token response
    /// `{access_token, refresh_token, expires_in}`.
    static func fromJSON(_ text: String) -> Token? {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let root = (obj["claudeAiOauth"] as? [String: Any]) ?? obj
        guard let access = root["accessToken"] as? String ?? root["access_token"] as? String,
              !access.isEmpty else { return nil }
        let refresh = root["refreshToken"] as? String ?? root["refresh_token"] as? String ?? ""
        let expiresAt: Date
        if let ms = root["expiresAt"] as? Double, ms > 0 {
            expiresAt = Date(timeIntervalSince1970: ms > 1e12 ? ms / 1000 : ms)
        } else if let iso = root["expiresAt"] as? String, let d = UsageModel.parseDate(iso) {
            expiresAt = d
        } else if let e = root["expires_in"] as? Double {
            expiresAt = Date().addingTimeInterval(e)
        } else {
            expiresAt = Date().addingTimeInterval(3600)
        }
        return Token(accessToken: access, refreshToken: refresh, expiresAt: expiresAt)
    }

    func save(accountID: String) {
        if let data = try? JSONEncoder().encode(self) { Keychain.save(data, accountID: accountID) }
    }
}

enum OAuthError: LocalizedError {
    case exchangeFailed(String)
    var errorDescription: String? {
        if case .exchangeFailed(let msg) = self { return msg }
        return nil
    }
}

enum OAuth {
    static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    static let redirectURI = "https://platform.claude.com/oauth/code/callback"
    static var tokenURL: URL { URL(string: Config.base(path: "/v1/oauth/token"))! }
    static let scope = "user:profile"

    struct PKCE {
        let verifier: String
        let challenge: String
        let state: String

        init() {
            verifier = Self.randomURLSafe()
            challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL()
            state = Self.randomURLSafe()
        }

        static func randomURLSafe() -> String {
            var bytes = [UInt8](repeating: 0, count: 32)
            guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
                fatalError("Secure random generator unavailable") // fail closed — never proceed with a predictable PKCE verifier
            }
            return Data(bytes).base64URL()
        }
    }

    static func authorizeURL(_ pkce: PKCE) -> URL {
        var c = URLComponents(string: Config.base(path: "/oauth/authorize"))!
        c.queryItems = [
            .init(name: "code", value: "true"),
            .init(name: "client_id", value: clientID),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "scope", value: scope),
            .init(name: "code_challenge", value: pkce.challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: pkce.state),
        ]
        return c.url!
    }

    /// The callback page shows the code as "code#state" — accept either form,
    /// but a pasted state MUST match the one we generated (rejects injected codes).
    static func exchange(pastedCode: String, pkce: PKCE) async throws -> Token {
        let parts = pastedCode.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "#")
        guard let first = parts.first, !first.isEmpty else {
            throw OAuthError.exchangeFailed("That code looks empty — copy it from the callback page and try again.")
        }
        if parts.count > 1, String(parts[1]) != pkce.state {
            throw OAuthError.exchangeFailed("Authorization state mismatch — please restart the connect flow.")
        }
        let code = String(first)
        let body: [String: String] = [
            "grant_type": "authorization_code",
            "code": code,
            "state": pkce.state,
            "client_id": clientID,
            "redirect_uri": redirectURI,
            "code_verifier": pkce.verifier,
        ]
        return try await requestToken(body)
    }

    static func refresh(_ token: Token) async throws -> Token {
        try await requestToken([
            "grant_type": "refresh_token",
            "refresh_token": token.refreshToken,
            "client_id": clientID,
        ])
    }

    private static func requestToken(_ body: [String: String]) async throws -> Token {
        var req = URLRequest(url: tokenURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)
        var (data, resp) = try await URLSession.shared.data(for: req)

        // ponytail: some deployments want form-encoded instead of JSON — retry once
        if (resp as? HTTPURLResponse)?.statusCode ?? 500 >= 400 {
            req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            req.httpBody = body.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? $0.value)" }
                .joined(separator: "&").data(using: .utf8)
            (data, resp) = try await URLSession.shared.data(for: req)
        }

        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? "token exchange failed"
            throw OAuthError.exchangeFailed(String(msg.prefix(200))) // cap reflected server output
        }

        struct TokenResponse: Decodable {
            let access_token: String
            let refresh_token: String?
            let expires_in: Double
        }
        let tr = try JSONDecoder().decode(TokenResponse.self, from: data)
        let token = Token(
            accessToken: tr.access_token,
            refreshToken: tr.refresh_token ?? body["refresh_token"] ?? "",
            expiresAt: Date().addingTimeInterval(tr.expires_in)
        )
        return token
    }
}

extension Data {
    func base64URL() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

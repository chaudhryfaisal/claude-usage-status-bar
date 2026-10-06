import Foundation
import SwiftUI

struct UsageWindow: Identifiable {
    let id: String
    let label: String
    let utilization: Double   // 0–100
    let resetsAt: Date?
}

struct AccountMeta: Codable {
    let id: String
    var alias: String
}

@MainActor
final class AccountModel: ObservableObject, Identifiable {
    let id: String
    @Published var alias: String
    @Published var windows: [UsageWindow] = []
    @Published var connected: Bool
    @Published var stale = false
    @Published var lastError: String?
    @Published var lastRefreshed: Date?

    init(id: String, alias: String) {
        self.id = id
        self.alias = alias
        self.connected = Token.load(accountID: id) != nil
    }

    var refreshedText: String? {
        guard let lastRefreshed else { return nil }
        let s = max(0, Int(Date().timeIntervalSince(lastRefreshed)))
        if s < 5 { return "just now" }
        if s < 60 { return "\(s)s ago" }
        let m = s / 60, sec = s % 60
        if m < 60 { return sec > 0 ? "\(m)m\(sec)s ago" : "\(m)m ago" }
        let h = m / 60
        return "\(h)h\(m % 60)m ago"
    }

    var sessionUtilization: Double? { windows.first { $0.id == "five_hour" }?.utilization }
    var weeklyUtilization: Double? { windows.first { $0.id == "seven_day" }?.utilization }

    func refresh() async {
        guard var token = Token.load(accountID: id) else {
            connected = false
            windows = []
            return
        }
        do {
            if token.needsRefresh {
                token = try await OAuth.refresh(token)
                token.save(accountID: id)
            }
            var req = URLRequest(url: UsageModel.usageURL)
            req.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
            req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
            req.setValue("claude-code/1.0.119", forHTTPHeaderField: "User-Agent")
            let (data, resp) = try await URLSession.shared.data(for: req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if status == 401 || status == 403 {
                connected = false
                windows = []
                lastError = "Session expired — reconnect this account."
                return
            }
            guard status == 200 else {
                stale = true
                return
            }
            connected = true
            windows = UsageModel.parse(data)
            stale = false
            lastError = nil
            lastRefreshed = Date()
        } catch {
            stale = true
        }
    }
}

@MainActor
final class UsageModel: ObservableObject {
    @Published var accounts: [AccountModel] = []
    @Published var primaryID: String?
    @Published var pendingAuth: OAuth.PKCE?
    @Published var pendingReauthID: String?
    @Published var lastError: String?

    static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private var timer: Timer?
    private static let knownLabels: [(key: String, label: String)] = [
        ("five_hour", "Session (5h)"),
        ("seven_day", "Weekly"),
        ("seven_day_opus", "Weekly · Opus"),
    ]

    init() {
        migrateLegacyToken()
        loadState()
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { await self?.refreshAll() }
        }
        Task { await refreshAll() }
    }

    var primary: AccountModel? {
        accounts.first { $0.id == primaryID } ?? accounts.first
    }

    // MARK: - Account management

    func rename(_ account: AccountModel, to alias: String) {
        account.alias = alias.isEmpty ? "Account" : alias
        persist()
    }

    func move(_ account: AccountModel, by delta: Int) {
        guard let i = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        let j = i + delta
        guard accounts.indices.contains(j) else { return }
        accounts.swapAt(i, j)
        persist()
    }

    func setPrimary(_ account: AccountModel) {
        primaryID = account.id
        persist()
    }

    func disconnect(_ account: AccountModel) {
        Keychain.delete(accountID: account.id)
        accounts.removeAll { $0.id == account.id }
        if primaryID == account.id { primaryID = accounts.first?.id }
        persist()
    }

    // MARK: - Connect flow

    func startConnect(reauth account: AccountModel? = nil) {
        let pkce = OAuth.PKCE()
        pendingAuth = pkce
        pendingReauthID = account?.id
        lastError = nil
        NSWorkspace.shared.open(OAuth.authorizeURL(pkce))
    }

    func finishConnect(code: String) async {
        guard let pkce = pendingAuth else { return }
        do {
            let token = try await OAuth.exchange(pastedCode: code, pkce: pkce)
            if let id = pendingReauthID, let acc = accounts.first(where: { $0.id == id }) {
                token.save(accountID: id)
                acc.connected = true
                acc.lastError = nil
                await acc.refresh()
            } else {
                let id = UUID().uuidString
                token.save(accountID: id)
                let acc = AccountModel(id: id, alias: "Account \(accounts.count + 1)")
                accounts.append(acc)
                if primaryID == nil { primaryID = id }
                await acc.refresh()
            }
            pendingAuth = nil
            pendingReauthID = nil
            lastError = nil
            persist()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func cancelConnect() {
        pendingAuth = nil
        pendingReauthID = nil
    }

    func refreshAll() async {
        await withTaskGroup(of: Void.self) { group in
            for acc in accounts {
                group.addTask { await acc.refresh() }
            }
        }
    }

    // MARK: - Persistence

    private func persist() {
        let metas = accounts.map { AccountMeta(id: $0.id, alias: $0.alias) }
        UserDefaults.standard.set(try? JSONEncoder().encode(metas), forKey: "accounts")
        UserDefaults.standard.set(primaryID, forKey: "primaryAccountID")
    }

    private func loadState() {
        primaryID = UserDefaults.standard.string(forKey: "primaryAccountID")
        if let data = UserDefaults.standard.data(forKey: "accounts"),
           let metas = try? JSONDecoder().decode([AccountMeta].self, from: data) {
            accounts = metas.map { AccountModel(id: $0.id, alias: $0.alias) }
        }
        if primaryID == nil { primaryID = accounts.first?.id }
    }

    /// One-time import of the pre-multi-account single-token Keychain entry.
    private func migrateLegacyToken() {
        guard UserDefaults.standard.data(forKey: "accounts") == nil,
              let data = Keychain.load(),
              let token = try? JSONDecoder().decode(Token.self, from: data) else { return }
        let id = UUID().uuidString
        token.save(accountID: id)
        Keychain.delete()
        if let metas = try? JSONEncoder().encode([AccountMeta(id: id, alias: "Default")]) {
            UserDefaults.standard.set(metas, forKey: "accounts")
        }
        UserDefaults.standard.set(id, forKey: "primaryAccountID")
    }

    // MARK: - Parsing

    static func parse(_ data: Data) -> [UsageWindow] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        var result: [UsageWindow] = []
        var seen = Set<String>()
        func window(_ key: String, _ label: String) -> UsageWindow? {
            guard let obj = json[key] as? [String: Any],
                  let utilization = obj["utilization"] as? Double else { return nil }
            return UsageWindow(id: key, label: label,
                               utilization: utilization,
                               resetsAt: (obj["resets_at"] as? String).flatMap(parseDate))
        }
        for (key, label) in knownLabels {
            if let w = window(key, label) { result.append(w); seen.insert(key) }
        }
        for key in json.keys.sorted() where !seen.contains(key) {
            if let w = window(key, key.replacingOccurrences(of: "_", with: " ").capitalized) {
                result.append(w)
            }
        }
        return result
    }

    static func parseDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}

extension UsageWindow {
    var resetText: String? {
        guard let resetsAt else { return nil }
        let f = DateFormatter()
        f.dateFormat = Calendar.current.isDateInToday(resetsAt) ? "HH:mm" : "EEE HH:mm"
        return "resets \(f.string(from: resetsAt)) (\(Self.remainingText(until: resetsAt)))"
    }

    /// "1h10m", "45m", "3d4h", or "now" when the window has already reset.
    static func remainingText(until date: Date, now: Date = Date()) -> String {
        let minutes = max(0, Int((date.timeIntervalSince(now) / 60).rounded()))
        if minutes == 0 { return "now" }
        let d = minutes / 1440
        let h = (minutes % 1440) / 60
        let m = minutes % 60
        if d > 0 { return h > 0 ? "\(d)d\(h)h" : "\(d)d" }
        if h > 0 { return m > 0 ? "\(h)h\(m)m" : "\(h)h" }
        return "\(m)m"
    }

    var color: Color {
        if utilization >= 90 { return .red }
        if utilization >= 70 { return Color(red: 0.85, green: 0.47, blue: 0.34) } // Anthropic coral
        return .secondary
    }
}

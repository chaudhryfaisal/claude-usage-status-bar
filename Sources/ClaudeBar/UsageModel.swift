import Foundation
import SwiftUI

struct UsageWindow: Identifiable {
    let id: String
    let label: String
    let utilization: Double   // 0–100
    let resetsAt: Date?
}

@MainActor
final class UsageModel: ObservableObject {
    @Published var windows: [UsageWindow] = []
    @Published var connected = Token.load() != nil
    @Published var lastError: String?
    @Published var stale = false
    @Published var pendingAuth: OAuth.PKCE?

    private var timer: Timer?
    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let knownLabels: [(key: String, label: String)] = [
        ("five_hour", "Session (5h)"),
        ("seven_day", "Weekly"),
        ("seven_day_opus", "Weekly · Opus"),
    ]

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
        Task { await refresh() }
    }

    var sessionUtilization: Double? { windows.first { $0.id == "five_hour" }?.utilization }
    var weeklyUtilization: Double? { windows.first { $0.id == "seven_day" }?.utilization }

    // MARK: - Connect flow

    func startConnect() {
        let pkce = OAuth.PKCE()
        pendingAuth = pkce
        NSWorkspace.shared.open(OAuth.authorizeURL(pkce))
    }

    func finishConnect(code: String) async {
        guard let pkce = pendingAuth else { return }
        do {
            _ = try await OAuth.exchange(pastedCode: code, pkce: pkce)
            pendingAuth = nil
            connected = true
            lastError = nil
            await refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func disconnect() {
        Keychain.delete()
        connected = false
        windows = []
        pendingAuth = nil
    }

    // MARK: - Fetch

    func refresh() async {
        guard var token = Token.load() else { connected = false; return }
        do {
            if token.needsRefresh {
                token = try await OAuth.refresh(token)
            }
            var req = URLRequest(url: Self.usageURL)
            req.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
            req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
            req.setValue("claude-code/1.0.119", forHTTPHeaderField: "User-Agent")
            let (data, resp) = try await URLSession.shared.data(for: req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if status == 401 || status == 403 {
                connected = false
                lastError = "Session expired — reconnect your account."
                return
            }
            guard status == 200 else {
                stale = true
                return
            }
            windows = Self.parse(data)
            stale = false
            lastError = nil
        } catch {
            stale = true
        }
    }

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
        // future windows the API may add
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
        return "resets \(f.string(from: resetsAt))"
    }

    var color: Color {
        if utilization >= 90 { return .red }
        if utilization >= 70 { return Color(red: 0.85, green: 0.47, blue: 0.34) } // Anthropic coral
        return .secondary
    }
}

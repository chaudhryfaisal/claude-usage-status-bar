import SwiftUI

@main
struct ClaudeBarApp: App {
    @StateObject private var model = UsageModel()

    var body: some Scene {
        MenuBarExtra {
            MenuView(model: model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)
        Window("Usage Dashboard", id: "dashboard") {
            DashboardView(model: model)
        }
    }
}

struct MenuBarLabel: View {
    @ObservedObject var model: UsageModel

    private func pct(_ v: Double) -> String { String(format: "%.2f", v) }

    var body: some View {
        if let primary = model.primary,
           let session = primary.sessionUtilization,
           let weekly = primary.weeklyUtilization {
            Text("✳ \(pct(session))/\(pct(weekly))%")
        } else if let primary = model.primary,
                  let only = primary.sessionUtilization ?? primary.weeklyUtilization {
            Text("✳ \(pct(only))%")
        } else {
            Text(model.accounts.isEmpty ? "✳ –" : "✳")
        }
    }
}

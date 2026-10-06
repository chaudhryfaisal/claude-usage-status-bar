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
        Window("Claude Usage Dashboard", id: "dashboard") {
            DashboardView(model: model)
        }
    }
}

struct MenuBarLabel: View {
    @ObservedObject var model: UsageModel

    var body: some View {
        if let primary = model.primary,
           let session = primary.sessionUtilization,
           let weekly = primary.weeklyUtilization {
            Text("✳ \(Int(session.rounded()))/\(Int(weekly.rounded()))%")
        } else if let primary = model.primary,
                  let only = primary.sessionUtilization ?? primary.weeklyUtilization {
            Text("✳ \(Int(only.rounded()))%")
        } else {
            Text(model.accounts.isEmpty ? "✳ –" : "✳")
        }
    }
}

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
    }
}

struct MenuBarLabel: View {
    @ObservedObject var model: UsageModel

    var body: some View {
        if let session = model.sessionUtilization, let weekly = model.weeklyUtilization {
            Text("✳ \(Int(session.rounded()))/\(Int(weekly.rounded()))%")
        } else if let only = model.sessionUtilization ?? model.weeklyUtilization {
            Text("✳ \(Int(only.rounded()))%")
        } else {
            Text(model.connected ? "✳" : "✳ –")
        }
    }
}

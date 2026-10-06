import SwiftUI

struct DashboardView: View {
    @ObservedObject var model: UsageModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Claude Usage Dashboard").font(.title2.weight(.semibold))
                Spacer()
                Button("Refresh all") { Task { await model.refreshAll() } }
            }
            if model.accounts.isEmpty {
                Text("No accounts connected. Add one from the menu bar.")
                    .foregroundStyle(.secondary)
            }
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 16)], spacing: 16) {
                    ForEach(model.accounts) { account in
                        DashboardCard(account: account, model: model)
                    }
                }
            }
        }
        .padding(20)
        .frame(minWidth: 700, minHeight: 420)
        .onAppear { Task { await model.refreshAll() } }
    }
}

struct DashboardCard: View {
    @ObservedObject var account: AccountModel
    @ObservedObject var model: UsageModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            RefreshedLabel(account: account)
            usageSection
            Divider()
            HStack {
                Button("Open web dashboard") {
                    NSWorkspace.shared.open(URL(string: "https://claude.ai/settings/usage")!)
                }
                Spacer()
                Button("Disconnect", role: .destructive) { model.disconnect(account) }
            }
            .font(.subheadline)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 10).fill(.thinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
    }

    private var header: some View {
        HStack {
            Button { model.setPrimary(account) } label: {
                Image(systemName: model.primary?.id == account.id ? "star.fill" : "star")
                    .foregroundStyle(model.primary?.id == account.id ? .yellow : .secondary)
            }
            .buttonStyle(.plain)
            TextField("Alias", text: Binding(
                get: { account.alias },
                set: { model.rename(account, to: $0) }
            ))
            .font(.headline)
            .textFieldStyle(.plain)
            Spacer()
            Button { model.move(account, by: -1) } label: { Image(systemName: "chevron.up") }
                .buttonStyle(.plain)
                .help("Move up")
            Button { model.move(account, by: 1) } label: { Image(systemName: "chevron.down") }
                .buttonStyle(.plain)
                .help("Move down")
            if account.stale {
                Image(systemName: "wifi.exclamationmark").foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var usageSection: some View {
        Group {
            if !account.connected {
                Text(account.lastError ?? "Disconnected.")
                    .foregroundStyle(.red)
                Button("Reconnect") { model.startConnect(reauth: account) }
            } else if account.windows.isEmpty {
                Text("Loading…").foregroundStyle(.secondary)
            } else {
                ForEach(account.windows) { w in
                    WindowRow(w: w)
                }
            }
        }
    }
}

struct WindowRow: View {
    let w: UsageWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(w.label)
                Spacer()
                let pct = Int(w.utilization.rounded())
                Text("\(pct)%")
                    .monospacedDigit().fontWeight(.medium)
                    .foregroundStyle(w.utilization >= 70 ? w.color : .primary)
            }
            ProgressView(value: min(w.utilization, 100), total: 100)
                .tint(w.color)
            if let reset = w.resetText {
                Text(reset).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

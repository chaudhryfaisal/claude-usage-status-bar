import SwiftUI
import ServiceManagement
import UniformTypeIdentifiers

struct MenuView: View {
    @ObservedObject var model: UsageModel
    @State private var code = ""
    @State private var importJSON = ""
    @State private var baseURL = Config.baseURLString
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.accounts.isEmpty && model.pendingAuth == nil {
                connect
            } else {
                accounts
            }
            Divider().padding(.horizontal, 12)
            footer
        }
        .frame(width: 300)
        .onAppear { Task { await model.refreshAll() } }
    }

    // MARK: - Accounts

    private var accounts: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(model.accounts) { account in
                    AccountCard(account: account, model: model)
                }
                if model.pendingAuth != nil {
                    codeEntry
                } else {
                    addAccountSection
                }
                if let err = model.lastError {
                    Text(err).font(.caption).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxHeight: 460)
    }

    @ViewBuilder
    private var addAccountSection: some View {
        switch model.adding {
        case .none:
            Button("+ Add account") { model.adding = .chooser }
                .buttonStyle(.plain)
                .font(.subheadline)
                .foregroundStyle(.blue)
        case .chooser:
            VStack(alignment: .leading, spacing: 6) {
                Text("How do you want to add the account?")
                    .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Button("Browser sign-in") { model.adding = nil; model.startConnect() }
                    Button("Import JSON") { model.adding = .importToken }
                    Button("Cancel") { model.adding = nil }
                }
                .font(.subheadline)
            }
        case .importToken:
            importEntry
        }
    }

    private var importEntry: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Paste credentials JSON (claudeAiOauth from ~/.claude.json / Claude Code credentials, or an OAuth token response), or choose a file:")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextEditor(text: $importJSON)
                .font(.caption.monospaced())
                .frame(height: 70)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.quaternary))
            HStack(spacing: 12) {
                Button("Choose File…") { pickFile() }
                Button("Import") {
                    let j = importJSON
                    importJSON = ""
                    Task { await model.finishImport(json: j) }
                }
                .disabled(importJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Cancel") { model.adding = nil; importJSON = "" }
                Spacer()
            }
        }
    }

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url,
           let text = try? String(contentsOf: url) {
            importJSON = text
        }
    }

    private var codeEntry: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Approve in your browser, then paste the code:")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                TextField("Paste code", text: $code)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { submit() }
                Button("Connect") { submit() }
                    .disabled(code.isEmpty)
                Button("Cancel") { model.cancelConnect() }
            }
            if let err = model.lastError {
                Text(err).font(.caption).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Connect (first account)

    private var connect: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Claude Usage").font(.headline)
            Text("Connect your Claude account to see your session and weekly limits.")
                .font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("or import credentials JSON") { model.adding = .importToken }
                .buttonStyle(.plain)
                .font(.subheadline)
                .foregroundStyle(.blue)
            if model.pendingAuth != nil {
                codeEntry
            } else if model.adding != nil {
                addAccountSection
            } else {
                Button("Connect Claude Account") { model.startConnect() }
                    .controlSize(.large)
            }
            if let err = model.lastError {
                Text(err).font(.caption).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
    }

    private func saveBaseURL() {
        let v = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(v == Config.defaultBaseURL ? nil : v, forKey: "baseURL")
        baseURL = Config.baseURLString
        Task { await model.refreshAll() }
    }

    private func submit() {
        let c = code
        code = ""
        Task { await model.finishConnect(code: c) }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                launchAtLogin.toggle()
                try? launchAtLogin ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: launchAtLogin ? "checkmark.square.fill" : "square")
                    Text("Launch at login")
                }
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                TextField("Base URL", text: $baseURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .onSubmit { saveBaseURL() }
                footerButton("Save") { saveBaseURL() }
                footerButton("Reset") {
                    baseURL = Config.defaultBaseURL
                    saveBaseURL()
                }
            }
            HStack(spacing: 12) {
                footerButton("Refresh") { Task { await model.refreshAll() } }
                footerButton("Dashboard") { openWindow(id: "dashboard") }
                Spacer()
                footerButton("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(12)
    }

    private func footerButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

struct RefreshedLabel: View {
    @ObservedObject var account: AccountModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 5)) { _ in
            if let text = account.refreshedText {
                Text("Refreshed \(text)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

struct AccountCard: View {
    @ObservedObject var account: AccountModel
    @ObservedObject var model: UsageModel
    @FocusState private var aliasFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Button { model.setPrimary(account) } label: {
                    Image(systemName: model.primary?.id == account.id ? "star.fill" : "star")
                        .foregroundStyle(model.primary?.id == account.id ? .yellow : .secondary)
                }
                .buttonStyle(.plain)
                .help("Set as primary (shown in menu bar)")
                TextField("Alias", text: Binding(
                    get: { account.alias },
                    set: { model.rename(account, to: $0) }
                ))
                .font(.subheadline.weight(.medium))
                .textFieldStyle(.plain)
                .focused($aliasFocused)
                if account.stale {
                    Circle().fill(.secondary).frame(width: 5, height: 5)
                        .help("Couldn't reach Anthropic — showing last known data")
                }
                Spacer()
                Button {
                    NSWorkspace.shared.open(URL(string: Config.base(path: "/settings/usage"))!)
                } label: { Image(systemName: "globe") }
                .buttonStyle(.plain)
                .help("Open web dashboard")
                Button { model.move(account, by: -1) } label: { Image(systemName: "chevron.up") }
                .buttonStyle(.plain)
                .help("Move up")
                Button { model.move(account, by: 1) } label: { Image(systemName: "chevron.down") }
                .buttonStyle(.plain)
                .help("Move down")
                Button { model.disconnect(account) } label: { Image(systemName: "xmark.circle") }
                .buttonStyle(.plain)
                .help("Disconnect account")
            }

            RefreshedLabel(account: account)

            if !account.connected {
                HStack {
                    Text(account.lastError ?? "Disconnected.")
                        .font(.caption).foregroundStyle(.red)
                    Spacer()
                    Button("Reconnect") { model.startConnect(reauth: account) }
                        .font(.caption)
                }
            } else if account.windows.isEmpty {
                Text("Loading…").font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(account.windows) { w in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(w.label).font(.subheadline)
                            Spacer()
                            Text("\(Int(w.utilization.rounded()))%")
                                .font(.subheadline.monospacedDigit().weight(.medium))
                                .foregroundStyle(w.utilization >= 70 ? w.color : .primary)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(.quaternary)
                                Capsule().fill(w.color)
                                    .frame(width: geo.size.width * min(w.utilization, 100) / 100)
                            }
                        }
                        .frame(height: 4)
                        if let reset = w.resetText {
                            Text(reset).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if let err = account.lastError, account.connected {
                Text(err).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.4)))
        .padding(.horizontal, 12)
    }
}

import SwiftUI
import AwakeCore

struct ContentView: View {
    @ObservedObject private var settings = AppConfigurationModel.shared
    @StateObject private var session = WakeSessionModel()
    @State private var installResult: String?

    private let durations = [0, 15, 30, 60, 120, 240, 480, 1440]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                assertionSettings
                sessionSettings
                automationSettings
                commandLineSection
                if let configurationError = settings.configurationError {
                    Text(configurationError).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                }
            }
            .padding(28)
        }
        .frame(minWidth: 520, minHeight: 560)
        .onAppear { settings.start() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: session.isActive ? "sun.max.fill" : "moon.zzz")
                    .font(.system(size: 28)).foregroundStyle(.tint)
                Text("Awake").font(.largeTitle.bold())
            }
            if settings.configuration.showWelcomeMessage {
                Text("Awake holds macOS power assertions so your Mac — and its display — stay on. Control it here, from the menu bar, or with the awake command.")
                    .foregroundStyle(.secondary)
            }
            Text(session.summary).font(.callout).foregroundStyle(session.isActive ? .primary : .secondary)
        }
    }

    private var assertionSettings: some View {
        section("What to keep awake", note: "These are the defaults for every session. Changing one while a session is running applies it immediately.") {
            ForEach(WakeAssertionKind.allCases, id: \.self) { kind in
                Toggle(isOn: Binding(
                    get: { settings.configuration.defaultAssertions[kind] },
                    set: { enabled in
                        settings.setAssertion(kind, enabled: enabled)
                        var updated = settings.configuration.defaultAssertions
                        updated[kind] = enabled
                        session.applyDefaultsToActiveSession(updated)
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(kind.title)
                        Text(kind.detail).font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .toggleStyle(.switch)
            }
            Text("macOS always sleeps a laptop when the lid closes; no app can hold that off with public APIs.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var sessionSettings: some View {
        section("How long", note: nil) {
            Picker("Default duration", selection: Binding(
                get: { settings.configuration.defaultDurationMinutes },
                set: { settings.setDefaultDurationMinutes($0) }
            )) {
                ForEach(durations, id: \.self) { minutes in
                    Text(minutes == 0 ? "Until I stop it" : WakeSessionModel.duration(minutes * 60)).tag(minutes)
                }
            }
            Toggle(isOn: Binding(
                get: { settings.configuration.activateAtLaunch },
                set: { settings.setActivateAtLaunch($0) }
            )) {
                Text("Start a session when Awake launches").frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(.switch)
            HStack {
                Button(session.isActive ? "Stop now" : "Start now") { session.toggle() }
                if let sessionError = session.sessionError {
                    Text(sessionError).font(.caption).foregroundStyle(.red)
                }
            }
        }
    }

    private var automationSettings: some View {
        section("Automation", note: "Start the loopback HTTP API with awake serve; restart it after changing these.") {
            Toggle(isOn: Binding(
                get: { settings.configuration.showWelcomeMessage },
                set: { settings.setShowWelcomeMessage($0) }
            )) {
                Text("Explain what Awake does in this window").frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(.switch)
            Picker("API address", selection: Binding(
                get: { settings.configuration.apiHost }, set: { settings.setAPIHost($0) }
            )) { Text("127.0.0.1").tag("127.0.0.1"); Text("::1").tag("::1") }
            TextField("API port", value: Binding(
                get: { settings.configuration.apiPort }, set: { settings.setAPIPort($0) }
            ), format: .number.grouping(.never))
        }
    }

    private var commandLineSection: some View {
        section("Command line", note: nil) {
            Button("Install Command Line Tool") { installCLI() }
            Text("awake on --display true --minutes 60 · awake state --json · awake off")
                .font(.callout.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
            if let installResult {
                Text(installResult).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
    }

    private func section<Content: View>(_ title: String, note: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            if let note { Text(note).font(.caption).foregroundStyle(.secondary) }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func installCLI() {
        do {
            installResult = "Installed \(try CLIInstaller.install().path)"
        } catch {
            installResult = error.localizedDescription
        }
    }
}

#Preview {
    ContentView()
}

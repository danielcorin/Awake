import SwiftUI
import AwakeCore

/// Awake's entire interface: one switch, what it holds, and how long for.
/// Everything else lives in `awake config` and the CLI.
struct ContentView: View {
    @ObservedObject private var settings = AppConfigurationModel.shared
    @ObservedObject private var session = WakeSessionModel.shared

    private let durations = [0, 15, 30, 60, 120, 240, 480, 1440]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle(isOn: Binding(get: { session.isActive }, set: { _ in session.toggle() })) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Keep this Mac awake")
                    Text(session.summary).font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(.switch)

            Divider()

            ForEach(WakeAssertionKind.allCases, id: \.self) { kind in
                Toggle(kind.title, isOn: Binding(
                    get: { settings.configuration.defaultAssertions[kind] },
                    set: { enabled in
                        settings.setAssertion(kind, enabled: enabled)
                        var updated = settings.configuration.defaultAssertions
                        updated[kind] = enabled
                        session.applyDefaultsToActiveSession(updated)
                    }
                ))
            }

            Picker("For", selection: Binding(
                get: { settings.configuration.defaultDurationMinutes },
                set: { settings.setDefaultDurationMinutes($0) }
            )) {
                ForEach(durations, id: \.self) { minutes in
                    Text(minutes == 0 ? "Until I stop it" : WakeSessionModel.duration(minutes * 60)).tag(minutes)
                }
            }

            HotkeyField(settings: settings)

            if let message = session.sessionError ?? settings.configurationError ?? AppRuntime.shared.hotkeyError {
                Text(message).font(.caption).foregroundStyle(.red)
            }

            Divider()

            HStack {
                Button("About") { AppRuntime.shared.showAbout() }
                Button(installed ? "CLI installed" : "Install CLI") { installCLI() }
                    .disabled(installed)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .buttonStyle(.link)
            .font(.caption)
        }
        .padding(14)
        .frame(width: 260)
        .onAppear { settings.start() }
    }

    @State private var installed = CLIInstaller.isInstalled

    private func installCLI() {
        installed = (try? CLIInstaller.install()) != nil
    }
}

#Preview {
    ContentView()
}

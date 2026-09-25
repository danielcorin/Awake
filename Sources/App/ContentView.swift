import SwiftUI
import AwakeCore

/// Awake's entire interface: one switch, what it holds, and how long for.
/// Everything else lives in `awake config` and the CLI.
struct ContentView: View {
    @ObservedObject private var settings = AppConfigurationModel.shared
    @ObservedObject private var session = WakeSessionModel.shared
    @State private var installed = CLIInstaller.isInstalled
    @State private var installError: String?

    private static let presetDurations = [0, 15, 30, 60, 120, 240, 480, 1440]

    /// The presets plus whatever `awake config set default-duration-minutes`
    /// chose, so the picker never shows a blank selection.
    private var durations: [Int] {
        let configured = settings.configuration.defaultDurationMinutes
        return Self.presetDurations.contains(configured) ? Self.presetDurations : (Self.presetDurations + [configured]).sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle(isOn: Binding(get: { session.isActive }, set: { _ in session.toggle() })) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Keep this Mac awake")
                    summary.font(.caption).foregroundStyle(.secondary).monospacedDigit()
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
                .help(kind.detail)
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

            if let message = session.sessionError ?? settings.configurationError ?? AppRuntime.shared.hotkeyError ?? installError {
                Text(message).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack {
                Button("About") { AppRuntime.shared.showAbout() }
                Button(installed ? "CLI installed" : "Install CLI") { installCLI() }
                    .disabled(installed)
                    .help(installed ? CLIInstaller.destinationURL.path : "Link the awake command into ~/.local/bin")
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

    /// Only a timed session needs a clock, and `TimelineView` stops ticking
    /// while the panel is off screen.
    @ViewBuilder private var summary: some View {
        if session.snapshot.expiresAt != nil {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(session.summary(at: context.date))
            }
        } else {
            Text(session.summary(at: .now))
        }
    }

    private func installCLI() {
        do {
            _ = try CLIInstaller.install()
            installed = true
            installError = nil
        } catch {
            installError = error.localizedDescription
        }
    }
}

#Preview {
    ContentView()
}

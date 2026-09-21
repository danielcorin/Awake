import SwiftUI
import AwakeCore

/// The menu bar panel: the switch people actually use, the three assertion
/// toggles, and quick durations. Everything here writes through the same
/// operations and settings the CLI uses.
struct MenuBarView: View {
    @ObservedObject var session: WakeSessionModel
    @ObservedObject private var settings = AppConfigurationModel.shared

    private let quickDurations = [15, 30, 60, 120, 240, 480]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: Binding(get: { session.isActive }, set: { _ in session.toggle() })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Keep this Mac awake").font(.headline)
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
                .toggleStyle(.checkbox)
            }

            Divider()

            Text("Start a timed session").font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 6) {
                ForEach(quickDurations, id: \.self) { minutes in
                    Button(WakeSessionModel.duration(minutes * 60)) { session.start(minutes: minutes) }
                }
                Button("Forever") { session.start(minutes: 0) }
            }

            if let sessionError = session.sessionError {
                Text(sessionError).font(.caption).foregroundStyle(.red)
            }

            Divider()

            HStack {
                Button("Settings…") { Task { _ = try? await AppRuntime.shared.show(.init()) } }
                Spacer()
                Button("Quit Awake") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 280)
    }
}

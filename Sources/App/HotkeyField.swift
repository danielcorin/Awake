import SwiftUI
import AwakeCore

/// A one-line shortcut recorder. While recording it swallows key events with a
/// local monitor so the keystroke configures the shortcut instead of reaching
/// the controls behind it.
struct HotkeyField: View {
    @ObservedObject var settings: AppConfigurationModel
    @State private var recording = false
    @State private var monitor: Any?

    private var shortcut: HotkeyShortcut? { HotkeyShortcut(parsing: settings.configuration.toggleHotkey) }

    var body: some View {
        HStack(spacing: 6) {
            Text("Shortcut")
            Spacer()
            Button(title) { recording ? stop() : start() }
                .fixedSize()
            if shortcut != nil && !recording {
                Button {
                    settings.setToggleHotkey(nil)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Clear shortcut")
            }
        }
        .onDisappear(perform: stop)
    }

    private var title: String {
        if recording { return "Press keys…" }
        return shortcut?.symbolic ?? "Set…"
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            if event.keyCode == 53 { stop(); return nil }          // Escape cancels
            if let recorded = GlobalHotkeyMonitor.shortcut(from: event) {
                settings.setToggleHotkey(recorded)
                stop()
            }
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

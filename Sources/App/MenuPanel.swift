import AppKit
import SwiftUI

/// A borderless window can't become key by default, but the shortcut recorder
/// needs key events, so allow it explicitly. Escape dismisses it like a menu.
final class MenuPanel: NSPanel {
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

/// Menu chrome for the panel: the system menu material, rounded the way an
/// `NSMenu` is, with a hairline edge so it reads against a light desktop.
struct MenuPanelContent: View {
    private static let cornerRadius = 10.0

    var body: some View {
        ContentView()
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                    .strokeBorder(.separator, lineWidth: 0.5)
            )
            // The panel itself is transparent, so leave room for the shadow.
            .padding(1)
    }
}

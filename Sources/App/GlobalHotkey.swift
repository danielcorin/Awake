import AppKit
import Carbon.HIToolbox
import AwakeCore

/// Registers the configured shortcut with the window server.
///
/// Carbon hot keys are used deliberately: `NSEvent`'s global monitor needs
/// Accessibility permission and cannot swallow the key, while
/// `RegisterEventHotKey` needs no permission and claims the combination.
@MainActor
final class GlobalHotkeyMonitor {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var current: HotkeyShortcut?
    private let action: () -> Void

    /// The Carbon handler is a C callback, so the target is reached statically.
    private static var active: GlobalHotkeyMonitor?
    private static let signature: OSType = 0x41_57_4B_45 // 'AWKE'

    init(action: @escaping () -> Void) {
        self.action = action
        Self.active = self
    }

    deinit { MainActor.assumeIsolated { unregister() } }

    /// Applies the configured shortcut, returning a message when the setting
    /// could not be registered. Re-registering the same shortcut is a no-op.
    @discardableResult
    func apply(_ configuration: AppConfiguration) -> String? {
        let shortcut = configuration.toggleHotkey.isEmpty ? nil : HotkeyShortcut(parsing: configuration.toggleHotkey)
        if configuration.toggleHotkey.isEmpty == false && shortcut == nil {
            return "“\(configuration.toggleHotkey)” is not a usable shortcut."
        }
        guard shortcut != current else { return nil }
        unregister()
        current = shortcut
        guard let shortcut else { return nil }
        installHandler()
        var reference: EventHotKeyRef?
        let identifier = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(shortcut.keyCode, Self.carbonModifiers(shortcut.modifiers),
                                         identifier, GetApplicationEventTarget(), 0, &reference)
        guard status == noErr, let reference else {
            current = nil
            return "\(shortcut.symbolic) is already claimed by another app."
        }
        hotKeyRef = reference
        return nil
    }

    private func installHandler() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var identifier = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard identifier.signature == GlobalHotkeyMonitor.signature else { return OSStatus(eventNotHandledErr) }
            DispatchQueue.main.async { MainActor.assumeIsolated { GlobalHotkeyMonitor.active?.action() } }
            return noErr
        }, 1, &spec, nil, &handlerRef)
    }

    private func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }

    private static func carbonModifiers(_ modifiers: HotkeyShortcut.Modifiers) -> UInt32 {
        var value: UInt32 = 0
        if modifiers.contains(.control) { value |= UInt32(controlKey) }
        if modifiers.contains(.option) { value |= UInt32(optionKey) }
        if modifiers.contains(.shift) { value |= UInt32(shiftKey) }
        if modifiers.contains(.command) { value |= UInt32(cmdKey) }
        return value
    }

    /// Translates a recorded key event into a storable shortcut.
    static func shortcut(from event: NSEvent) -> HotkeyShortcut? {
        var modifiers = HotkeyShortcut.Modifiers()
        if event.modifierFlags.contains(.control) { modifiers.insert(.control) }
        if event.modifierFlags.contains(.option) { modifiers.insert(.option) }
        if event.modifierFlags.contains(.shift) { modifiers.insert(.shift) }
        if event.modifierFlags.contains(.command) { modifiers.insert(.command) }
        guard HotkeyShortcut.keyName(for: UInt32(event.keyCode)) != nil,
              !modifiers.isDisjoint(with: [.control, .option, .command]) else { return nil }
        return HotkeyShortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers)
    }
}

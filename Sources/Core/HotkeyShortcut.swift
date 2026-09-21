import Foundation

/// A system-wide shortcut, stored in TOML as readable text such as `opt+cmd+a`.
/// Parsing and formatting live here so the settings file, the CLI, and the
/// recorder in the UI all agree on what a valid shortcut is.
public struct HotkeyShortcut: Equatable, Sendable {
    public struct Modifiers: OptionSet, Equatable, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }
        public static let control = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let shift = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)
    }

    public var keyCode: UInt32
    public var modifiers: Modifiers

    public init(keyCode: UInt32, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Standard ANSI virtual key codes. Keeping the table here avoids importing
    /// Carbon into every layer that only needs to name a key.
    static let keys: KeyValuePairs<String, UInt32> = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26,
        "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35,
        "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45,
        "m": 46, ".": 47, "`": 50,
        "return": 36, "tab": 48, "space": 49, "delete": 51, "escape": 53,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98, "f8": 100,
        "f9": 101, "f10": 109, "f11": 103, "f12": 111,
        "left": 123, "right": 124, "down": 125, "up": 126,
    ]
    private static let aliases = ["command": "cmd", "control": "ctrl", "alt": "opt", "option": "opt", "ctl": "ctrl"]
    private static let modifierNames: [(String, Modifiers, String)] = [
        ("ctrl", .control, "\u{2303}"), ("opt", .option, "\u{2325}"),
        ("shift", .shift, "\u{21E7}"), ("cmd", .command, "\u{2318}"),
    ]

    public static func keyCode(for name: String) -> UInt32? {
        keys.first { $0.key == name.lowercased() }?.value
    }
    public static func keyName(for keyCode: UInt32) -> String? {
        keys.first { $0.value == keyCode }?.key
    }

    /// Returns nil for anything unparseable, including a shortcut with no
    /// modifier other than shift, which would swallow ordinary typing.
    public init?(parsing text: String) {
        let tokens = text.lowercased().split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let key = tokens.last, !key.isEmpty else { return nil }
        var modifiers = Modifiers()
        for token in tokens.dropLast() {
            let name = Self.aliases[token] ?? token
            guard let match = Self.modifierNames.first(where: { $0.0 == name }) else { return nil }
            modifiers.insert(match.1)
        }
        guard let code = Self.keyCode(for: key) else { return nil }
        guard !modifiers.isDisjoint(with: [.control, .option, .command]) else { return nil }
        self.init(keyCode: code, modifiers: modifiers)
    }

    /// Canonical TOML form, always modifiers in a fixed order then the key.
    public var text: String {
        let parts = Self.modifierNames.filter { modifiers.contains($0.1) }.map(\.0)
        return (parts + [Self.keyName(for: keyCode) ?? "?"]).joined(separator: "+")
    }

    /// Menu-style rendering for the UI, for example `⌥⌘A`.
    public var symbolic: String {
        let symbols = Self.modifierNames.filter { modifiers.contains($0.1) }.map(\.2).joined()
        let key = Self.keyName(for: keyCode) ?? "?"
        return symbols + (key.count == 1 ? key.uppercased() : key.capitalized)
    }
}

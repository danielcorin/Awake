import Foundation
import IOKit.pwr_mgt

/// One IOKit power assertion Awake knows how to hold. The raw values are the
/// documented public assertion type strings; `caffeinate` holds the same ones.
public enum WakeAssertionKind: String, CaseIterable, Codable, Sendable {
    case preventSystemSleep, keepDisplayOn, preventDiskIdle

    public var assertionType: String {
        switch self {
        case .preventSystemSleep: kIOPMAssertPreventUserIdleSystemSleep as String
        case .keepDisplayOn: kIOPMAssertPreventUserIdleDisplaySleep as String
        case .preventDiskIdle: kIOPMAssertPreventDiskIdle as String
        }
    }
    public var title: String {
        switch self {
        case .preventSystemSleep: "Prevent system sleep"
        case .keepDisplayOn: "Keep display on"
        case .preventDiskIdle: "Prevent disk idle"
        }
    }
    public var detail: String {
        switch self {
        case .preventSystemSleep: "The Mac will not fall asleep on its own. The display can still dim and sleep."
        case .keepDisplayOn: "The display stays lit and the screen saver never starts."
        case .preventDiskIdle: "Disks are not spun down while the Mac is idle."
        }
    }
}

/// Which assertions a session holds, or which ones it holds by default.
public struct WakeAssertionSet: Equatable, Codable, Sendable {
    public var preventSystemSleep: Bool
    public var keepDisplayOn: Bool
    public var preventDiskIdle: Bool

    public init(preventSystemSleep: Bool = false, keepDisplayOn: Bool = false, preventDiskIdle: Bool = false) {
        self.preventSystemSleep = preventSystemSleep
        self.keepDisplayOn = keepDisplayOn
        self.preventDiskIdle = preventDiskIdle
    }
    public static let none = WakeAssertionSet()

    public subscript(kind: WakeAssertionKind) -> Bool {
        get {
            switch kind {
            case .preventSystemSleep: preventSystemSleep
            case .keepDisplayOn: keepDisplayOn
            case .preventDiskIdle: preventDiskIdle
            }
        }
        set {
            switch kind {
            case .preventSystemSleep: preventSystemSleep = newValue
            case .keepDisplayOn: keepDisplayOn = newValue
            case .preventDiskIdle: preventDiskIdle = newValue
            }
        }
    }
    public var kinds: [WakeAssertionKind] { WakeAssertionKind.allCases.filter { self[$0] } }
    public var isEmpty: Bool { kinds.isEmpty }
}

/// The platform seam. The app holds real IOKit assertions; tests inject a
/// recording controller so a scenario run never keeps the machine awake.
public protocol PowerAssertionController: Sendable {
    func hold(_ kind: WakeAssertionKind, reason: String) throws -> UInt32
    func release(_ token: UInt32)
}

public struct IOKitPowerAssertionController: PowerAssertionController {
    public init() {}

    public func hold(_ kind: WakeAssertionKind, reason: String) throws -> UInt32 {
        var identifier: IOPMAssertionID = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            kind.assertionType as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &identifier
        )
        guard result == kIOReturnSuccess else { throw WakeSessionError.assertionFailed(kind: kind, code: result) }
        return UInt32(identifier)
    }

    public func release(_ token: UInt32) {
        IOPMAssertionRelease(IOPMAssertionID(token))
    }
}

/// Deterministic controller for tests and the automation fixture. It records
/// what would have been held without touching system power management.
public final class RecordingPowerAssertionController: PowerAssertionController, @unchecked Sendable {
    private let lock = NSLock()
    private var next: UInt32 = 1
    private var live: [UInt32: WakeAssertionKind] = [:]

    public init() {}

    public var heldKinds: [WakeAssertionKind] {
        lock.lock(); defer { lock.unlock() }
        return WakeAssertionKind.allCases.filter { live.values.contains($0) }
    }

    public func hold(_ kind: WakeAssertionKind, reason: String) throws -> UInt32 {
        lock.lock(); defer { lock.unlock() }
        let token = next
        next += 1
        live[token] = kind
        return token
    }

    public func release(_ token: UInt32) {
        lock.lock(); defer { lock.unlock() }
        live[token] = nil
    }
}

public enum WakeSessionError: LocalizedError, Sendable {
    case noAssertionsRequested
    case invalidDuration(minutes: Int)
    case assertionFailed(kind: WakeAssertionKind, code: Int32)

    public var errorDescription: String? {
        switch self {
        case .noAssertionsRequested:
            "Choose at least one of --system, --display, or --disk, or enable one in Awake's settings."
        case .invalidDuration(let minutes):
            "Use a duration from 0 through \(maximumWakeDurationMinutes) minutes; 0 stays awake until stopped. Received \(minutes)."
        case .assertionFailed(let kind, let code):
            "macOS refused the \(kind.title.lowercased()) assertion (IOReturn \(code))."
        }
    }
}

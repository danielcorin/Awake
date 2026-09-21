import Combine
import Darwin
import Foundation
import AwakeCore

@MainActor
final class AppConfigurationModel: ObservableObject {
    /// The settings window and the menu bar panel edit the same settings, so
    /// they share one model rather than racing two writers.
    static let shared = AppConfigurationModel()

    @Published private(set) var configuration: AppConfiguration
    @Published private(set) var configurationError: String?

    private let store: AppConfigurationStore
    private var directoryWatcher: ConfigurationDirectoryWatcher?
    private var distributedObserver: NSObjectProtocol?
    private var reloadTask: Task<Void, Never>?
    private var started = false

    init(store: AppConfigurationStore = AppConfigurationStore()) {
        self.store = store
        do {
            configuration = try store.load()
            configurationError = nil
        } catch {
            configuration = .defaults
            configurationError = error.localizedDescription
        }
    }

    func start() {
        guard !started else { return }
        started = true

        do {
            try store.prepareDirectory()
            directoryWatcher = try ConfigurationDirectoryWatcher(
                directoryURL: store.fileURL.deletingLastPathComponent()
            ) { [weak self] in
                Task { @MainActor [weak self] in
                    self?.scheduleReload()
                }
            }
        } catch {
            configurationError = "Couldn’t monitor the configuration file: \(error.localizedDescription)"
        }

        distributedObserver = DistributedNotificationCenter.default().addObserver(
            forName: AppConfigurationStore.changeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleReload()
            }
        }
    }

    private var pendingWrite: Task<Void, Never>?
    func setAssertion(_ kind: WakeAssertionKind, enabled: Bool) {
        switch kind {
        case .preventSystemSleep: set(.preventSystemSleep, value: String(enabled))
        case .keepDisplayOn: set(.keepDisplayOn, value: String(enabled))
        case .preventDiskIdle: set(.preventDiskIdle, value: String(enabled))
        }
    }
    func setDefaultDurationMinutes(_ minutes: Int) { set(.defaultDurationMinutes, value: String(minutes)) }
    func setToggleHotkey(_ shortcut: HotkeyShortcut?) { set(.toggleHotkey, value: shortcut?.text ?? "") }
    private func set(_ key: AppConfigurationKey, value: String) {
        let previous = pendingWrite
        pendingWrite = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            do {
                _ = try await ConfigurationOperationService(store: store).configSet(.init(key: key.rawValue, value: value))
                configuration = try store.load()
                AppRuntime.shared.applyHotkey(configuration)
                configurationError = nil
            } catch { configurationError = error.localizedDescription }
        }
    }

    func reload() {
        do {
            configuration = try store.load()
            AppRuntime.shared.applyHotkey(configuration)
            configurationError = nil
        } catch {
            configurationError = error.localizedDescription
        }
    }

    private func scheduleReload() {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            self?.reload()
        }
    }
}

private final class ConfigurationDirectoryWatcher: @unchecked Sendable {
    private let descriptor: Int32
    private let source: DispatchSourceFileSystemObject

    init(directoryURL: URL, onChange: @escaping @Sendable () -> Void) throws {
        descriptor = Darwin.open(directoryURL.path, O_EVTONLY)
        guard descriptor >= 0 else {
            throw CocoaError(.fileReadNoPermission)
        }

        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete],
            queue: DispatchQueue(label: "llc.wvlen.Awake.configuration-watcher")
        )
        source.setEventHandler(handler: onChange)
        source.setCancelHandler { [descriptor] in
            Darwin.close(descriptor)
        }
        source.resume()
    }

    deinit {
        source.cancel()
    }
}

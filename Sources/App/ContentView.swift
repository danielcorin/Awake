import SwiftUI

struct ContentView: View {
    @StateObject private var configurationModel = AppConfigurationModel()
    @State private var installResult: String?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "hammer.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("Awake")
                .font(.largeTitle.bold())
            if configurationModel.configuration.showWelcomeMessage {
                Text("A macOS app with a companion CLI for agents and automation.")
                    .foregroundStyle(.secondary)
            }

            Toggle(
                "Show welcome message",
                isOn: Binding(
                    get: { configurationModel.configuration.showWelcomeMessage },
                    set: { configurationModel.setShowWelcomeMessage($0) }
                )
            )
            .toggleStyle(.switch)

            Picker("API address", selection: Binding(
                get: { configurationModel.configuration.apiHost }, set: { configurationModel.setAPIHost($0) }
            )) { Text("127.0.0.1").tag("127.0.0.1"); Text("::1").tag("::1") }
            TextField("API port", value: Binding(
                get: { configurationModel.configuration.apiPort }, set: { configurationModel.setAPIPort($0) }
            ), format: .number.grouping(.never))
            Text("Start with awake serve. Restart the server after changing its address or port.")
                .font(.caption).foregroundStyle(.secondary)

            Button("Install Command Line Tool") {
                installCLI()
            }

            Text("Then run `awake help` or `awake status --json`.")
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            if let installResult {
                Text(installResult)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            if let configurationError = configurationModel.configurationError {
                Text(configurationError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
        .padding(40)
        .frame(minWidth: 460, minHeight: 300)
        .onAppear {
            configurationModel.start()
        }
    }

    private func installCLI() {
        do {
            let url = try CLIInstaller.install()
            installResult = "Installed \(url.path)"
        } catch {
            installResult = error.localizedDescription
        }
    }
}

#Preview {
    ContentView()
}

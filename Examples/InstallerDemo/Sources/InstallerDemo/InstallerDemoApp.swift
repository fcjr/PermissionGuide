import DemoSetup
import PermissionInstaller
import SwiftUI

@main
struct InstallerDemoApp: App {
    init() {
        // When the installer launches the app to check or perform a step, this handles
        // it and exits before any window appears.
        InstallerSetup.demo.handleInstallerLaunch()
    }

    var body: some Scene {
        Window("InstallerDemo", id: "main") {
            VStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.indigo)
                Text("InstallerDemo is installed")
                    .font(.title2.weight(.semibold))
            }
            .padding(40)
        }
        .windowResizability(.contentSize)
    }
}

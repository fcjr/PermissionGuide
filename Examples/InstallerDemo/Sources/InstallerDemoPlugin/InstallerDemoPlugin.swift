import DemoSetup
import Foundation
import PermissionInstaller
import PermissionInstallerPlugin

/// Named in Resources/Plugin-Info.plist under PermissionInstallerProvider.
@objc(InstallerDemoPlugin)
final class InstallerDemoPlugin: InstallerPlugin {
    override var setup: InstallerSetup { .demo }
}

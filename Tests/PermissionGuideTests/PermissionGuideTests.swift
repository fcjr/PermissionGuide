import AppKit
import PermissionGuideProbe
import Testing
@testable import PermissionGuide

private let window = NSRect(x: 0, y: 0, width: 800, height: 600)
private let touchID = SystemSettings.Prompt.panel(NSRect(x: 260, y: 160, width: 280, height: 273), window: 1)
private let alert = SystemSettings.Prompt.panel(NSRect(x: 260, y: 190, width: 280, height: 220), window: 2)
private let password = SystemSettings.Prompt.authentication(NSRect(x: 200, y: 150, width: 400, height: 300), window: 3)

@Suite struct PromptTrackerTests {
    @Test func firstPanelIsAuthenticationThenTheAlert() {
        var t = PromptTracker()
        _ = t.update(alert)
        #expect(t.phase == .prompt(.authentication(alert.frame)), "nothing asks to relaunch before authenticating")
        let closed = t.update(alert)
        #expect(!closed)
        #expect(t.phase == .prompt(.authentication(alert.frame)), "the same window stays the same prompt")

        var u = PromptTracker()
        _ = u.update(password)
        _ = u.update(nil)
        _ = u.update(alert)
        #expect(u.phase == .prompt(.relaunch(alert.frame)))
        #expect(u.isShowingRelaunchPrompt)
    }

    @Test func aTallPanelAfterAuthenticationIsARetry() {
        var t = PromptTracker()
        _ = t.update(touchID)
        _ = t.update(nil)
        _ = t.update(touchID)
        #expect(t.phase == .prompt(.authentication(touchID.frame)))
        _ = t.update(alert)
        #expect(t.phase == .prompt(.relaunch(alert.frame)), "the alert can replace Touch ID within one tick")
    }

    @Test func laterLeavesTheGuideGrantedWithNothingHighlighted() {
        var t = PromptTracker()
        _ = t.update(touchID)
        _ = t.update(nil)
        _ = t.update(alert)
        let closed = t.update(nil)
        #expect(closed, "the alert closing is reported")
        #expect(t.phase == .granted)
        for _ in 0..<120 {
            let again = t.update(nil)
            #expect(!again, "only once")
        }
        #expect(t.phase == .granted, "it doesn't fall back to the drag instructions on its own")
        #expect(!t.isShowingRelaunchPrompt)
    }

    /// A panel System Settings showed on its own while the guide waited (measured on macOS
    /// 27): it zoomed from 239×202 to 260×220 and back, and dropped out of the window list
    /// for a tick. Taking its later frames for the "Quit & Reopen" alert left the guide
    /// thinking the grant had gone through.
    @Test func aZoomingPanelStaysOnePrompt() {
        var t = PromptTracker()
        var closed = false
        let heights: [CGFloat] = [202, 206, 211, 219, 223, 220, 220]
        for h in heights {
            closed = t.update(.panel(NSRect(x: 422, y: 366, width: 260, height: h), window: 40572)) || closed
            #expect(!t.isShowingRelaunchPrompt)
        }
        closed = t.update(nil) || closed
        for h in heights.reversed() {
            closed = t.update(.panel(NSRect(x: 422, y: 366, width: 260, height: h), window: 40572)) || closed
            #expect(t.phase == .prompt(.authentication(NSRect(x: 422, y: 366, width: 260, height: h))))
        }
        for _ in 0...PromptTracker.authenticationGapTicks { closed = t.update(nil) || closed }
        #expect(!closed)
        #expect(t.phase == .instructions)
    }

    @Test func resumeReturnsToInstructions() {
        var t = PromptTracker()
        _ = t.update(touchID)
        _ = t.update(nil)
        _ = t.update(alert)
        _ = t.update(nil)
        t.resume()
        #expect(t.phase == .instructions)
    }

    @Test func authenticationClosingHoldsBeforeTheInstructions() {
        var t = PromptTracker()
        _ = t.update(touchID)
        let closed = t.update(nil)
        #expect(!closed)
        #expect(t.phase == .afterAuthentication(ticks: 0))
        for _ in 1..<PromptTracker.authenticationGapTicks {
            _ = t.update(nil)
            #expect(t.phase.isAfterAuthentication)
        }
        _ = t.update(nil)
        #expect(t.phase == .instructions, "cancelled authentication: back to the list")
    }

    @Test func resumeOnlyLeavesTheGrantedPhase() {
        var t = PromptTracker()
        _ = t.update(touchID)
        t.resume()
        #expect(t.phase == .prompt(.authentication(touchID.frame)))
    }
}

@Suite struct ProbeTests {
    @Test func probeNamesMatchRelaunchPermissions() {
        for permission in Permission.privacyPermissions {
            #expect((Probe.name(for: permission) != nil) == permission.mayNeedRelaunch, "\(permission)")
        }
        #expect(Permission.fullDiskAccess.mayNeedRelaunch)
        #expect(Permission.screenRecording.mayNeedRelaunch)
        #expect(!Permission.accessibility.mayNeedRelaunch)
    }

    @Test func asksOnlyWhatItCanCheckOnce() {
        let asked = Probe.asked([.accessibility, .fullDiskAccess, .screenRecording, .fullDiskAccess])
        #expect(asked == [.fullDiskAccess, .screenRecording])
        #expect(Probe.environmentValue(for: asked) == "fullDiskAccess,screenRecording")
    }

    @Test func decodesExitStatus() {
        let asked: [Permission] = [.fullDiskAccess, .screenRecording, .inputMonitoring]
        #expect(Probe.grants(fromExitStatus: PERMISSIONGUIDE_PROBE_ANSWERED, asked: asked) == [])
        #expect(Probe.grants(fromExitStatus: PERMISSIONGUIDE_PROBE_ANSWERED | 0b001, asked: asked) == [.fullDiskAccess])
        #expect(Probe.grants(fromExitStatus: PERMISSIONGUIDE_PROBE_ANSWERED | 0b110, asked: asked) == [.screenRecording, .inputMonitoring])
    }

    @Test func otherExitStatusesAreNotAnswers() {
        // A copy of the app that started up normally (no probe linked) and quit.
        #expect(Probe.grants(fromExitStatus: 0, asked: [.fullDiskAccess]) == nil)
        #expect(Probe.grants(fromExitStatus: 1, asked: [.fullDiskAccess]) == nil)
        #expect(Probe.grants(fromExitStatus: 2, asked: [.fullDiskAccess]) == nil)
        #expect(Probe.grants(fromExitStatus: PERMISSIONGUIDE_PROBE_ANSWERED | 0x80, asked: [.fullDiskAccess]) == nil)
    }

    @Test func constructorRanInThisProcess() {
        #expect(Probe.isAvailable)
    }

    /// Runs the probe against a tiny C program linked the same way an app would be, to
    /// check the constructor answers before main.
    @Test func freshProcessAnswers() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "pk-probe-\(getpid())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = URL(filePath: #filePath).deletingLastPathComponent()
            .appending(path: "../../Sources/PermissionGuideProbe").standardized
        let main = dir.appending(path: "main.c")
        try "int main(void) { return 7; }\n".write(to: main, atomically: true, encoding: .utf8)
        let exe = dir.appending(path: "probe-host")
        let cc = Process()
        cc.executableURL = URL(filePath: "/usr/bin/xcrun")
        cc.arguments = ["clang", "-I", source.appending(path: "include").path, main.path,
                        source.appending(path: "PermissionGuideProbe.c").path,
                        "-framework", "CoreGraphics", "-framework", "IOKit", "-o", exe.path]
        try cc.run()
        cc.waitUntilExit()
        try #require(cc.terminationStatus == 0)

        let plain = Process()
        plain.executableURL = exe
        try plain.run()
        plain.waitUntilExit()
        #expect(plain.terminationStatus == 7, "without the variable the app starts normally")

        let answer = await Probe.run([.fullDiskAccess, .screenRecording], executable: exe)
        #expect(answer != nil)
    }
}

@Suite struct SystemExtensionSetupTests {
    private static let networkEntitlement = "com.apple.developer.networking.networkextension"

    /// An unsigned `.app` in a temporary folder, with the named extensions embedded.
    private func makeApp(embedding identifiers: [String] = []) throws -> (bundle: Bundle, cleanUp: () -> Void) {
        let root = FileManager.default.temporaryDirectory.appending(path: "pg-setup-\(UUID().uuidString)")
        let app = root.appending(path: "Sample.app")
        try write(["CFBundleIdentifier": "com.example.sample", "CFBundlePackageType": "APPL"], in: app)
        for identifier in identifiers {
            let ext = app.appending(path: "Contents/Library/SystemExtensions/\(identifier).systemextension")
            try write(["CFBundleIdentifier": identifier, "CFBundlePackageType": "SYSX"], in: ext)
        }
        let bundle = try #require(Bundle(url: app))
        return (bundle, { try? FileManager.default.removeItem(at: root) })
    }

    private func write(_ info: [String: String], in bundle: URL) throws {
        let contents = bundle.appending(path: "Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: contents.appending(path: "Info.plist"))
    }

    @Test func anAppWithNothingSetUp() throws {
        let (bundle, cleanUp) = try makeApp()
        defer { cleanUp() }
        let ext = SystemExtension(identifier: "com.example.sample.tunnel", category: .networkExtension, displayName: "Sample")
        #expect(ext.embeddedURL(in: bundle) == nil)
        #expect(ext.setupIssues(in: bundle) == [.appNotInApplicationsFolder, .appMissingInstallEntitlement, .extensionNotEmbedded])
    }

    @Test func findsTheEmbeddedExtensionByIdentifier() throws {
        let (bundle, cleanUp) = try makeApp(embedding: ["com.example.sample.other", "com.example.sample.tunnel"])
        defer { cleanUp() }
        let ext = SystemExtension(identifier: "com.example.sample.tunnel", category: .networkExtension, displayName: "Sample")
        let url = try #require(ext.embeddedURL(in: bundle))
        #expect(url.lastPathComponent == "com.example.sample.tunnel.systemextension")

        let missing = SystemExtension(identifier: "com.example.sample.nope", category: .networkExtension, displayName: "Sample")
        #expect(missing.embeddedURL(in: bundle) == nil)
        #expect(missing.setupIssues(in: bundle).contains(.extensionNotEmbedded))
    }

    @Test func anEmbeddedExtensionWithoutItsEntitlement() throws {
        let (bundle, cleanUp) = try makeApp(embedding: ["com.example.sample.tunnel"])
        defer { cleanUp() }
        let ext = SystemExtension(identifier: "com.example.sample.tunnel", category: .networkExtension, displayName: "Sample")
        #expect(ext.setupIssues(in: bundle) == [
            .appNotInApplicationsFolder, .appMissingInstallEntitlement,
            .extensionMissingEntitlement(Self.networkEntitlement),
        ])
    }

    @Test func aCameraExtensionNeedsNoEntitlementOfItsOwn() throws {
        let (bundle, cleanUp) = try makeApp(embedding: ["com.example.sample.camera"])
        defer { cleanUp() }
        let ext = SystemExtension(identifier: "com.example.sample.camera", category: .cameraExtension, displayName: "Sample")
        #expect(ext.setupIssues(in: bundle) == [.appNotInApplicationsFolder, .appMissingInstallEntitlement])
    }

    /// Signs the bundles ad hoc with the entitlements macOS looks for, which leaves only
    /// the app's location to complain about.
    @Test func signedWithTheRightEntitlements() throws {
        let (bundle, cleanUp) = try makeApp(embedding: ["com.example.sample.tunnel"])
        defer { cleanUp() }
        let ext = SystemExtension(identifier: "com.example.sample.tunnel", category: .networkExtension, displayName: "Sample")
        let extURL = try #require(ext.embeddedURL(in: bundle))
        try sign(extURL, entitlements: [Self.networkEntitlement: ["packet-tunnel-provider"]])
        try sign(bundle.bundleURL, entitlements: ["com.apple.developer.system-extension.install": true])
        #expect(ext.setupIssues(in: bundle) == [.appNotInApplicationsFolder])
    }

    @Test func everyIssueDescribesItself() {
        let issues: [SystemExtension.SetupIssue] = [
            .appNotInApplicationsFolder, .extensionNotEmbedded, .appMissingInstallEntitlement,
            .extensionMissingEntitlement(Self.networkEntitlement),
        ]
        for issue in issues { #expect(!issue.description.isEmpty) }
        #expect(issues[3].description.contains(Self.networkEntitlement))
    }

    private func sign(_ bundle: URL, entitlements: [String: Any]) throws {
        // codesign needs something to sign as the bundle's executable.
        let name = bundle.deletingPathExtension().lastPathComponent
        let macOS = bundle.appending(path: "Contents/MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: URL(filePath: "/usr/bin/true"), to: macOS.appending(path: name))
        var info = try #require(NSDictionary(contentsOf: bundle.appending(path: "Contents/Info.plist")) as? [String: Any])
        info["CFBundleExecutable"] = name
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: bundle.appending(path: "Contents/Info.plist"))

        let plist = bundle.deletingLastPathComponent().appending(path: "\(name).entitlements")
        try PropertyListSerialization.data(fromPropertyList: entitlements, format: .xml, options: 0).write(to: plist)
        defer { try? FileManager.default.removeItem(at: plist) }
        let codesign = Process()
        codesign.executableURL = URL(filePath: "/usr/bin/codesign")
        codesign.arguments = ["--force", "--sign", "-", "--entitlements", plist.path, bundle.path]
        codesign.standardError = FileHandle.nullDevice
        try codesign.run()
        codesign.waitUntilExit()
        try #require(codesign.terminationStatus == 0)
    }
}

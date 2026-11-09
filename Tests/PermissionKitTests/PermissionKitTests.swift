import AppKit
import PermissionKitProbe
import Testing
@testable import PermissionKit

private let window = NSRect(x: 0, y: 0, width: 800, height: 600)
private let touchID = SystemSettings.Prompt.panel(NSRect(x: 260, y: 160, width: 280, height: 273))
private let alert = SystemSettings.Prompt.panel(NSRect(x: 260, y: 190, width: 280, height: 220))
private let password = SystemSettings.Prompt.authentication(NSRect(x: 200, y: 150, width: 400, height: 300))

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
        #expect(Probe.grants(fromExitStatus: PK_PROBE_ANSWERED, asked: asked) == [])
        #expect(Probe.grants(fromExitStatus: PK_PROBE_ANSWERED | 0b001, asked: asked) == [.fullDiskAccess])
        #expect(Probe.grants(fromExitStatus: PK_PROBE_ANSWERED | 0b110, asked: asked) == [.screenRecording, .inputMonitoring])
    }

    @Test func otherExitStatusesAreNotAnswers() {
        // A copy of the app that started up normally (no probe linked) and quit.
        #expect(Probe.grants(fromExitStatus: 0, asked: [.fullDiskAccess]) == nil)
        #expect(Probe.grants(fromExitStatus: 1, asked: [.fullDiskAccess]) == nil)
        #expect(Probe.grants(fromExitStatus: 2, asked: [.fullDiskAccess]) == nil)
        #expect(Probe.grants(fromExitStatus: PK_PROBE_ANSWERED | 0x80, asked: [.fullDiskAccess]) == nil)
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
            .appending(path: "../../Sources/PermissionKitProbe").standardized
        let main = dir.appending(path: "main.c")
        try "int main(void) { return 7; }\n".write(to: main, atomically: true, encoding: .utf8)
        let exe = dir.appending(path: "probe-host")
        let cc = Process()
        cc.executableURL = URL(filePath: "/usr/bin/xcrun")
        cc.arguments = ["clang", "-I", source.appending(path: "include").path, main.path,
                        source.appending(path: "PermissionKitProbe.c").path,
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

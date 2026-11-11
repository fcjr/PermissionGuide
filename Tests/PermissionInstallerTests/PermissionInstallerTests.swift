import AppKit
import PermissionGuide
import Testing
@testable import PermissionInstaller
@testable import PermissionInstallerPlugin

private let vpn = SystemExtension(identifier: "com.example.app.tunnel", category: .networkExtension, displayName: "Example VPN")

/// One of every kind of step, and every permission.
private let everyStep: [InstallerStep] = Permission.privacyPermissions.map { .permission($0) } + [
    .permission(.systemExtension(vpn)),
    .permission(.backgroundItem(daemonPlist: "com.example.app.helper.plist")),
    .networkConfiguration(.init(.packetTunnel, providerBundleIdentifier: "com.example.app.tunnel")),
    .certificate(.init(resourceName: "RootCA")),
    .custom(id: "library", title: "Library", heading: "Create the library", message: "It holds your data.",
            actionTitle: "Create", check: { nil }, perform: {}),
]

@Suite struct StepIDTests {
    /// The plugin passes these to the app on the command line, and the two can be built
    /// at different times, so a changed id breaks installers already shipped.
    @Test func idsAreStable() {
        #expect(everyStep.map(\.id) == [
            "permission.accessibility",
            "permission.appManagement",
            "permission.bluetooth",
            "permission.developerTools",
            "permission.fullDiskAccess",
            "permission.inputMonitoring",
            "permission.screenRecording",
            "sysext.com.example.app.tunnel",
            "permission.backgroundItem.com.example.app.helper.plist",
            "network.packetTunnel.com.example.app.tunnel",
            "certificate.RootCA.cer",
            "custom.library",
        ])
    }

    @Test func idsAreUnique() {
        #expect(InstallerSetup.duplicateIDs(in: everyStep).isEmpty)
    }

    @Test func stepsThatDifferOnlyInDetailGetTheirOwnIDs() {
        let steps: [InstallerStep] = [
            .certificate(.init(resourceName: "RootCA")),
            .certificate(.init(resourceName: "RootCA", extension: "der")),
            .networkConfiguration(.init(.packetTunnel, providerBundleIdentifier: "com.example.app.provider")),
            .networkConfiguration(.init(.appProxy, providerBundleIdentifier: "com.example.app.provider")),
            .permission(.backgroundItem(daemonPlist: "a.plist")),
            .permission(.backgroundItem(daemonPlist: "b.plist")),
        ]
        #expect(InstallerSetup.duplicateIDs(in: steps).isEmpty)
    }

    @Test func theSameStepTwiceIsReported() {
        let steps: [InstallerStep] = [.permission(.fullDiskAccess), .permission(.accessibility), .permission(.fullDiskAccess, .optional)]
        #expect(InstallerSetup.duplicateIDs(in: steps) == ["permission.fullDiskAccess"])
    }

    @Test func requirementDoesNotChangeTheID() {
        #expect(InstallerStep.permission(.accessibility).id == InstallerStep.permission(.accessibility, .optional).id)
    }
}

@Suite struct StepTextTests {
    @Test func privacyPermission() {
        let step = InstallerStep.permission(.fullDiskAccess)
        #expect(step.title == "Full Disk Access")
        #expect(step.resolvedHeading(appName: "MyApp") == "Allow Full Disk Access")
        #expect(step.resolvedMessage(appName: "MyApp")
            == "MyApp needs Full Disk Access. Click below, then drag MyApp into the highlighted list in System Settings.")
        #expect(step.resolvedActionTitle() == "Open System Settings")
        #expect(step.resolvedSymbolName() == "externaldrive")
        #expect(step.requirement == .required)
    }

    @Test func backgroundItem() {
        let step = InstallerStep.permission(.backgroundItem(daemonPlist: "helper.plist"))
        #expect(step.title == "Allow in the Background")
        #expect(step.resolvedHeading(appName: "MyApp") == "Allow MyApp in the background")
        #expect(step.resolvedMessage(appName: "MyApp").contains("turn on MyApp under Allow in the Background"))
    }

    @Test func systemExtension() {
        let step = InstallerStep.permission(.systemExtension(vpn))
        #expect(step.title == "Example VPN")
        #expect(step.resolvedHeading(appName: "MyApp") == "Allow the network extension")
        #expect(step.resolvedMessage(appName: "MyApp").hasPrefix("macOS will ask you to allow Example VPN."))
        #expect(step.resolvedActionTitle() == "Allow Extension")
    }

    @Test func networkConfiguration() {
        let tunnel = InstallerStep.networkConfiguration(.init(.packetTunnel, providerBundleIdentifier: "p"))
        #expect(tunnel.title == "VPN Configuration")
        #expect(tunnel.resolvedHeading(appName: "MyApp") == "Add the VPN configuration")
        #expect(tunnel.resolvedActionTitle() == "Add Configuration")

        let proxy = InstallerStep.networkConfiguration(.init(.transparentProxy, providerBundleIdentifier: "p"))
        #expect(proxy.title == "Proxy Configuration")
        #expect(proxy.resolvedHeading(appName: "MyApp") == "Add the proxy configuration")
    }

    @Test func certificate() {
        let step = InstallerStep.certificate(.init(resourceName: "RootCA"), .optional)
        #expect(step.title == "Certificate")
        #expect(step.resolvedHeading(appName: "MyApp") == "Trust the MyApp certificate")
        #expect(step.resolvedActionTitle() == "Trust Certificate")
        #expect(step.requirement == .optional)
    }

    @Test func customStepUsesItsOwnText() {
        let step = everyStep.last!
        #expect(step.resolvedHeading(appName: "MyApp") == "Create the library")
        #expect(step.resolvedMessage(appName: "MyApp") == "It holds your data.")
        #expect(step.resolvedActionTitle() == "Create")
        #expect(step.resolvedSymbolName() == "gearshape")
    }

    @Test func everyStepHasText() {
        for step in everyStep {
            #expect(!step.title.isEmpty, "\(step.id)")
            #expect(!step.resolvedHeading(appName: "MyApp").isEmpty, "\(step.id)")
            #expect(!step.resolvedMessage(appName: "MyApp").isEmpty, "\(step.id)")
            #expect(!step.resolvedActionTitle().isEmpty, "\(step.id)")
            #expect(NSImage(systemSymbolName: step.resolvedSymbolName(), accessibilityDescription: nil) != nil, "\(step.id)")
        }
    }

    @Test func textPassedToAStepReplacesTheDefault() {
        let steps: [InstallerStep] = [
            .permission(.fullDiskAccess, heading: "H", message: "M", actionTitle: "A"),
            .permission(.systemExtension(vpn), heading: "H", message: "M", actionTitle: "A"),
            .networkConfiguration(.init(.appProxy, providerBundleIdentifier: "p"), heading: "H", message: "M", actionTitle: "A"),
            .certificate(.init(resourceName: "RootCA"), heading: "H", message: "M", actionTitle: "A"),
        ]
        for step in steps {
            #expect(step.resolvedHeading(appName: "MyApp") == "H", "\(step.id)")
            #expect(step.resolvedMessage(appName: "MyApp") == "M", "\(step.id)")
            #expect(step.resolvedActionTitle() == "A", "\(step.id)")
        }
        // Only what's passed is replaced.
        let partial = InstallerStep.permission(.accessibility, message: "M")
        #expect(partial.resolvedHeading(appName: "MyApp") == "Allow Accessibility")
        #expect(partial.resolvedMessage(appName: "MyApp") == "M")
    }
}

@Suite @MainActor struct PaneLayoutTests {
    /// Installer's content area.
    private static let size = NSSize(width: 418, height: 329)

    private func laidOut(_ view: NSView) -> NSView {
        view.frame = NSRect(origin: .zero, size: Self.size)
        view.layoutSubtreeIfNeeded()
        return view
    }

    /// Installer grows a pane's view to the height its content asks for and shows the
    /// bottom of it, so a pane that asks for more than the content area loses its top.
    private func expectFits(_ pane: NSView, _ comment: Comment) {
        #expect(pane.fittingSize.height <= Self.size.height, "\(comment)")
        expectInside(laidOut(pane), comment)
    }

    /// Every view the pane shows, leaving out what a scroll view holds: that's meant to
    /// run past the edge.
    private func visibleViews(in view: NSView) -> [NSView] {
        view.subviews.flatMap { sub in [sub] + (sub is NSScrollView ? [] : visibleViews(in: sub)) }
    }

    private func expectInside(_ pane: NSView, _ comment: Comment) {
        for view in visibleViews(in: pane) where !view.isHidden {
            let frame = view.convert(view.bounds, to: pane)
            #expect(pane.bounds.insetBy(dx: -0.5, dy: -0.5).contains(frame), "\(comment): \(type(of: view)) at \(frame)")
        }
    }

    private func intro(steps count: Int) -> (session: SetupSession, pane: IntroPane) {
        let steps = (0..<count).map { i in
            InstallerStep.custom(id: "\(i)", title: "Step \(i)", heading: "H", message: "M", actionTitle: "A",
                                 .optional, check: { nil }, perform: {})
        }
        let session = SetupSession(setup: InstallerSetup(appName: "MyApp", steps: steps))
        return (session, IntroPane(session: session))
    }

    /// With nine steps the list used to push the app icon off the top of the pane.
    @Test(arguments: [1, 6, 7, 9, 12, 30])
    func introStaysInsideThePane(steps count: Int) {
        let (session, pane) = intro(steps: count)
        withExtendedLifetime(session) { expectFits(pane.view, "\(count) steps") }
    }

    /// Nine steps is what the demo installer has. Up to there the whole list shows.
    @Test(arguments: [1, 6, 7, 9])
    func introShowsEveryStepWithoutScrolling(steps count: Int) throws {
        let (session, pane) = intro(steps: count)
        try withExtendedLifetime(session) {
            let scroll = try #require(visibleViews(in: laidOut(pane.view)).compactMap { $0 as? NSScrollView }.first)
            let list = try #require(scroll.documentView)
            #expect(scroll.frame.height >= list.frame.height - 0.5, "\(scroll.frame.height) of \(list.frame.height)")
        }
    }

    @Test func aLongIntroListScrollsFromTheTop() throws {
        let (session, pane) = intro(steps: 30)
        try withExtendedLifetime(session) {
            let scroll = try #require(visibleViews(in: laidOut(pane.view)).compactMap { $0 as? NSScrollView }.first)
            let list = try #require(scroll.documentView)
            #expect(scroll.frame.height < list.frame.height)
            #expect(scroll.frame.height > 100, "still room for several rows")
            #expect(scroll.contentView.isFlipped && scroll.contentView.bounds.minY == 0)
        }
    }

    @Test func stepPanesStayInsideThePane() {
        // Panes don't keep their session alive.
        let session = SetupSession(setup: InstallerSetup(appName: "MyApp", steps: everyStep))
        for pane in session.steps {
            expectFits(pane.view, "\(pane.step.id)")
        }
    }
}

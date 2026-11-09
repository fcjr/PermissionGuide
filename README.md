# PermissionKit

Guided permission setup for macOS apps. PermissionKit opens the right System Settings
pane, dims everything but the list the user needs, and docks a panel beside the window
with your app's icon to drag in. For system extensions it points the user at the switch
to turn on. It notices the grant and brings your app back to the front.

Requires macOS 14.

## Supported permissions

| Permission | Pane | Status check |
| --- | --- | --- |
| `.fullDiskAccess` | Full Disk Access | ✓ (may need a relaunch) |
| `.screenRecording` | Screen & System Audio Recording | ✓ (may need a relaunch) |
| `.accessibility` | Accessibility | ✓ |
| `.inputMonitoring` | Input Monitoring | ✓ (may need a relaunch) |
| `.bluetooth` | Bluetooth | ✓ |
| `.developerTools` | Developer Tools | No API; user clicks Done |
| `.appManagement` | App Management | No API; user clicks Done |
| `.systemExtension(...)` | Login Items & Extensions | ✓ via `OSSystemExtensionRequest` |
| `.backgroundItem(daemonPlist:)` | Login Items & Extensions → Allow in the Background | ✓ via `SMAppService` |

System extensions cover VPN providers, content filters and DNS proxies
(`.networkExtension`), Endpoint Security clients (`.endpointSecurity`), DriverKit
drivers and camera extensions.

Prompt-only permissions (Camera, Microphone, Automation, Files & Folders, …) aren't
included: an app shows up in those lists only after it asks through the framework's
own API.

## Installation

Add the package in Xcode (File → Add Package Dependencies), or in `Package.swift`:

```swift
dependencies: [
    .package(path: "../PermissionKit"),  // or .package(url: "<repo URL>", from: "<version>")
],
targets: [
    .target(name: "MyApp", dependencies: ["PermissionKit"]),
]
```

### App requirements

- **A real, signed `.app` bundle.** macOS tracks permissions per signed app, and the
  user drags the bundle itself. A bare `swift run` executable won't work.
- **No App Sandbox.** PermissionKit is built for Developer ID apps. In a sandbox the Full
  Disk Access check looks inside the app's container and always fails, and system
  extensions can't be installed.
- **`NSBluetoothAlwaysUsageDescription`** in Info.plist if you use `.bluetooth`.
- **Your executable can be launched as a probe.** To see grants that only apply after a
  relaunch, PermissionKit runs `Bundle.main.executableURL` with `PERMISSIONKIT_PROBE`
  set. A C constructor in `PermissionKitProbe` answers through the exit status and exits
  before `main`, so none of your startup code runs. This works on its own when the app
  links PermissionKit, statically or not. Your own `__attribute__((constructor))` or
  `+load` code can still run first, so keep it free of side effects. If the probe's
  constructor didn't run in your process (it wasn't linked in), PermissionKit doesn't
  probe, so it never launches a second copy of your app.

## Usage

### 1. Create a manager

`PermissionManager` is `@Observable` and runs on the main actor. Create one, keep it
alive for as long as you need it, and list the permissions it should track:

```swift
import PermissionKit

@State private var permissions = PermissionManager(
    permissions: [.accessibility, .fullDiskAccess, .screenRecording]
)
```

With no arguments it tracks every privacy permission (`Permission.privacyPermissions`).
It re-checks status every 0.75 seconds (`pollInterval:`), so views that read it update
by themselves.

### 2. Check status

```swift
switch permissions.status(of: .fullDiskAccess) {
case .granted: …
case .notGranted: …
case .unknown: …   // macOS can't report it (Developer Tools, App Management)
}

permissions.statuses   // [Permission: PermissionStatus] for every tracked permission
permissions.pending    // the permission whose guide is showing, if any
```

Checking never shows a system prompt.

### 3. Request a permission

```swift
switch await permissions.request(.fullDiskAccess) {
case .granted: …
case .confirmed: …
case .cancelled: …
case .failed(let error): …
}
```

This opens the pane in System Settings, highlights the list, and shows a panel with your
app's icon for the user to drag in. It returns a `PermissionResult`:

- `.granted` once macOS reports the permission granted.
- `.confirmed` if the user clicks **Done** for a permission macOS can't check.
- `.cancelled` if the user clicks **Cancel**, you call `permissions.cancel()`, the calling
  `Task` is cancelled, or another `request` starts before this one finishes.
- `.failed(error)` if a system extension fails to activate.

`result.isGranted` is `true` for `.granted` and `.confirmed`. In every case the guide
closes and your app comes back to the front. If the permission is already granted,
`request` returns `.granted` right away without opening anything.

Options:

```swift
await permissions.request(
    .screenRecording,
    dragging: helperURL,                 // bundle to drag in; defaults to your app
    tint: .systemPurple,                 // highlight and panel color
    isGranted: { helper.canRecord }      // custom check, for when the default can't see it
)
```

When macOS asks for Touch ID or a password, or System Settings offers to quit and reopen
your app, the guide highlights that prompt and tells the user what to do. Set
`permissions.relaunchChoice = .later` if relaunching would interrupt something; the
default, `.quitAndReopen`, suggests restarting.

### Permissions that need a relaunch

Full Disk Access, Screen Recording and Input Monitoring
(`permission.mayNeedRelaunch`) can keep reading as `.notGranted` in the running app
after the user grants them. System Settings then offers **Quit & Reopen** or **Later**.
PermissionKit checks these from a fresh copy of your app (see
[App requirements](#app-requirements)), so:

- **Quit & Reopen:** macOS quits your app. The guide closes on the way out, and code
  after the pending `request` may not get to run before the process ends, so save any
  progress before you call it. After the relaunch the permission is simply `.granted`.
- **Later:** the guide finishes and `request` returns `.granted`. `status(of:)` reads
  `.granted` too, but your process can't use the permission yet, so
  `needsRelaunch(_:)` is `true` until the app restarts. Offer a restart:

```swift
if case .granted = await permissions.request(.fullDiskAccess),
   permissions.needsRelaunch(.fullDiskAccess) {
    showRestartButton()   // relaunch however your app does it
}
```

`relaunchPending` is the observable set of permissions waiting for a relaunch. The same
check also catches grants made in System Settings outside the guide: tracked permissions
are probed every 5 seconds, and `request` probes before it opens anything, so it returns
`.granted` right away for a grant the app can't see yet.

A new `PermissionResult` case was considered and left out: the permission *is* granted,
the existing `.granted` paths in callers stay correct, and restarting is an app-level
choice that `needsRelaunch(_:)` answers whenever the app asks, not only at the end of a
request.

### A SwiftUI permission screen

```swift
struct PermissionsView: View {
    let permissions: PermissionManager

    var body: some View {
        List(permissions.permissions) { permission in
            HStack {
                Text(permission.localizedName)
                Spacer()
                if permissions.status(of: permission) == .granted {
                    Label("Granted", systemImage: "checkmark.circle.fill")
                } else if permissions.pending == permission {
                    ProgressView().controlSize(.small)
                    Button("Cancel", action: permissions.cancel)
                } else {
                    Button("Grant…") {
                        Task { await permissions.request(permission) }
                    }
                }
            }
        }
    }
}
```

`Examples/PermissionKitDemo` is a fuller version of this screen.

### Helpers

When a helper process, not your app, needs the permission (for example, a server that
spawns shells), have the user drag the helper. Your app can't read another process's
permissions, so pass a check that can, such as asking the helper over IPC:

```swift
await permissions.request(
    .fullDiskAccess,
    dragging: Bundle.main.bundleURL.appending(path: "Contents/Helpers/MyHelper.app"),
    isGranted: { helper.reportsFullDiskAccess }
)
```

Without `isGranted`, the panel shows a Done button, because PermissionKit can't tell when
the helper has been granted.

### System extensions

Describe each extension your app embeds, and track it like any other permission:

```swift
let vpn = SystemExtension(
    identifier: "com.example.app.tunnel",   // the extension's bundle identifier
    category: .networkExtension,
    displayName: "Example VPN"              // the name next to its switch in System Settings
)
let permissions = PermissionManager(permissions: [.fullDiskAccess, .systemExtension(vpn)])
```

Categories: `.networkExtension` (VPN providers, content filters, DNS proxies),
`.endpointSecurity`, `.driverExtension` and `.cameraExtension`.

#### Before you request

macOS refuses to activate an extension unless the app is set up for it. Check with
`setupIssues()` first, and show or log what's wrong:

```swift
let issues = vpn.setupIssues()   // [] when ready
for issue in issues { print(issue) }
```

It catches the common mistakes:

- The app isn't in `/Applications`.
- The app lacks `com.apple.developer.system-extension.install`.
- No `.systemextension` with the identifier in `Contents/Library/SystemExtensions`.
- The extension lacks its category's entitlement
  (`com.apple.developer.networking.networkextension`,
  `com.apple.developer.endpoint-security.client` or `com.apple.developer.driverkit`).

An empty list doesn't guarantee activation. macOS also requires a Developer ID
signature, notarization and a provisioning profile that grants those entitlements.
Endpoint Security entitlements need Apple's approval. During development,
`systemextensionsctl developer on` (with SIP disabled) relaxes the location and
notarization checks.

#### Installing and approving

```swift
if vpn.setupIssues().isEmpty {
    let result = await permissions.request(.systemExtension(vpn))
}
```

`request` submits `OSSystemExtensionRequest.activationRequest`, which installs the
extension: macOS copies it out of your app bundle and asks the user to approve it.
PermissionKit then opens the extension pane and guides the user to the switch. It
returns `.granted` once the extension is active, `.failed(error)` if activation fails, and
`.cancelled` if the user cancels.

If your app already submits its own `OSSystemExtensionRequest`, call `guide(to:)` from
`requestNeedsUserApproval` instead. It shows the walkthrough without installing anything:

```swift
func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
    Task { await permissions.guide(to: .systemExtension(vpn)) }
}
```

`guide(to:)` works for privacy panes too. For those it does the same thing as `request`.

A VPN also has to save its configuration (`NETunnelProviderManager.saveToPreferences`),
which shows a separate "Add VPN Configurations" alert that PermissionKit doesn't guide.
Endpoint Security clients usually also need `.fullDiskAccess`, granted to the extension:
pass the extension's URL (`vpn.embeddedURL()`) as `dragging:` along with an `isGranted:`
check.

### Background items

A launch daemon registered with `SMAppService` (a privileged helper, say) only runs once
the user switches it on under Login Items & Extensions → Allow in the Background. Pass the
plist's name in `Contents/Library/LaunchDaemons`:

```swift
let helper = Permission.backgroundItem(daemonPlist: "com.example.app.helper.plist")
if await permissions.request(helper).isGranted {
    // SMAppService.daemon(plistName:).status == .enabled
}
```

`request` registers the daemon if it isn't yet, then shows the guide until macOS reports
it enabled. The guide doesn't highlight the switch: the list's position depends on how
many items sit above it. The app has to be signed (Developer ID) for macOS to register it.

### API at a glance

| API | Purpose |
| --- | --- |
| `PermissionManager(permissions:pollInterval:)` | Tracks status for the listed permissions |
| `status(of:)`, `statuses` | Current status: `.granted`, `.notGranted` or `.unknown` |
| `pending` | The permission whose guide is showing |
| `needsRelaunch(_:)`, `relaunchPending` | Granted, but the app must relaunch to use it |
| `request(_:dragging:tint:isGranted:)` | Guides the user; installs system extensions and registers background items first |
| `guide(to:dragging:tint:isGranted:)` | Guides the user without requesting anything |
| `cancel()` | Closes the guide; the pending call returns `.cancelled` |
| `refresh()` | Re-checks status now |
| `Permission.localizedName`, `.settingsURL` | Pane name and deep link |
| `Permission.mayNeedRelaunch` | Whether a grant can wait for a relaunch |
| `SystemExtension.setupIssues(in:)` | What's stopping activation |
| `SystemExtension.embeddedURL(in:)` | The embedded `.systemextension` bundle |

## How it works

- **Window tracking:** `CGWindowListCopyWindowInfo` gives System Settings' window frame
  without any permission. A timer in common run loop modes keeps the panels attached
  while the window moves, including during a drag.
- **Highlight:** With Accessibility permission, PermissionKit reads the list's exact frame.
  Without it, the highlight is placed from System Settings' layout (measured on macOS 27)
  and covers the first two rows. Extension switches are found from the sheet's frame.
  Once the grant has gone through (the user clicked Later on "Quit & Reopen"), and
  briefly after authenticating, nothing is highlighted: those rows aren't your app's.
- **Prompts:** Touch ID, password and "Quit & Reopen" windows are found in the window
  list and told apart by the order they appear in and their size. While "Quit & Reopen"
  is up, the guide waits for the user's answer even if the grant is already visible.
- **Probe:** For permissions that may need a relaunch, a fresh copy of the app reports
  what it has through its exit status (`PermissionKitProbe`), at most every 1.5 seconds
  during a request and every 5 seconds otherwise, only while one is missing.
- **Drag:** The icon's pasteboard item is the app's file URL. Dropping it into a privacy
  list adds the app, the same as picking it with "+".
- **Sheets:** System Settings ignores deep links while a sheet is open, and it can't be
  closed without Accessibility. When one is open, PermissionKit quits System Settings
  and reopens it on the right pane. While guiding a drag, the highlight hides whenever a
  sheet (such as the "+" file picker) covers the list.
- **Placement:** The panel docks to the right of the window, or to the left, or over the
  sidebar on screens too small for either. It works across displays and re-lays out when
  displays change.

## Installer panes

`PermissionInstaller` adds a Set Up section to your `.pkg`, after Install. It shows one
pane per step, and each step is either required (Continue stays disabled until it's
done) or optional (the user can skip it). Panes skip ahead when a step is already done,
and the last pane lists anything skipped and opens your app.

Steps can be any System Settings permission above, a VPN or proxy configuration, a
trusted root certificate, or your own step.

### 1. Define the setup

Put this in a target that both your app and your installer plugin depend on:

```swift
import PermissionInstaller

extension InstallerSetup {
    static let myApp = InstallerSetup(
        appName: "MyApp",
        steps: [
            .permission(.fullDiskAccess),
            .permission(.systemExtension(vpn)),
            .networkConfiguration(.init(.packetTunnel, providerBundleIdentifier: "com.example.myapp.tunnel")),
            .certificate(.init(resourceName: "RootCA"), .optional),
            .permission(.screenRecording, .optional),
            .custom(
                id: "login-item",
                title: "Open at Login",
                heading: "Open MyApp at login",
                message: "MyApp runs in the background so it's always protecting you.",
                actionTitle: "Open at Login",
                .optional,
                check: { SMAppService.mainApp.status == .enabled },
                perform: { try SMAppService.mainApp.register() }
            ),
        ],
        tint: .systemIndigo
    )
}
```

Steps are required unless you pass `.optional`. Each step's `heading`, `message` and
`actionTitle` have defaults you can override.

### 2. Handle the installer in your app

The installer does each step by launching your installed app in the background, so
permissions, system extensions and network configurations belong to your app, not to
Installer. Call this before any UI:

```swift
@main
struct MyApp: App {
    init() {
        InstallerSetup.myApp.handleInstallerLaunch()
    }
    // ...
}
```

It returns right away on a normal launch. When the installer launched the app, it checks
or performs the step (showing PermissionKit's guide, without a Dock icon) and exits.

### 3. Build the plugin

Make a dynamic library target that depends on `PermissionInstallerPlugin`:

```swift
import Foundation
import PermissionInstaller
import PermissionInstallerPlugin

@objc(MyAppInstallerPlugin)
final class MyAppInstallerPlugin: InstallerPlugin {
    override var setup: InstallerSetup { .myApp }
}
```

Wrap it in a bundle (`SetupPane.bundle/Contents/MacOS/<executable>`) whose Info.plist has:

| Key | Value |
| --- | --- |
| `NSPrincipalClass` | `PKInstallerSection` |
| `PermissionInstallerProvider` | Your subclass's `@objc` name |
| `InstallerSectionTitle` | Sidebar title, such as `Set Up` |

Then list the bundle after `Install` in `InstallerSections.plist` and pass the folder to
`productbuild --plugins`. The `build-pkg` recipe in the [`justfile`](justfile)
does all of this.

Installer warns that the package "will run a program to determine if the software can be
installed" whenever it has a plugin. Sign the plugin, app and package with your
Developer ID for release.

## Examples

The examples build with [just](https://github.com/casey/just). Run `just` to list recipes.

```sh
just demo       # build and open PermissionKitDemo.app
just demo-pkg   # build and open InstallerDemo.pkg
```

The demos are ad-hoc signed, so macOS treats each rebuild as a new app. Reset stale grants
with `just reset`. Remove an installed InstallerDemo with `just uninstall-pkg`, and all
build output with `just clean`.

The installer demo has a required Full Disk Access step, a required custom step, and
optional steps for every other kind. Its VPN, Endpoint Security and VPN configuration
steps fail on purpose: the demo has no real extension or Network Extension entitlement.

## License

MIT. See [LICENSE](LICENSE).

import PermissionKit
import SwiftUI

@main
struct PermissionKitDemoApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var permissions = PermissionManager(
        permissions: Permission.privacyPermissions + [.vpn, .endpointSecurity]
    )

    var body: some Scene {
        Window("Permissions", id: "main") {
            ContentView(permissions: permissions)
        }
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct ContentView: View {
    let permissions: PermissionManager
    /// Permissions macOS can't report, which the user confirmed with Done.
    @State private var confirmed: Set<Permission> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
                    .resizable()
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Grant System Permissions").font(.title2.bold())
                    Text("Click Grant, then drag the icon into the list System Settings shows you.")
                        .foregroundStyle(.secondary)
                }
            }

            VStack(spacing: 8) {
                ForEach(permissions.permissions) { permission in
                    PermissionRow(
                        permission: permission,
                        status: permissions.status(of: permission),
                        confirmed: confirmed.contains(permission),
                        waiting: permissions.pending == permission,
                        grant: {
                            // This demo doesn't embed real system extensions, so it can't
                            // activate them. guide(to:) shows the same walkthrough that
                            // request(_:) shows once macOS asks for approval.
                            let result = if case .systemExtension = permission {
                                await permissions.guide(to: permission, tint: permission.color)
                            } else {
                                await permissions.request(permission, tint: permission.color)
                            }
                            if case .confirmed = result {
                                confirmed.insert(permission)
                            }
                        },
                        cancel: permissions.cancel
                    )
                }
            }
        }
        .padding(24)
        .frame(width: 540)
        .animation(.spring(duration: 0.35), value: permissions.statuses)
        .animation(.spring(duration: 0.35), value: permissions.pending)
    }
}

struct PermissionRow: View {
    let permission: Permission
    let status: PermissionStatus
    let confirmed: Bool
    let waiting: Bool
    let grant: () async -> Void
    let cancel: () -> Void

    private var tint: Color { Color(nsColor: permission.color) }
    private var isGranted: Bool { status == .granted || confirmed }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: permission.symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(permission.title).font(.headline)
                Text(permission.summary).font(.callout).foregroundStyle(.secondary)
                if case .systemExtension(let ext) = permission {
                    // Real apps check this before calling request(_:), which activates
                    // (installs) the extension. This demo embeds none, so all fail.
                    ForEach(ext.setupIssues(), id: \.self) { issue in
                        Label(issue.description, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Spacer(minLength: 8)

            if isGranted {
                Label(status == .granted ? "Granted" : "Confirmed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout.weight(.medium))
                    .transition(.scale.combined(with: .opacity))
            } else if waiting {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Button("Cancel", action: cancel)
                }
            } else {
                Button("Grant…") { Task { await grant() } }
                    .buttonStyle(.borderedProminent)
                    .tint(tint)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isGranted ? Color.green.opacity(0.08) : waiting ? tint.opacity(0.12) : Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(waiting ? tint : .clear, lineWidth: 1.5)
        )
    }
}

extension Permission {
    // Placeholder identifiers: a real app embeds these in Contents/Library/SystemExtensions.
    static let vpn = Permission.systemExtension(SystemExtension(
        identifier: "com.example.permissionkitdemo.tunnel",
        category: .networkExtension,
        displayName: "PermissionKit Demo"
    ))
    static let endpointSecurity = Permission.systemExtension(SystemExtension(
        identifier: "com.example.permissionkitdemo.security",
        category: .endpointSecurity,
        displayName: "PermissionKit Demo"
    ))

    var title: String {
        guard case .systemExtension(let ext) = self else { return localizedName }
        return switch ext.category {
        case .networkExtension: "VPN"
        case .endpointSecurity: "Endpoint Security"
        case .driverExtension: "Driver"
        case .cameraExtension: "Camera Extension"
        }
    }

    var summary: String {
        switch self {
        case .fullDiskAccess: "Read files in protected folders like Mail and Safari."
        case .screenRecording: "Capture the screen, windows and system audio."
        case .accessibility: "Observe and control other apps."
        case .inputMonitoring: "Read keyboard and mouse input from any app."
        case .developerTools: "Run software that doesn't meet security policy."
        case .appManagement: "Update or delete other apps."
        case .bluetooth: "Connect to Bluetooth devices."
        case .systemExtension(let ext):
            switch ext.category {
            case .networkExtension: "Route traffic through a VPN tunnel."
            case .endpointSecurity: "Monitor processes and files for threats."
            case .driverExtension: "Talk to connected hardware."
            case .cameraExtension: "Provide a virtual camera."
            }
        }
    }

    var symbol: String {
        switch self {
        case .fullDiskAccess: "externaldrive.fill"
        case .screenRecording: "rectangle.dashed.badge.record"
        case .accessibility: "accessibility"
        case .inputMonitoring: "keyboard.fill"
        case .developerTools: "hammer.fill"
        case .appManagement: "square.stack.3d.up.fill"
        case .bluetooth: "dot.radiowaves.left.and.right"
        case .systemExtension(let ext):
            switch ext.category {
            case .networkExtension: "network.badge.shield.half.filled"
            case .endpointSecurity: "checkmark.shield.fill"
            case .driverExtension: "cable.connector"
            case .cameraExtension: "web.camera.fill"
            }
        }
    }

    var color: NSColor {
        switch self {
        case .fullDiskAccess: .systemBlue
        case .screenRecording: .systemPurple
        case .accessibility: .systemOrange
        case .inputMonitoring: .systemPink
        case .developerTools: .systemBrown
        case .appManagement: .systemTeal
        case .bluetooth: .systemIndigo
        case .systemExtension(let ext):
            ext.category == .networkExtension ? .systemGreen : .systemRed
        }
    }
}

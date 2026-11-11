import Foundation
import PermissionGuideProbe

/// Asks a fresh copy of the app which permissions it has.
///
/// Some grants only reach a process when it starts, so the running app can keep reading
/// them as denied (see `Permission.mayNeedRelaunch`). The probe relaunches the app's
/// executable with `PERMISSIONGUIDE_PROBE_ENV` set. A C constructor in PermissionGuideProbe answers
/// through the exit status before `main`, so none of the app's own startup code runs.
enum Probe {
    /// The name PermissionGuideProbe.c checks a permission by, for permissions it can check.
    static func name(for permission: Permission) -> String? {
        switch permission {
        case .fullDiskAccess: "fullDiskAccess"
        case .screenRecording: "screenRecording"
        case .inputMonitoring: "inputMonitoring"
        default: nil
        }
    }

    /// Whether launching this executable runs the probe. When the constructor didn't run
    /// here (the probe object wasn't linked in), a launch would start a second copy of the
    /// app instead, so PermissionGuide doesn't probe at all.
    static var isAvailable: Bool { permissionguide_probe_linked() }

    /// The permissions one probe asks about: those it can check, at most `PERMISSIONGUIDE_PROBE_CAPACITY`.
    static func asked(_ permissions: [Permission]) -> [Permission] {
        var seen = Set<Permission>()
        return Array(permissions.filter { name(for: $0) != nil && seen.insert($0).inserted }.prefix(Int(PERMISSIONGUIDE_PROBE_CAPACITY)))
    }

    static func environmentValue(for asked: [Permission]) -> String {
        asked.compactMap(name(for:)).joined(separator: ",")
    }

    /// The granted permissions in a probe's exit status, or `nil` when it isn't an answer.
    static func grants(fromExitStatus status: Int32, asked: [Permission]) -> Set<Permission>? {
        let bits = (Int32(1) << PERMISSIONGUIDE_PROBE_CAPACITY) - 1
        guard status & ~bits == PERMISSIONGUIDE_PROBE_ANSWERED else { return nil }
        return Set(asked.enumerated().filter { status & (1 << $0.offset) != 0 }.map(\.element))
    }

    /// Launches `executable` as a probe. `nil` when it couldn't answer. The probe disclaims
    /// this process as responsible for it, so TCC checks the app's grants as a fresh launch
    /// would instead of reusing what it decided for this one (seen with Full Disk Access).
    static func run(_ permissions: [Permission], executable: URL, timeout: TimeInterval = 10) async -> Set<Permission>? {
        let asked = asked(permissions)
        guard !asked.isEmpty, isAvailable else { return nil }
        let value = environmentValue(for: asked)
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let status = permissionguide_probe_spawn(executable.path, value, timeout)
                continuation.resume(returning: status < 0 ? nil : grants(fromExitStatus: status, asked: asked))
            }
        }
    }
}

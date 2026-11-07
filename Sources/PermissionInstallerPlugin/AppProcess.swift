import Foundation
import PermissionInstaller

/// The installed app, run in the background to check or perform one step.
final class AppProcess: @unchecked Sendable {
    struct Result: Sendable {
        var status: InstallerProtocol.Exit
        var message: String
    }

    private typealias Disclaim = @convention(c) (UnsafeMutablePointer<posix_spawnattr_t?>, Int32) -> Int32

    private let lock = NSLock()
    private var pid: pid_t = 0

    /// Runs `executable` and waits for it to exit.
    func run(_ executable: URL, _ arguments: [String]) async -> Result {
        await Task.detached { self.spawnAndWait(executable, arguments) }.value
    }

    /// Stops the app, which then reports `.notDone`.
    func terminate() {
        lock.withLock { if pid > 0 { kill(pid, SIGTERM) } }
    }

    private func spawnAndWait(_ executable: URL, _ arguments: [String]) -> Result {
        let err = Pipe()

        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        // A child normally counts Installer as its "responsible" process, so macOS would
        // check Installer's permissions instead of the app's. Disclaiming makes the app
        // responsible for itself. The call is private, so it's looked up at runtime.
        if let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_spawnattrs_setdisclaim") {
            _ = unsafeBitCast(symbol, to: Disclaim.self)(&attr, 1)
        }

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_adddup2(&actions, err.fileHandleForWriting.fileDescriptor, 2)

        let argv: [UnsafeMutablePointer<CChar>?] = ([executable.path] + arguments).map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }

        var child: pid_t = 0
        let spawned = posix_spawn(&child, executable.path, &actions, &attr, argv, environ)
        try? err.fileHandleForWriting.close()
        guard spawned == 0 else {
            return Result(status: .failed, message: String(cString: strerror(spawned)))
        }
        lock.withLock { pid = child }

        let message = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        var status: Int32 = 0
        while waitpid(child, &status, 0) == -1 && errno == EINTR {}
        lock.withLock { pid = 0 }

        let exited = status & 0x7f == 0
        let code = InstallerProtocol.Exit(rawValue: (status >> 8) & 0xff)
        return Result(
            status: exited ? code ?? .failed : .notDone,
            message: message.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

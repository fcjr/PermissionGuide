#include <stdbool.h>

/// Environment variable that turns a launch of the app into a permission check. Its value
/// is a comma-separated list of permission names (`fullDiskAccess`, `screenRecording`,
/// `inputMonitoring`).
#define PERMISSIONGUIDE_PROBE_ENV "PERMISSIONGUIDE_PROBE"

/// A probe's exit status is this flag plus one bit per permission it found granted, in
/// the order they were listed. Any other status means the probe didn't run.
#define PERMISSIONGUIDE_PROBE_ANSWERED 0x40

/// Most permissions one probe can answer for.
#define PERMISSIONGUIDE_PROBE_CAPACITY 5

/// Whether the probe's constructor ran in this process, which means a fresh launch of the
/// app answers instead of starting up. Referenced from Swift so the linker keeps the probe.
bool permissionguide_probe_linked(void);

/// Whether this process has Full Disk Access, checked by opening files only it can open.
/// Never prompts and is safe on any thread. May keep reading false until the app relaunches.
bool permissionguide_full_disk_access(void);

/// Launches `executable` as a probe with `PERMISSIONGUIDE_PROBE_ENV` set to `value`, as its
/// own responsible process so TCC checks the app's grants as a fresh launch would. Blocks
/// until it exits; kills it after `timeout` seconds. The exit status, or -1 when it didn't
/// exit normally.
int permissionguide_probe_spawn(const char *executable, const char *value, double timeout);

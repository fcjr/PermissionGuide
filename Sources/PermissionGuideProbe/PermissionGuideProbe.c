#include "PermissionGuideProbe.h"
#include <CoreGraphics/CoreGraphics.h>
#include <IOKit/hidsystem/IOHIDLib.h>
#include <fcntl.h>
#include <limits.h>
#include <pwd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static bool pk_probe_ran = false;

bool permissionguide_probe_linked(void) { return pk_probe_ran; }

// Files that exist on every Mac and can only be opened with Full Disk Access. The
// per-user TCC.db is missing on some Macs (some macOS 27 installs), so the system one is
// checked too.
bool permissionguide_full_disk_access(void) {
    const struct passwd *user = getpwuid(getuid());
    const char *home = user != NULL ? user->pw_dir : getenv("HOME");
    char path[PATH_MAX];
    const char *paths[2] = {"/Library/Application Support/com.apple.TCC/TCC.db", NULL};
    if (home != NULL) {
        snprintf(path, sizeof path, "%s/Library/Application Support/com.apple.TCC/TCC.db", home);
        paths[1] = path;
    }
    for (int i = 0; i < 2; i++) {
        if (paths[i] == NULL) continue;
        int fd = open(paths[i], O_RDONLY);
        if (fd >= 0) {
            close(fd);
            return true;
        }
    }
    return false;
}

static bool pk_granted(const char *name) {
    if (strcmp(name, "fullDiskAccess") == 0) return permissionguide_full_disk_access();
    if (strcmp(name, "screenRecording") == 0) return CGPreflightScreenCaptureAccess();
    if (strcmp(name, "inputMonitoring") == 0) {
        return IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted;
    }
    return false;
}

// Runs before main. A running app can keep seeing some grants (Full Disk Access, Screen
// Recording) as denied until it relaunches, so PermissionManager launches a fresh copy of
// the app with PERMISSIONGUIDE_PROBE_ENV set to ask. The copy answers through its exit status and
// never reaches main, so none of the app's own startup code runs.
__attribute__((constructor))
static void pk_probe(void) {
    pk_probe_ran = true;
    const char *probe = getenv(PERMISSIONGUIDE_PROBE_ENV);
    if (probe == NULL) return;

    char list[256];
    strlcpy(list, probe, sizeof list);
    int answer = PERMISSIONGUIDE_PROBE_ANSWERED;
    char *rest = list, *name;
    for (int bit = 0; bit < PERMISSIONGUIDE_PROBE_CAPACITY && (name = strsep(&rest, ",")) != NULL; bit++) {
        if (pk_granted(name)) answer |= 1 << bit;
    }
    // _exit skips atexit handlers that other libraries' initializers may have registered.
    _exit(answer);
}

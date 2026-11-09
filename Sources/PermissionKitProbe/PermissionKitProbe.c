#include "PermissionKitProbe.h"
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

bool pk_probe_linked(void) { return pk_probe_ran; }

// Same check as Permission.currentStatus: TCC.db exists on every Mac and can only be
// opened with Full Disk Access.
static bool pk_full_disk_access(void) {
    const struct passwd *user = getpwuid(getuid());
    const char *home = user != NULL ? user->pw_dir : getenv("HOME");
    if (home == NULL) return false;
    char path[PATH_MAX];
    snprintf(path, sizeof path, "%s/Library/Application Support/com.apple.TCC/TCC.db", home);
    int fd = open(path, O_RDONLY);
    if (fd < 0) return false;
    close(fd);
    return true;
}

static bool pk_granted(const char *name) {
    if (strcmp(name, "fullDiskAccess") == 0) return pk_full_disk_access();
    if (strcmp(name, "screenRecording") == 0) return CGPreflightScreenCaptureAccess();
    if (strcmp(name, "inputMonitoring") == 0) {
        return IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted;
    }
    return false;
}

// Runs before main. A running app can keep seeing some grants (Full Disk Access, Screen
// Recording) as denied until it relaunches, so PermissionManager launches a fresh copy of
// the app with PK_PROBE_ENV set to ask. The copy answers through its exit status and
// never reaches main, so none of the app's own startup code runs.
__attribute__((constructor))
static void pk_probe(void) {
    pk_probe_ran = true;
    const char *probe = getenv(PK_PROBE_ENV);
    if (probe == NULL) return;

    char list[256];
    strlcpy(list, probe, sizeof list);
    int answer = PK_PROBE_ANSWERED;
    char *rest = list, *name;
    for (int bit = 0; bit < PK_PROBE_CAPACITY && (name = strsep(&rest, ",")) != NULL; bit++) {
        if (pk_granted(name)) answer |= 1 << bit;
    }
    // _exit skips atexit handlers that other libraries' initializers may have registered.
    _exit(answer);
}

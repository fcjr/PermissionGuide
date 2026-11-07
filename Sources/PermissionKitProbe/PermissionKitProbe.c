#include "PermissionKitProbe.h"
#include <CoreGraphics/CoreGraphics.h>
#include <stdlib.h>
#include <string.h>

bool pk_probe_linked(void) { return true; }

// Runs before main. A running app keeps seeing Screen Recording as denied until it
// relaunches, so PermissionManager launches a fresh copy of the app with PK_PROBE_ENV
// set to ask. The copy answers through its exit status and never reaches main.
__attribute__((constructor))
static void pk_probe(void) {
    const char *probe = getenv(PK_PROBE_ENV);
    if (probe == NULL) return;
    if (strcmp(probe, "screenRecording") == 0) {
        exit(CGPreflightScreenCaptureAccess() ? 0 : 2);
    }
    exit(3);
}

#include <stdbool.h>

/// Environment variable that turns a launch of the app into a permission check.
#define PK_PROBE_ENV "PERMISSIONKIT_PROBE"

/// Always true. Referenced from Swift so the linker keeps the probe in the app.
bool pk_probe_linked(void);

#include "PermissionGuideProbe.h"
#include <CoreGraphics/CoreGraphics.h>
#include <errno.h>
#include <signal.h>
#include <spawn.h>
#include <sys/wait.h>
#include <time.h>
#include <IOKit/hidsystem/IOHIDLib.h>
#include <fcntl.h>
#include <limits.h>
#include <pwd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

extern char **environ;

// libSystem SPI (Chromium and LLDB use it): the child becomes its own responsible
// process, so TCC checks the app's grants afresh instead of inheriting the parent's.
int responsibility_spawnattrs_setdisclaim(posix_spawnattr_t *attrs, int disclaim) __attribute__((weak_import));

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

int permissionguide_probe_spawn(const char *executable, const char *value, double timeout) {
    size_t prefix = strlen(PERMISSIONGUIDE_PROBE_ENV) + 1;
    size_t count = 0;
    while (environ[count] != NULL) count++;
    char **env = calloc(count + 2, sizeof *env);
    char *entry = malloc(prefix + strlen(value) + 1);
    if (env == NULL || entry == NULL) {
        free(env);
        free(entry);
        return -1;
    }
    sprintf(entry, "%s=%s", PERMISSIONGUIDE_PROBE_ENV, value);
    size_t n = 0;
    for (size_t i = 0; i < count; i++) {
        if (strncmp(environ[i], PERMISSIONGUIDE_PROBE_ENV "=", prefix) != 0) env[n++] = environ[i];
    }
    env[n++] = entry;
    env[n] = NULL;

    posix_spawnattr_t attrs;
    posix_spawn_file_actions_t files;
    posix_spawnattr_init(&attrs);
    posix_spawn_file_actions_init(&files);
    if (responsibility_spawnattrs_setdisclaim != NULL) responsibility_spawnattrs_setdisclaim(&attrs, 1);
    for (int fd = 0; fd <= 2; fd++) {
        posix_spawn_file_actions_addopen(&files, fd, "/dev/null", fd == 0 ? O_RDONLY : O_WRONLY, 0);
    }
    char *argv[] = {(char *)executable, NULL};
    pid_t pid;
    int spawned = posix_spawn(&pid, executable, &files, &attrs, argv, env);
    posix_spawn_file_actions_destroy(&files);
    posix_spawnattr_destroy(&attrs);
    free(entry);
    free(env);
    if (spawned != 0) return -1;

    // The probe answers in well under a second. Something that runs this long is the
    // app starting up instead, so stop it.
    struct timespec tick = {0, 10 * 1000 * 1000};
    int status = 0;
    for (double waited = 0;; waited += 0.01) {
        pid_t done = waitpid(pid, &status, WNOHANG);
        if (done == pid) break;
        if (done < 0 && errno != EINTR) return -1;
        if (waited >= timeout) {
            kill(pid, SIGKILL);
            waitpid(pid, &status, 0);
            return -1;
        }
        nanosleep(&tick, NULL);
    }
    return WIFEXITED(status) ? WEXITSTATUS(status) : -1;
}

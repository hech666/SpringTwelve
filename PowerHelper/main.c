#define _DARWIN_C_SOURCE 1

#include <dlfcn.h>
#include <errno.h>
#include <grp.h>
#include <signal.h>
#include <stdint.h>
#include <string.h>
#include <sys/types.h>
#include <unistd.h>
#include "HaogeSpringTwelveServiceRestart.h"

/* Darwin libSystem ABI; not declared by this project's public SDK headers. */
extern int proc_pidpath(int pid, void *buffer, uint32_t buffersize);

typedef int (*HaogeSpringTwelveReboot3Function)(uint64_t flags, ...);

extern int proc_listpids(uint32_t type, uint32_t typeinfo, void *buffer, int buffersize);

static int haoge_springtwelve_parentMatches(pid_t expectedParent, const char *expectedPath) {
    /* Fixed libproc path buffer; reject truncation below. */
    char path[4096] = {0};

    if (expectedParent <= 1 || getppid() != expectedParent) {
        return 0;
    }
    int length = proc_pidpath((int)expectedParent, path, (uint32_t)sizeof(path));
    if (length <= 0 || (uint32_t)length > (uint32_t)sizeof(path) ||
        memchr(path, '\0', sizeof(path)) == NULL ||
        strcmp(path, expectedPath) != 0) {
        return 0;
    }
    return getppid() == expectedParent;
}

static int haoge_springtwelve_restartMotionX(pid_t parent, const char *parentPath) {
    // Fixed paths and signal only: no shell, executable search or caller input.
    static const char *const services[] = {"/usr/libexec/replayd", "/usr/libexec/backboardd"};
    pid_t pids[8192] = {0};
    int bytes = proc_listpids(1 /* PROC_ALL_PIDS */, 0, pids, (int)sizeof(pids));
    if (bytes <= 0 || bytes >= (int)sizeof(pids) || bytes % (int)sizeof(pid_t) != 0)
        return HaogeSpringTwelvePowerHelperMotionXError;
    int displayServiceMatched = 0;
    for (unsigned int service = 0; service < 2; service++) {
        for (int i = 0; i < bytes / (int)sizeof(pid_t); i++) {
            if (pids[i] <= 1) continue;
            // Unrelated processes (including zombies) need no executable-path lookup.
            extern int proc_name(int pid, void *buffer, uint32_t buffersize);
            char name[64] = {0};
            if (proc_name((int)pids[i], name, sizeof(name)) <= 0 ||
                strcmp(name, service == 0 ? "replayd" : "backboardd") != 0) continue;
            char path[4096] = {0};
            errno = 0;
            int length = proc_pidpath((int)pids[i], path, (uint32_t)sizeof(path));
            if (length <= 0) {
                if (errno == ESRCH || errno == ENOENT) continue;
                return HaogeSpringTwelvePowerHelperMotionXError;
            }
            if (length >= (int)sizeof(path) || memchr(path, '\0', sizeof(path)) == NULL)
                return HaogeSpringTwelvePowerHelperMotionXError;
            if (strcmp(path, services[service]) != 0) continue;
            if (!haoge_springtwelve_parentMatches(parent, parentPath))
                return HaogeSpringTwelvePowerHelperPermission;
            // Reduce the PID-reuse window; never signal a changed executable.
            memset(path, 0, sizeof(path));
            errno = 0;
            length = proc_pidpath((int)pids[i], path, (uint32_t)sizeof(path));
            if (length <= 0 && (errno == ESRCH || errno == ENOENT)) continue;
            if (length <= 0 || length >= (int)sizeof(path) ||
                memchr(path, '\0', sizeof(path)) == NULL)
                return HaogeSpringTwelvePowerHelperMotionXError;
            if (strcmp(path, services[service]) != 0) continue;
            if (kill(pids[i], SIGKILL) != 0 && errno != ESRCH)
                return HaogeSpringTwelvePowerHelperMotionXError;
            if (service == 1) displayServiceMatched = 1;
        }
    }
    // replayd can be launched on demand; backboardd should exist with Settings visible.
    return displayServiceMatched ? HaogeSpringTwelvePowerHelperSubmitted : HaogeSpringTwelvePowerHelperMotionXError;
}

int haoge_springtwelve_powerHelperMain(int argc, char *argv[]) {
    if (argc != 2 || argv == NULL || argv[1] == NULL)
        return HaogeSpringTwelvePowerHelperUsage;
    int restartMotionX = strcmp(argv[1], "restart-motionx-services") == 0;
    if (!restartMotionX && strcmp(argv[1], "userspace-reboot") != 0)
        return HaogeSpringTwelvePowerHelperUsage;
    const char *parentPath = restartMotionX ? "/Applications/Preferences.app/Preferences" :
        "/System/Library/CoreServices/SpringBoard.app/SpringBoard";
    if (getuid() != (uid_t)501 || geteuid() != (uid_t)0) {
        return HaogeSpringTwelvePowerHelperPermission;
    }

    const pid_t parent = getppid();
    if (!haoge_springtwelve_parentMatches(parent, parentPath)) {
        return HaogeSpringTwelvePowerHelperPermission;
    }

    if (setgroups(0, NULL) != 0 || setgid((gid_t)0) != 0 || setuid((uid_t)0) != 0) {
        return HaogeSpringTwelvePowerHelperElevation;
    }
    if (getuid() != (uid_t)0 || geteuid() != (uid_t)0 ||
        getgid() != (gid_t)0 || getegid() != (gid_t)0) {
        return HaogeSpringTwelvePowerHelperElevation;
    }
    if (!haoge_springtwelve_parentMatches(parent, parentPath)) {
        return HaogeSpringTwelvePowerHelperPermission;
    }

    if (restartMotionX) return haoge_springtwelve_restartMotionX(parent, parentPath);

    /* Resolve only the existing libSystem export; no dlopen or fallback. */
    void *symbol = dlsym(RTLD_DEFAULT, "reboot3");
    if (symbol == NULL) {
        return HaogeSpringTwelvePowerHelperUnavailable;
    }
    HaogeSpringTwelveReboot3Function rebootFunction =
        (HaogeSpringTwelveReboot3Function)symbol;

    /* Revalidate after symbol resolution, immediately before the one action. */
    if (!haoge_springtwelve_parentMatches(parent, parentPath)) {
        return HaogeSpringTwelvePowerHelperPermission;
    }
    const uint64_t flags = UINT64_C(0x2000000000000000);
    if (rebootFunction(flags) != 0) {
        return HaogeSpringTwelvePowerHelperRebootError;
    }
    return HaogeSpringTwelvePowerHelperSubmitted;
}

#ifndef HAOGE_SPRINGTWELVE_HELPER_TEST
int main(int argc, char *argv[]) {
    return haoge_springtwelve_powerHelperMain(argc, argv);
}
#endif

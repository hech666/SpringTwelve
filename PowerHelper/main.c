#define _DARWIN_C_SOURCE 1

#include <dlfcn.h>
#include <stdint.h>
#include <string.h>
#include <sys/types.h>
#include <unistd.h>

/* Darwin libSystem ABI; not declared by this project's public SDK headers. */
extern int proc_pidpath(int pid, void *buffer, uint32_t buffersize);

typedef int (*HaogeSpringTwelveReboot3Function)(uint64_t flags, ...);

enum HaogeSpringTwelvePowerHelperExitCode {
    HaogeSpringTwelvePowerHelperSubmitted = 0,
    HaogeSpringTwelvePowerHelperUsage = 64,
    HaogeSpringTwelvePowerHelperUnavailable = 69,
    HaogeSpringTwelvePowerHelperRebootError = 70,
    HaogeSpringTwelvePowerHelperPermission = 77,
    HaogeSpringTwelvePowerHelperElevation = 78
};

static int haoge_springtwelve_parentMatches(pid_t expectedParent) {
    static const char expectedPath[] =
        "/System/Library/CoreServices/SpringBoard.app/SpringBoard";
    /* Darwin PROC_PIDPATHINFO_MHAOGEIZE is 4096 bytes. */
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

int main(int argc, char *argv[]) {
    if (argc != 2 || argv == NULL || argv[1] == NULL ||
        strcmp(argv[1], "userspace-reboot") != 0) {
        return HaogeSpringTwelvePowerHelperUsage;
    }
    if (getuid() != (uid_t)501 || geteuid() != (uid_t)0) {
        return HaogeSpringTwelvePowerHelperPermission;
    }

    const pid_t parent = getppid();
    if (!haoge_springtwelve_parentMatches(parent)) {
        return HaogeSpringTwelvePowerHelperPermission;
    }

    if (setgroups(0, NULL) != 0) {
        return HaogeSpringTwelvePowerHelperElevation;
    }
    if (setgid((gid_t)0) != 0) {
        return HaogeSpringTwelvePowerHelperElevation;
    }
    if (setuid((uid_t)0) != 0) {
        return HaogeSpringTwelvePowerHelperElevation;
    }
    if (getuid() != (uid_t)0 || geteuid() != (uid_t)0 ||
        getgid() != (gid_t)0 || getegid() != (gid_t)0) {
        return HaogeSpringTwelvePowerHelperElevation;
    }
    if (!haoge_springtwelve_parentMatches(parent)) {
        return HaogeSpringTwelvePowerHelperPermission;
    }

    /* Resolve only the existing libSystem export; no dlopen or fallback. */
    void *symbol = dlsym(RTLD_DEFAULT, "reboot3");
    if (symbol == NULL) {
        return HaogeSpringTwelvePowerHelperUnavailable;
    }
    HaogeSpringTwelveReboot3Function rebootFunction =
        (HaogeSpringTwelveReboot3Function)symbol;

    /* Revalidate after symbol resolution, immediately before the one action. */
    if (!haoge_springtwelve_parentMatches(parent)) {
        return HaogeSpringTwelvePowerHelperPermission;
    }
    const uint64_t flags = UINT64_C(0x2000000000000000);
    if (rebootFunction(flags) != 0) {
        return HaogeSpringTwelvePowerHelperRebootError;
    }
    return HaogeSpringTwelvePowerHelperSubmitted;
}

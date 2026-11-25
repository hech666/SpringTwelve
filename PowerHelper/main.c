#define _DARWIN_C_SOURCE 1

#include <dlfcn.h>
#include <stdint.h>
#include <string.h>
#include <sys/types.h>
#include <unistd.h>

/* Darwin libSystem ABI; not declared by this project's public SDK headers. */
extern int proc_pidpath(int pid, void *buffer, uint32_t buffersize);

typedef int (*AxsSpringTwelveReboot3Function)(uint64_t flags, ...);

enum AxsSpringTwelvePowerHelperExitCode {
    AxsSpringTwelvePowerHelperSubmitted = 0,
    AxsSpringTwelvePowerHelperUsage = 64,
    AxsSpringTwelvePowerHelperUnavailable = 69,
    AxsSpringTwelvePowerHelperRebootError = 70,
    AxsSpringTwelvePowerHelperPermission = 77,
    AxsSpringTwelvePowerHelperElevation = 78
};

static int axs_springtwelve_parentMatches(pid_t expectedParent) {
    static const char expectedPath[] =
        "/System/Library/CoreServices/SpringBoard.app/SpringBoard";
    /* Darwin PROC_PIDPATHINFO_MAXSIZE is 4096 bytes. */
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
        return AxsSpringTwelvePowerHelperUsage;
    }
    if (getuid() != (uid_t)501 || geteuid() != (uid_t)0) {
        return AxsSpringTwelvePowerHelperPermission;
    }

    const pid_t parent = getppid();
    if (!axs_springtwelve_parentMatches(parent)) {
        return AxsSpringTwelvePowerHelperPermission;
    }

    if (setgroups(0, NULL) != 0) {
        return AxsSpringTwelvePowerHelperElevation;
    }
    if (setgid((gid_t)0) != 0) {
        return AxsSpringTwelvePowerHelperElevation;
    }
    if (setuid((uid_t)0) != 0) {
        return AxsSpringTwelvePowerHelperElevation;
    }
    if (getuid() != (uid_t)0 || geteuid() != (uid_t)0 ||
        getgid() != (gid_t)0 || getegid() != (gid_t)0) {
        return AxsSpringTwelvePowerHelperElevation;
    }
    if (!axs_springtwelve_parentMatches(parent)) {
        return AxsSpringTwelvePowerHelperPermission;
    }

    /* Resolve only the existing libSystem export; no dlopen or fallback. */
    void *symbol = dlsym(RTLD_DEFAULT, "reboot3");
    if (symbol == NULL) {
        return AxsSpringTwelvePowerHelperUnavailable;
    }
    AxsSpringTwelveReboot3Function rebootFunction =
        (AxsSpringTwelveReboot3Function)symbol;

    /* Revalidate after symbol resolution, immediately before the one action. */
    if (!axs_springtwelve_parentMatches(parent)) {
        return AxsSpringTwelvePowerHelperPermission;
    }
    const uint64_t flags = UINT64_C(0x2000000000000000);
    if (rebootFunction(flags) != 0) {
        return AxsSpringTwelvePowerHelperRebootError;
    }
    return AxsSpringTwelvePowerHelperSubmitted;
}

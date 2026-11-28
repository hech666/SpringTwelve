#define _DARWIN_C_SOURCE 1
#include <assert.h>
#include <dlfcn.h>
#include <errno.h>
#include <grp.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/types.h>
#include <unistd.h>
#include "../PowerHelper/HaogeSpringTwelveServiceRestart.h"

static uid_t ruid, euid;
static gid_t rgid, egid;
static const char *parentPath;
static int failure, count, killed[4], rebootCalls, pathChecks[2];
static uid_t test_getuid(void) { return ruid; }
static uid_t test_geteuid(void) { return euid; }
static gid_t test_getgid(void) { return rgid; }
static gid_t test_getegid(void) { return egid; }
static pid_t test_getppid(void) { return 123; }
static int test_setgroups(size_t n, const gid_t *g) { (void)n; (void)g; return failure == 1 ? -1 : 0; }
static int test_setgid(gid_t g) { rgid = egid = g; return 0; }
static int test_setuid(uid_t u) { ruid = euid = u; return 0; }
static int test_proc_listpids(uint32_t t, uint32_t ti, void *b, int size) {
    assert(t == 1 && ti == 0);
    if (failure == 2) return -1;
    if (failure == 3) return size;
    if (failure == 4) return 1;
    pid_t pids[] = {202, 201, 203};
    memcpy(b, pids, sizeof(pids)); return (int)sizeof(pids);
}
static int test_proc_name(int pid, void *b, uint32_t size) {
    const char *n = pid == 201 ? "replayd" : pid == 202 ? "backboardd" : "unrelated";
    if ((failure == 8 && pid == 201) || (failure == 9 && pid == 202)) return 0;
    assert(strlen(n) < size); strcpy(b, n); return (int)strlen(n);
}
static int test_proc_pidpath(int pid, void *b, uint32_t size) {
    const char *p = parentPath;
    if (pid != 123) {
        assert(pid == 201 || pid == 202);
        int index = pid == 201 ? 0 : 1;
        pathChecks[index]++;
        if (failure == 5 && pid == 201) { errno = EACCES; return -1; }
        if (failure == 6 && pid == 201) { errno = ESRCH; return -1; }
        p = pid == 201 ? "/usr/libexec/replayd" : "/usr/libexec/backboardd";
        if ((failure == 7 && pid == 201) || (failure == 10 && pathChecks[index] > 1 && pid == 201)) p = "/tmp/replayd";
    }
    assert(strlen(p) < size); strcpy(b, p); return (int)strlen(p);
}
static int test_kill(pid_t pid, int sig) {
    assert(sig == SIGKILL && (pid == 201 || pid == 202));
    assert(count < 4); killed[count++] = pid;
    if (failure == 11) { errno = EPERM; return -1; }
    if (failure == 12) { errno = ESRCH; return -1; }
    return 0;
}
static int test_reboot(uint64_t flags, ...) { assert(flags == UINT64_C(0x2000000000000000)); rebootCalls++; return failure == 14 ? -1 : 0; }
static void *test_dlsym(void *handle, const char *symbol) {
    (void)handle; assert(strcmp(symbol, "reboot3") == 0);
    return failure == 13 ? NULL : (void *)test_reboot;
}
#define HAOGE_SPRINGTWELVE_HELPER_TEST 1
#define getuid test_getuid
#define geteuid test_geteuid
#define getgid test_getgid
#define getegid test_getegid
#define getppid test_getppid
#define setgroups test_setgroups
#define setgid test_setgid
#define setuid test_setuid
#define proc_listpids test_proc_listpids
#define proc_name test_proc_name
#define proc_pidpath test_proc_pidpath
#define kill test_kill
#define dlsym test_dlsym
#include "../PowerHelper/main.c"

static int run(const char *action, const char *parent, int f) {
    ruid = 501; euid = 0; rgid = egid = 501;
    parentPath = parent; failure = f; count = rebootCalls = 0;
    memset(pathChecks, 0, sizeof(pathChecks));
    char *args[] = {(char *)"helper", (char *)action, NULL};
    return haoge_springtwelve_powerHelperMain(2, args);
}
int main(void) {
    const char *prefs = "/Applications/Preferences.app/Preferences";
    const char *sb = "/System/Library/CoreServices/SpringBoard.app/SpringBoard";
    const char *a = "restart-motionx-services";
    assert(run(a, prefs, 0) == 0); assert(count == 2 && killed[0] == 201 && killed[1] == 202 && rebootCalls == 0);
    for (int f = 1; f <= 5; f++) { assert(run(a, prefs, f) == (f == 1 ? 78 : 71)); assert(count == 0); }
    for (int f = 6; f <= 8; f++) { assert(run(a, prefs, f) == 0); assert(count == 1 && killed[0] == 202); }
    assert(run(a, prefs, 9) == 71); assert(count == 1 && killed[0] == 201);
    assert(run(a, prefs, 10) == 0); assert(count == 1 && killed[0] == 202);
    assert(run(a, prefs, 11) == 71); assert(count == 1);
    assert(run(a, prefs, 12) == 0); assert(count == 2);
    assert(run(a, sb, 0) == 77 && count == 0);
    assert(run("userspace-reboot", prefs, 0) == 77 && count == 0 && rebootCalls == 0);
    assert(run("userspace-reboot", sb, 0) == 0 && count == 0 && rebootCalls == 1);
    assert(run("userspace-reboot", sb, 13) == 69);
    assert(run("userspace-reboot", sb, 14) == 70);
    assert(run("arbitrary", prefs, 0) == 64);
    assert(run(a, "/tmp/Preferences", 0) == 77);
    (void)run(a, prefs, 0); ruid = 0;
    char *args[] = {(char *)"helper", (char *)a, NULL};
    assert(haoge_springtwelve_powerHelperMain(2, args) == 77);
    assert(haoge_springtwelve_powerHelperMain(0, NULL) == 64);
    puts("PASS actual helper with mocked OS: fixed service order, path filtering/recheck, failure handling, caller isolation, unchanged reboot flags; no real signals");
    return 0;
}

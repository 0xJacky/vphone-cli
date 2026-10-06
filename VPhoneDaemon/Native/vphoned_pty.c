#include "Include/VphonedNative.h"

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <termios.h>
#include <unistd.h>

// The host Terminal window's shells. vphoned has threads (NIO, dispatch), so
// the child does only async-signal-safe system calls between fork() and
// execve(): everything it needs (paths, argv, envp, the descriptor limit) is
// prepared here first. forkpty() is not used because it lives in libutil, and
// posix_spawn cannot make the terminal the child's controlling terminal and
// change its user in one call without private SPI.

int vp_pty_spawn(const VPPtySpawnRequest *request, int *master_out, int32_t *pid_out) {
    if (request == NULL || request->path == NULL || request->argv == NULL || request->envp == NULL) {
        return EINVAL;
    }
    int master = posix_openpt(O_RDWR | O_NOCTTY);
    if (master < 0) return errno;
    if (grantpt(master) != 0 || unlockpt(master) != 0) {
        int error = errno;
        close(master);
        return error;
    }
    char name[128];
    if (ptsname_r(master, name, sizeof(name)) != 0) {
        int error = errno;
        close(master);
        return error;
    }
    // Opened here, without becoming vphoned's controlling terminal, so the
    // size set below is not cleared by the first open in the child.
    int slave = open(name, O_RDWR | O_NOCTTY);
    if (slave < 0) {
        int error = errno;
        close(master);
        return error;
    }
    // The shell's user owns its terminal, as after login(1): tty(1), mesg and
    // programs that reopen the terminal by name need that.
    (void)fchown(slave, request->uid, (gid_t)-1);
    (void)fchmod(slave, 0620);
    struct winsize size = {
        .ws_row = request->rows > 0 ? request->rows : 24,
        .ws_col = request->columns > 0 ? request->columns : 80,
    };
    (void)ioctl(slave, TIOCSWINSZ, &size);
    (void)fcntl(master, F_SETFD, FD_CLOEXEC);

    int limit = getdtablesize();
    if (limit < 0 || limit > 65536) limit = 65536;
    gid_t groups[1] = {request->gid};
    sigset_t empty;
    sigemptyset(&empty);

    // The child reports a failed setup or execve through this pipe as an
    // errno value; a successful execve closes it empty.
    int report[2];
    if (pipe(report) != 0) {
        int error = errno;
        close(slave);
        close(master);
        return error;
    }
    (void)fcntl(report[0], F_SETFD, FD_CLOEXEC);
    (void)fcntl(report[1], F_SETFD, FD_CLOEXEC);

    pid_t pid = fork();
    if (pid < 0) {
        int error = errno;
        close(report[0]);
        close(report[1]);
        close(slave);
        close(master);
        return error;
    }
    if (pid == 0) {
        // vphoned ignores or blocks some signals; a shell starts with defaults.
        struct sigaction defaults;
        memset(&defaults, 0, sizeof(defaults));
        defaults.sa_handler = SIG_DFL;
        for (int signal_number = 1; signal_number < NSIG; signal_number++) {
            if (signal_number == SIGKILL || signal_number == SIGSTOP) continue;
            (void)sigaction(signal_number, &defaults, NULL);
        }
        (void)sigprocmask(SIG_SETMASK, &empty, NULL);
        int failure = 0;
        if (setsid() < 0 || ioctl(slave, TIOCSCTTY, 0) != 0 || dup2(slave, STDIN_FILENO) < 0 ||
            dup2(slave, STDOUT_FILENO) < 0 || dup2(slave, STDERR_FILENO) < 0) {
            failure = errno;
        }
        // Nothing else vphoned has open reaches the shell. The report pipe is
        // close-on-exec, so it stays until execve.
        for (int descriptor = STDERR_FILENO + 1; failure == 0 && descriptor < limit; descriptor++) {
            if (descriptor != report[1]) (void)close(descriptor);
        }
        if (failure == 0 && (setgroups(1, groups) != 0 || setgid(request->gid) != 0 || setuid(request->uid) != 0)) {
            failure = errno;
        }
        if (failure == 0) {
            if (request->cwd == NULL || chdir(request->cwd) != 0) (void)chdir("/");
            execve(request->path, request->argv, request->envp);
            failure = errno;
        }
        (void)write(report[1], &failure, sizeof(failure));
        _exit(127);
    }
    close(report[1]);
    close(slave);
    int failure = 0;
    ssize_t count;
    do {
        count = read(report[0], &failure, sizeof(failure));
    } while (count < 0 && errno == EINTR);
    close(report[0]);
    if (count == (ssize_t)sizeof(failure)) {
        // The child never became the shell: reap it here.
        int status;
        while (waitpid(pid, &status, 0) < 0 && errno == EINTR) {}
        close(master);
        return failure != 0 ? failure : ENOEXEC;
    }
    *master_out = master;
    *pid_out = pid;
    return 0;
}

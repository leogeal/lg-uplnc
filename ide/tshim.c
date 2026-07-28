/* tshim.c: the narrow C platform shim for the UPLNC IDE (IDE.md section 2.1).
 *
 * Every function takes and returns intptr_t-compatible values, so the UPLNC
 * side never sees a bare C `int` return with an unspecified upper half (the
 * hazard examples/cint.he documents). Every C struct -- termios, winsize,
 * pollfd, sigaction -- stays on this side of the boundary. Compiled by the
 * same cc that links the target (langdrv.pl accepts .c inputs), so cross
 * builds get the target's own libc definitions of these structs.
 */
#include <stdint.h>
#include <unistd.h>
#include <termios.h>
#include <sys/ioctl.h>
#include <poll.h>
#include <signal.h>
#include <errno.h>

static struct termios tsh_saved;
static intptr_t tsh_have_saved = 0;
static volatile sig_atomic_t tsh_winch = 0;

/* enter raw mode on stdin, saving the exact prior state; 0 ok, -1 error */
intptr_t tsh_rawon(void)
{
    struct termios t;
    if (tcgetattr(0, &tsh_saved) != 0) return -1;
    tsh_have_saved = 1;
    t = tsh_saved;
    cfmakeraw(&t);
    t.c_cc[VMIN] = 1;
    t.c_cc[VTIME] = 0;
    if (tcsetattr(0, TCSAFLUSH, &t) != 0) return -1;
    return 0;
}

/* restore the exact state tsh_rawon saved; a no-op if it never ran */
intptr_t tsh_rawoff(void)
{
    if (!tsh_have_saved) return 0;
    return tcsetattr(0, TCSAFLUSH, &tsh_saved) != 0 ? -1 : 0;
}

/* the terminal size as rows*65536+cols, or -1 */
intptr_t tsh_winsz(void)
{
    struct winsize w;
    if (ioctl(1, TIOCGWINSZ, &w) != 0) return -1;
    return ((intptr_t)w.ws_row << 16) | (intptr_t)w.ws_col;
}

static void tsh_onwinch(int sig)
{
    (void)sig;
    tsh_winch = 1;
}

/* install the SIGWINCH handler; 0 ok, -1 error */
intptr_t tsh_sigwinch(void)
{
    struct sigaction sa;
    sa.sa_handler = tsh_onwinch;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = 0;   /* poll() must see EINTR so a resize wakes the wait */
    return sigaction(SIGWINCH, &sa, 0) != 0 ? -1 : 0;
}

/* read-and-clear the resize flag */
intptr_t tsh_tookwinch(void)
{
    intptr_t w = tsh_winch;
    tsh_winch = 0;
    return w;
}

/* wait up to ms for fd to become readable or reach EOF: 1 ready, 0 timeout or
 * resize interruption (the caller checks tsh_tookwinch), -1 descriptor/error */
intptr_t tsh_poll(intptr_t fd, intptr_t ms)
{
    struct pollfd p;
    int r;
    p.fd = (int)fd;
    p.events = POLLIN;
    p.revents = 0;
    do {
        r = poll(&p, 1, (int)ms);
    } while (r < 0 && errno == EINTR && !tsh_winch);
    if (r < 0) return tsh_winch ? 0 : -1;
    if (r == 0) return 0;
    if (p.revents & POLLNVAL) return -1;
    if (p.revents & (POLLIN | POLLHUP)) return 1;
    if (p.revents & POLLERR) return -1;
    return 0;
}

/* read up to n bytes; the byte count, 0 at EOF, -1 on error */
intptr_t tsh_read(intptr_t fd, char *buf, intptr_t n)
{
    ssize_t r;
    do {
        r = read((int)fd, buf, (size_t)n);
    } while (r < 0 && errno == EINTR);
    return (intptr_t)r;
}

/* write all n bytes; n, or -1 on error */
intptr_t tsh_write(intptr_t fd, const char *buf, intptr_t n)
{
    intptr_t done = 0;
    while (done < n) {
        ssize_t r = write((int)fd, buf + done, (size_t)(n - done));
        if (r < 0) {
            if (errno == EINTR) continue;
            return -1;
        }
        done += r;
    }
    return done;
}

/* pipe() into two FULL-WIDTH slots -- the packed-C-int hazard IDE.md
 * section 2.1 documents is owned here, on the C side, forever */
intptr_t tsh_pipe(intptr_t *fds)
{
    int p[2];
    if (pipe(p) != 0) return -1;
    fds[0] = (intptr_t)p[0];
    fds[1] = (intptr_t)p[1];
    return 0;
}

intptr_t tsh_close(intptr_t fd)
{
    return close((int)fd) != 0 ? -1 : 0;
}

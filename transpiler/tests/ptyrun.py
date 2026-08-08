# ptyrun.py: run a terminal program on a pseudo-terminal, feed it a script
# of events, and write everything it printed to stdout; the exit status and
# whether the termios state was restored exactly go to stderr.
#
#   ptyrun.py BIN ROWSxCOLS [a:ARG ...] [w:HEXBYTES | p | z:ROWSxCOLS ...]
#
#     a:ARG   pass ARG to the program (before any event)
#     w:HEX   write these bytes to its terminal, then let it settle
#     p       just let it settle
#     z:RxC   resize the terminal and deliver SIGWINCH
#
# Pipe the stdout through screen.py to assert on what a user would see.
import os, pty, sys, termios, fcntl, struct, signal, time, subprocess, select
binpath, size = sys.argv[1], sys.argv[2]
rows, cols = map(int, size.split('x'))
m, s = pty.openpty()
fcntl.ioctl(m, termios.TIOCSWINSZ, struct.pack('HHHH', rows, cols, 0, 0))
before = termios.tcgetattr(s)
args = [binpath] + [a[2:] for a in sys.argv[3:] if a.startswith('a:')]
ops = [a for a in sys.argv[3:] if not a.startswith('a:')]
p = subprocess.Popen(args, stdin=s, stdout=s, stderr=s, start_new_session=True)
out = b''
def drain(t=0.35):
    global out
    end = time.time()+t
    while time.time() < end:
        r,_,_ = select.select([m],[],[],0.05)
        if r:
            try: out += os.read(m, 65536)
            except OSError: break
drain()
for op in ops:
    if op.startswith('w:'):
        os.write(m, bytes.fromhex(op[2:])); drain()
    elif op == 'p':
        drain(0.3)
    elif op.startswith('z:'):
        r,c = map(int, op[2:].split('x'))
        fcntl.ioctl(m, termios.TIOCSWINSZ, struct.pack('HHHH', r, c, 0, 0))
        p.send_signal(signal.SIGWINCH); drain()
rc = p.wait(timeout=5)
drain(0.2)
after = termios.tcgetattr(s)
os.close(m); os.close(s)
sys.stdout.buffer.write(out)
print(f"\nRC={rc} TERMIOS_RESTORED={before==after}", file=sys.stderr)

# Replay a terminal byte stream into a screen model and print the final grid.
# Understands what ide/tui.e emits: CSI row;colH, CSI 2J, SGR (ignored for
# content), the DEC charset shifts, and printable bytes.
import sys, re
rows, cols = (int(x) for x in sys.argv[1].split('x'))
g = [[' ']*cols for _ in range(rows)]
cy = cx = 0
data = sys.stdin.buffer.read()
i = 0
while i < len(data):
    c = data[i]
    if c == 0x1b:
        m = re.match(rb'\x1b\[([0-9;]*)([A-Za-z])', data[i:])
        if m:
            args, fin = m.group(1), m.group(2)
            if fin == b'H':
                p = [int(x) for x in args.split(b';') if x != b'']
                cy = (p[0]-1) if len(p) > 0 else 0
                cx = (p[1]-1) if len(p) > 1 else 0
            elif fin == b'J':
                g = [[' ']*cols for _ in range(rows)]
            i += m.end()
            continue
        m = re.match(rb'\x1b[()][0B]', data[i:])
        if m:
            i += m.end()
            continue
        m = re.match(rb'\x1b\[\?[0-9]+[hl]', data[i:])
        if m:
            i += m.end()
            continue
        i += 1
        continue
    if 32 <= c < 127:
        if 0 <= cy < rows and 0 <= cx < cols:
            g[cy][cx] = chr(c)
        cx += 1
    i += 1
for r in g:
    print(''.join(r).rstrip())

# A Turbo-style IDE in UPLNC — feasibility assessment and design plan

Assessed 2026-07. Status: **planned, not started** — this document records the
design so the project can begin from a settled plan (the ROADMAP links here
from the M6 tooling item). The goal: a full-screen text-mode IDE in the spirit
of Borland's Turbo Pascal / Turbo C++ — blue desktop, pull-down menus,
double-line window borders, F-key bindings — written **in UPLNC**, editing and
building UPLNC (and other languages), with **integrated debugging**. It would
be the largest UPLNC program ever written and the ultimate M7 dogfood: an IDE
written in UPLNC, debugging programs compiled by the compiler written in
UPLNC, through debug information that compiler emits.

## 1. Verdict

Feasible now. Every capability the design needs either exists (most were
built in 2026-07) or has a pragmatic v1 fallback. The known constraints it
will hit (§6) are survivable, and two of them are exactly the kind of finding
dogfooding exists to force.

## 2. Look & feel: the easy part

Borland's UI is character cells. On a modern terminal:

- **Rendering**: ANSI escape sequences — 16-color SGR (the Borland palette
  maps directly: blue desktop, cyan/white menus, black shadows), cursor
  addressing, the alternate screen. Shadows are repainted cells offset by
  one.
- **Compositor**: every widget draws into an in-memory cell grid (glyph ID,
  foreground/background color, attributes). A diff pass flushes only changed
  *cells*. ASCII glyph IDs emit one byte; box-drawing IDs map to the UTF-8 byte
  strings for `═ ║ ╔ ╗ ╚ ╝`. This keeps a three-byte UTF-8 encoding from being
  mistaken for three screen cells and leaves room for an ASCII-border mode.
- **Input**: `read(0, &c, 1)` plus an escape-sequence state machine for
  arrows, F-keys, and Alt (ESC-prefixed) — a calc-sized parser.
- **Terminal lifecycle**: a narrow C portability shim is a v1 requirement,
  not a later refinement. It snapshots the exact `termios`, enters raw mode,
  restores the snapshot on normal teardown/`atexit`, reads `TIOCGWINSZ`, and
  turns SIGWINCH into a flag plus a wakeup byte for the event loop. A hard
  kill cannot be recovered from, but ordinary exits and handled termination
  must not replace the user's settings with a generic `stty sane` preset.

### 2.1 The platform ABI shim

UPLNC's word-sized `int` is 64 bits on four targets, while C `int` remains 32
bits. This affects pointers to C integers even when scalar integer calls happen
to marshal correctly: calling `pipe(fds)` with a UPLNC `[2]int` would place two
adjacent C descriptors inside `fds[0]` on a 64-bit target. A negative C `int`
return can likewise arrive as an unextended 32-bit value on x86_64/arm64. The
shim therefore owns every C-width return/output or C-structure interface used
by the IDE: process/descriptor operations, `termios`, `winsize`, `pollfd`, and
`sigaction`.

Its UPLNC-facing functions use scalar values, ordinary byte buffers, and
`intptr_t` returns/output slots (the same width as a UPLNC `int`). For example,
`ide_pipe(readfd:*int,writefd:*int)` creates a C `int p[2]` internally and
writes each descriptor to a separate `intptr_t`; wrappers for `fork`, `dup2`,
`close`, and child status sign-extend C results before returning them. The shim
contains no editor, terminal-rendering, or debugger policy; it is a small
target portability layer compiled and linked as one additional object.

## 3. Why the language is ready (2026-07 inventory)

| Need | Have |
|---|---|
| Widget/buffer objects | structs with methods, **typed method returns** (PR #113): `buf.line(n):*char` |
| Event-handler tables | function pointers via indirect calls — int/pointer args, `int` return: exactly an event handler's shape (a poor-man's Turbo Vision vtable; no virtual dispatch needed) |
| Text buffers | malloc/realloc/free with proven grow/teardown patterns (`sort_lines.e`); a line-pointer array, gap-style insertion by moving pointers |
| Status lines, dialogs | `lib/fmt.e`: `%d %u %x %c %s %f %e %g`, widths, exact float digits |
| Many-unit program | `langdrv.pl` multi-unit builds, per-unit linking proven by grep/sort |
| Error navigation | langc's `file:line: Error:` diagnostics with include-correct locations — parse stderr into an error window, jump to line |
| Debugging substrate | `-g`: DWARF line tables, CFI unwind, variable/type DIEs — gdb does file:line breakpoints, stepping, `info locals`, struct members, backtraces with parameters (PRs #101–#114) |
| Platform boundary | One narrow C shim for C-width output arrays/structures, exact terminal restoration, resize wakeups, and event polling (§2.1) |

## 4. Integrated debugging: the crown jewel

**v1 design: drive `gdb --interpreter=mi` as a child process.** The process
topology has three independent channels:

1. an IDE-to-gdb pipe for MI commands;
2. a gdb-to-IDE pipe for MI records; and
3. a dedicated pseudo-terminal for the inferior, selected with
   `-inferior-tty-set`, whose bytes appear in a console pane and whose input
   never enters the MI command stream.

The event loop monitors terminal input, gdb MI output, inferior PTY output,
child status, and the resize wakeup through the shim in §2.1. UPLNC owns the
topology and lifecycle; the shim's process primitives only normalize C-width
returns/outputs and keep descriptor arrays and polling structures from crossing
the ABI directly. The command translation is:

| Turbo key | gdb/MI |
|---|---|
| Ctrl-F8 toggle breakpoint | `-break-insert file:line` / `-break-delete` |
| F7 step into / F8 step over | `-exec-step` / `-exec-next` |
| F4 run to cursor | `-exec-until file:line` |
| Ctrl-F9 run | `-exec-run` / `-exec-continue` |
| Watch window | `-var-create`, `-data-evaluate-expression` |
| Call-stack window | `-stack-list-frames` |

MI output is record-oriented text, but it is not safely parsed by splitting on
commas or looking only for line prefixes. The parser must handle result/async/
stream records, optional numeric tokens, C-string escaping, tuples, and lists;
unknown fields are retained or skipped structurally. This works *because of*
the 2026-07 debug-info arc: the IDE presents, in our own UI, exactly what
langc's `-g` emits.

**Stretch (phase 4, compiler-sized project): a native ptrace debugger** —
`ptrace()` is int/pointer-arg (ABI-safe), INT3 breakpoints, single-step,
`.debug_line`/`.debug_frame` reading. Tractable only because we would read
the DWARF subset *we emit*, not general DWARF. Registers via
`PTRACE_GETREGS` need per-arch opaque-buffer offset tables. Do not start
here.

## 5. Other languages

The architecture is language-agnostic by construction: a language profile is
(1) a build-command template, (2) an error-message pattern (gcc emits the
same `file:line:` shape), (3) a keyword table for highlighting, (4) the same
gdb/MI backend (gcc's DWARF is richer than ours, which is fine). "For UPLNC
and other languages" reduces mostly to configuration.

## 6. Constraints it will hit (the dogfood value)

- **15-char identifiers, and `Struct.method` mangles ≤ 15 total**
  (LANGUAGE.md §14) — the first limit to hurt at 10k+ lines; may motivate
  raising NAMESIZE (a fixpoint-affecting change to plan deliberately).
- **16,000-byte string-literal pool per unit** — an IDE is full of UI text.
  Authentic fix: Borland's own — help/UI text in external files loaded at
  runtime (`TURBO.HLP` style), plus spreading literals across units.
- **No internal linkage** — 15+ units share one namespace; keep the
  `grep_`/`sort_` prefix discipline.
- **Indirect calls return `int` only** — handler tables fit today; a
  pointer-returning handler would extend the typed-return story to indirect
  calls (a natural future language item).
- 158-byte source lines, 6000-byte macro pool: minor, workable.

## 7. Phasing

1. **Platform + screen/input slice**: land the ABI shim first, with all-target
   pipe round-trip tests and PTY-hosted tests proving exact terminal restore
   and resize delivery. Then add pinned escape-sequence transcripts for the
   glyph-aware cell compositor, palette, box/shadow drawing, and key decoder.
2. **Phase 1 IDE** (~3–5k lines; langc is ~7k): menu bar, one editor window
   (open/save/search/block ops), F9 build with error-jump. *The Turbo feel
   arrives here.*
3. **Phase 2**: gdb/MI debugging — structured MI parser, dedicated inferior
   PTY and console pane, breakpoint margin, F7/F8, watch and call-stack
   windows.
4. **Phase 3**: overlapping/resizable windows, language profiles, help
   viewer from external files.
5. **Phase 4 (optional)**: native ptrace backend, x86_64 first.

## 8. Risks

- **Scale**: the largest UPLNC program by far; compiler robustness at this
  scale is itself part of the experiment (the sanitizer/fuzz + fixpoint
  gates are the safety net).
- **Terminal diversity**: stick to vt100/xterm sequences universally
  supported; degrade box glyphs to ASCII on request.
- **Platform boundary**: keep the C shim narrow and regression-test its public
  scalar/`intptr_t` ABI on every target; no UI or debugger policy belongs in
  it.
- **gdb/MI availability**: gdb is a run-time dependency for phase 2 only;
  the IDE without it is still a full editor/builder.

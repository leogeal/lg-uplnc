# Example utilities written in UPLNC

Small, self-contained programs written in the UPLNC language itself — the
"proof it's real" that the recovered language is usable for actual programs
(ROADMAP M7), not just for compiling its own compiler.

Each builds with the stage-0 tools (`transpiler/build/`) and runs on any of the
five backends. `wc` and `cat` call libc directly; `fmtdemo`, `hexdump`, and
`grep` use the first UPLNC library component, `lib/fmt.e`.

## `wc.e` — count lines, words and characters

A faithful `wc` reading standard input and printing `<lines> <words> <chars>`.
Exercises char-by-char I/O (`getchar`), EOF handling (sign-extended `-1`), a
whitespace state machine for word counting, and `printf`.

```sh
perl src/langdrv.pl -march=x86_64 examples/wc.e -o /tmp/wc
echo "hello world" | /tmp/wc          #  ->  1 2 12
/tmp/wc < examples/wc.e               #  matches system wc
```

## `cat.e` — concatenate files

A `cat` taking file names on the command line. With no arguments, or for an
argument of `-`, it reads standard input. Exits 1 if any file won't open.
Exercises `main(argc, argv)`, `fopen`/`fgetc`/`fclose`, the `stderr` extern, and
`fprintf`.

```sh
perl src/langdrv.pl -march=x86_64 examples/cat.e -o /tmp/cat
/tmp/cat examples/wc.e               # print a file
/tmp/cat a.txt - b.txt < piped       # files with stdin spliced in via "-"
```

## `grep.e` — multi-file text search

A deliberately small but operational `grep`, split into a CLI/I/O unit and a
reusable matcher unit (`grep_match.e` + `grep_match.he`). It accepts combined
`-n`, `-i`, and `-v` options, `--`, stdin, and multiple files, with conventional
exit statuses: 0 for a selected line, 1 for no selection, and 2 for an error.

The pattern language supports literals, `.` (any byte), `^`/`$` anchors, `*`
(zero or more of the preceding atom), and backslash quoting. It is intended for
text input. Patterns are limited to 120 bytes and lines to 1023 bytes; excessive
backtracking, an overlong pattern, or an overlong line produces an explicit
error instead of hanging or silently truncating.

```sh
perl src/langdrv.pl -march=x86_64 examples/grep.e \
    examples/grep_match.e lib/fmt.e -o /tmp/grep
/tmp/grep -ni '^error.*$' build.log other.log
printf 'one\ntwo\n' | /tmp/grep -v '^one$'
```

## `fmtdemo.e` and `hexdump.e` — formatted output

These include the declarations in `lib/fmt.he`; compile `lib/fmt.e` once and
link it with the program. Quoted includes resolve relative to the including
source file, so preprocessing is independent of the current working directory.

```sh
perl src/langdrv.pl -march=x86_64 examples/fmtdemo.e lib/fmt.e -o /tmp/fmtdemo
perl src/langdrv.pl -march=x86_64 examples/hexdump.e lib/fmt.e -o /tmp/hexdump
printf 'hello\n' | /tmp/hexdump
```

## Building for other targets

Swap `-march=x86_64` for `-march=arm64`, `-march=riscv64`, or
`-march=mips64`; the driver selects the matching cross-toolchain and static-link
flags. Drop `-march` for the default i386 target. All five utilities behave
identically on all five backends.

The `[11]` section of `transpiler/tests/run_tests.sh` builds and runs all five
utilities for the host's native arch on every CI run. The backend sections also
build and run the separately linked grep matcher on every available target.

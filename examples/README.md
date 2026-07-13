# Example utilities written in UPLNC

Small, self-contained programs written in the UPLNC language itself — the
"proof it's real" that the recovered language is usable for actual programs
(ROADMAP M7), not just for compiling its own compiler.

Each builds with the stage-0 tools (`transpiler/build/`) and runs on any of the
five backends. `wc` and `cat` call libc directly; `fmtdemo` and `hexdump` use
the first UPLNC library component, `lib/fmt.e`.

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
flags. Drop `-march` for the default i386 target. All four utilities behave
identically on all five backends.

The `[11]` section of `transpiler/tests/run_tests.sh` builds and runs all four
utilities for the host's native arch on every CI run.

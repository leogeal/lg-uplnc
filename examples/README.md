# Example utilities written in UPLNC

Small, self-contained programs written in the UPLNC language itself — the
"proof it's real" that the recovered language is usable for actual programs
(ROADMAP M7), not just for compiling its own compiler.

Each builds with the stage-0 tools (`transpiler/build/`) and runs on any of the
five backends. They call into libc directly (an unknown function is treated as
an `extern` returning `int`).

## `wc.e` — count lines, words and characters

A faithful `wc` reading standard input and printing `<lines> <words> <chars>`.
Exercises char-by-char I/O (`getchar`), EOF handling (sign-extended `-1`), a
whitespace state machine for word counting, and `printf`.

```sh
cd transpiler
build/lpp1 ../examples/wc.e | build/langc -march=x86_64 | gcc -no-pie -x assembler - -o /tmp/wc
echo "hello world" | /tmp/wc          #  ->  1 2 12
/tmp/wc < ../examples/wc.e            #  matches system wc
```

Swap `-march=x86_64` for `-march=arm64` / `-march=riscv64` / `-march=mips64`
(assemble + run with the matching cross-toolchain under qemu), or drop `-march`
for i386 (`gcc -m32`). The output matches system `wc` on all five.

The `[11]` section of `transpiler/tests/run_tests.sh` builds and runs `wc` for
the host's native arch on every CI run.

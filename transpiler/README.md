# uplnc2c — UPLNC → C transpiler (bootstrap stage 0)

`uplnc2c.py` translates the self-hosting UPLNC compiler sources (`../src/*.e`,
`*.he`) into C, so that gcc can build a throwaway **stage-0** compiler. That
stage-0 compiler is then meant to compile the UPLNC sources to i386 assembly and
self-host (see [`../BOOTSTRAP.md`](../BOOTSTRAP.md) for the full plan and the
self-host fixpoint that is the acceptance test).

## Usage

```sh
python3 uplnc2c.py FILE.e [-I included.he ...] [-o OUT.c]
./build.sh            # transpile everything and build build/lpp1 and build/langc
bash tests/run_tests.sh
```

`-I` headers are parsed only to populate the type/struct/method environment
(needed to resolve method dispatch and the two `var` declaration orders); they
are not emitted. A `*.he` target emits a header (no prelude); a `*.e` target
emits a full translation unit.

## Status

| Component | Transpiles | Compiles | Runs correctly | Self-compiles (stage 1) |
|-----------|:----------:|:--------:|:--------------:|:-----------------------:|
| `lpp1` (preprocessor) | ✅ | ✅ | ✅ | ✅ |
| `langc`+`codegen`+`autodyn`+`grph` | ✅ | ✅ | ✅ | ✅ |

The stage-0 compiler is **working**: built at 64-bit, `langc` compiles UPLNC to
i386 assembly, and it **self-compiles every one of its own units** — including the
4,331-line `langc.e` — to assembly with **0 errors** (verified by the test suite).
`lpp1` works as a real preprocessor. And the **self-host fixpoint holds**: CI runs
`fixpoint.sh` under `gcc-multilib` and confirms stage-2 and stage-3 assembly are
byte-identical. This is BOOTSTRAP.md steps 2–4 done.

### Return-type inference (closed the 64-bit width hazard)

UPLNC is an **i386** language: `int` and pointers are both 4 bytes (`WORDSIZE 4`),
and UPLNC functions default to returning `int`. Many compiler functions actually
return *pointers* (`autodynstr`, `dyncalloc`, the node allocators, …). At 64-bit a
pointer returned through `int` is truncated → the earlier build segfaulted.

`uplnc2c` now **infers return types**: across all units it classifies a function
as pointer-returning if any `return` expression is provably a pointer —
transitively (a call to a pointer-returning function or a libc allocator counts),
iterated to a fixpoint. Such functions are emitted as `void *` (correct pointer
width) in both their definition and their cross-unit forward declaration. 72
functions are inferred as pointer-returning; `langc` then runs correctly at
64-bit. (`void *` rather than a precise struct type avoids needing the struct
typedef visible at the forward declaration, and is sufficient for correctness.)

### The self-host fixpoint (verified in CI)

`fixpoint.sh` builds stage-1 (`langc1`) and stage-2 (`langc2`) by assembling each
generation's output with `gcc -m32`, then recompiles once more and checks that
**stage-2 and stage-3 assembly are byte-identical** — the acceptance test in
BOOTSTRAP.md §4. It is gated on `-m32` (printing an install hint if absent).

CI runs it under `gcc-multilib` and **it passes**, so the compiler is provably
self-hosting from this transpiler. (`langc`'s assembly output is also
deterministic — compiling any unit twice yields identical `.s` — so the fixpoint
is well-defined.) The only thing the original sandbox could not do was install the
32-bit libc; any machine with `gcc-multilib` / `libc6-dev-i386` reproduces it via
`./fixpoint.sh`.

## How it works

A recursive-descent front end with a struct/type model:

* **Lexer** — tokens, comments, char/string literals; `#…` directives at line
  start are captured verbatim (passed through; `#include "x.he"` → `"x.h"`).
* **Three declaration contexts**, each parsed correctly:
  struct members `T name;`, `var [extern] A:B;` (either order — the type is the
  side that starts with `*`/`[`/a type-name), and params (`name:type`,
  `type:name`, or `type name`).
* **Types** — prefix `*`/`[N]` reconstructed into C declarators (`int *a[N]`).
* **Methods** — static dispatch: `method S.m(...)` → `int S_m(S* this, ...)`;
  `recv->m(a)` → `S_m(recv, a)`, `q->fld.m()` → `S_m(&q->fld)`; and an
  **implicit `this`** so a bare field reference inside a method becomes
  `this->field`.
* **Emitter** — K&R (old-style) function definitions, so the C compiler does not
  enforce prototypes — faithfully reproducing UPLNC's untyped K&R-style calls
  (e.g. `error()` declared with one arg but called with two). No libc headers are
  included (UPLNC defines its own `div`, which would clash); the few
  pointer-returning libc routines are declared in a small prelude.

## Files

```
uplnc2c.py        the transpiler
build.sh          transpile all sources + build build/lpp1, build/langc
fixpoint.sh       self-host fixpoint check (stage 1->2->3; needs -m32)
tests/run_tests.sh  smoke + functional tests (19 checks)
tests/pp_input.e    preprocessor test input
build/            generated C, .s, and binaries (gitignored)
```

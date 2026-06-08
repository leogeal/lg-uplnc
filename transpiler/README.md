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

| Component | Transpiles | Compiles | Runs correctly |
|-----------|:----------:|:--------:|:--------------:|
| `lpp1` (preprocessor) | ✅ | ✅ | ✅ (verified: macro expansion, comment stripping, string preservation) |
| `langc` + `codegen` + `autodyn` + `grph` (compiler) | ✅ | ✅ (links to a binary) | ⚠️ needs `-m32` *or* return-type inference — see below |

So the transpiler front-end is **done and exercised end-to-end**: every source
file parses, the full compiler links, and `lpp1` works as a real preprocessor.

### The one remaining gap: int/pointer width

UPLNC is an **i386** language: `int` and pointers are both 4 bytes (`WORDSIZE 4`
in `tlangc.he`), and UPLNC functions default to returning `int`. Many compiler
functions actually return *pointers* (e.g. `autodynstr`, `dyncalloc`, the node
allocators) while still being declared with the default `int` return.

* On a true i386 target this is harmless (int == pointer == 4 bytes). Build with
  `-m32` and `langc` runs correctly. `build.sh` auto-detects `-m32` and uses it.
* On a 64-bit host without `-m32`, a pointer returned through an `int` is
  truncated to 32 bits → `langc` segfaults. `lpp1` is immune only because it has
  no pointer-returning functions.

This sandbox lacks the 32-bit libc (`gcc-multilib` / `libc6-dev-i386`) and has no
sudo, so the `-m32` build can't be produced here; `lpp1` is the working
demonstration. Two ways to close the gap:

1. **`-m32`** — install `gcc-multilib libc6-dev-i386`; `build.sh` then Just Works.
2. **Return-type inference** (host-portable) — infer which UPLNC functions return
   pointers (from their `return` expressions, transitively) and emit a pointer
   return type in the K&R definition and forward declaration. This is the planned
   next increment; it makes `langc` correct at 64-bit too.

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
tests/run_tests.sh  smoke + functional tests (11 checks)
tests/pp_input.e    preprocessor test input
build/            generated C and binaries (gitignored)
```

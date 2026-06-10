# UPLNC Compiler

[![CI](https://github.com/leogeal/lg-uplnc/actions/workflows/ci.yml/badge.svg)](https://github.com/leogeal/lg-uplnc/actions/workflows/ci.yml)
[![transpiler: uplnc2c](https://img.shields.io/badge/transpiler-uplnc2c-blue)](transpiler/)
[![stage-1 self-compile: 0 errors](https://img.shields.io/badge/stage--1%20self--compile-0%20errors-brightgreen)](transpiler/README.md#status)
[![self-host fixpoint: verified in CI](https://img.shields.io/badge/self--host%20fixpoint-verified%20in%20CI-brightgreen)](.github/workflows/ci.yml)
[![license: GPL-2.0](https://img.shields.io/badge/license-GPL--2.0-blue)](LICENSE)

Source code for the compiler of the **UPLNC** language, by Evgueniy Vitchev.

UPLNC is an experimental, C-like systems language created as part of a DIY
platform project (language + tools + OS kernel + utilities). It supports
unlimited levels of indirection, multidimensional arrays, structures, methods
on structures, and most C-style control statements. Its syntax parser is
similar to Small C, and — notably — the compiler is **self-hosting**: it is
written in UPLNC itself and can compile its own source.

The compiler runs in three stages:

1. **Parse** the source and build a syntax tree.
2. Generate an **intermediate representation** of the program.
3. Emit **assembly** code.

## Provenance

There is no upstream code-hosting repository for UPLNC. The complete source was
published as a full listing inside the paper:

> **The UPLNC Compiler: Design and Implementation** — Evgueniy Vitchev
> arXiv: [`cs/0402043`](https://arxiv.org/abs/cs/0402043) (submitted 18 Feb 2004; only version)

The files in [`src/`](src/) were extracted verbatim from the arXiv e-print
archive (the LaTeX `verbatim` listing wrappers were stripped). The code began as
an unmodified extraction; from the **M2 retargeting** work onward `src/` evolves
(see [`ROADMAP.md`](ROADMAP.md) and [`RETARGET-AUDIT.md`](RETARGET-AUDIT.md)).
The **pristine original is always recoverable** — preserved verbatim in the
e-print archive (`uplnc-eprint.tar.gz`, `uplnc-eprint/`) and in the initial git
commit. The original paper and raw archive are kept alongside for reference.

## Layout

| Path | Description |
|------|-------------|
| [`src/`](src/) | Clean compiler source (self-hosting; written in UPLNC) |
| [`transpiler/`](transpiler/) | `uplnc2c` — UPLNC→C transpiler that bootstraps the compiler |
| [`BOOTSTRAP.md`](BOOTSTRAP.md) | Bootstrapping plan + UPLNC feature/grammar inventory |
| [`ROADMAP.md`](ROADMAP.md) | Direction: multi-target, multi-host, floating point, optimization, usability |
| [`RETARGET.md`](RETARGET.md) | Design plan for a retargetable, multi-host backend |
| `uplnc-compiler-paper.pdf` | The full 134-page paper (design + implementation) |
| `uplnc-eprint.tar.gz`, `uplnc-eprint/` | Original arXiv e-print archive and its extracted contents |

### Source files (`src/`)

`.e` files are source; `.he` files are headers.

| File | Role |
|------|------|
| `langc.e` | Main language compiler (lexer, parser, tree builder) |
| `codegen.e` / `codegen.he` | Code generator (IR → assembly) |
| `tlangc.he` | Core compiler declarations / header |
| `autodyn.e` | Automatic allocation / deallocation |
| `lpp1.e` | Preprocessor |
| `grph.e` | Graph utilities |
| `langdrv.pl` | Perl build/driver script |

## Building

Because the compiler is written in UPLNC, building it from scratch requires
bootstrapping with an existing UPLNC compiler binary. The paper (included as
`uplnc-compiler-paper.pdf`) is the authoritative reference for the toolchain and
the three-stage architecture.

See [`BOOTSTRAP.md`](BOOTSTRAP.md) for a concrete bootstrapping plan — what the
build actually needs (two binaries, `lpp1` and `langc`, targeting i386 + glibc),
a UPLNC feature/grammar inventory drawn from the sources, and a transpiler-based
strategy with a self-host fixpoint as the acceptance test.

## Bootstrap status

That plan is implemented in [`transpiler/`](transpiler/) — **`uplnc2c`**, a
UPLNC→C transpiler that breaks the self-hosting cycle:

```sh
cd transpiler
./build.sh              # transpile the UPLNC sources to C, build lpp1 + langc
bash tests/run_tests.sh # 19 checks
./fixpoint.sh           # self-host fixpoint check (needs a 32-bit toolchain)
```

| Stage | State |
|-------|-------|
| Transpile all sources to C | ✅ done |
| `lpp1` preprocessor builds & runs | ✅ done |
| `langc` builds & runs (compiles UPLNC → i386 asm) | ✅ done (return-type inference closed the 64-bit width hazard) |
| Stage-1 self-compile (`langc` compiles its own sources) | ✅ 0 errors on all units, incl. the 4,331-line `langc.e` |
| Self-host fixpoint (stage-2 == stage-3 asm) | ✅ **verified in CI** ([`fixpoint.sh`](transpiler/fixpoint.sh) under `gcc-multilib`/`-m32`) |

The compiler is **provably self-hosting from this transpiler**: CI builds it via
`uplnc2c`, has it recompile its own source twice more, and confirms stage-2 and
stage-3 assembly are byte-identical. See [`transpiler/README.md`](transpiler/README.md)
for the design and full status writeup.

Where it goes from here — retargetable backend, other host CPUs, floating point,
optimization, and real-world usability — is laid out in [`ROADMAP.md`](ROADMAP.md)
(with the backend design in [`RETARGET.md`](RETARGET.md)).

## License

The compiler is released under the **GNU General Public License, version 2 (or,
at your option, any later version)**, © 2003 E.V. See the license headers at the
top of each source file in `src/`.

# UPLNC roadmap

Where the project is and where it could go — from a bootstrapped historical
compiler toward a language usable for real projects. This is a direction
document, not a commitment; items are roughly ordered but independent where
noted.

Status legend: ✅ done · 🟡 in progress · ⏳ planned · 💭 idea

Deep dives: bootstrap → [`BOOTSTRAP.md`](BOOTSTRAP.md); multi-target / multi-host
→ [`RETARGET.md`](RETARGET.md).

---

## M0 — Bootstrap & reproducibility ✅

The compiler is recovered, builds, and is provably self-hosting.

- ✅ Extract the original sources from the arXiv paper (`src/`)
- ✅ `uplnc2c` UPLNC→C transpiler (stage-0 seed)
- ✅ `langc` self-compiles all its own units (0 errors)
- ✅ Self-host **fixpoint** verified (stage-2 ≡ stage-3 assembly), gated in CI
- ✅ Return-type inference (runs correctly on 64-bit hosts)

## M1 — Host portability 🟡

Run the compiler on non-x86 CPUs. Cheap, thanks to the portable C seed.

- ✅ `-fsigned-char` in the build (match i386 `char` semantics everywhere)
- 🟡 CI job building + testing on **arm64** (confirm rather than assume)
- ⏳ Verify on **riscv64** (native runner or QEMU)
- ⏳ Audit remaining host assumptions (endianness; LP64 vs ILP32)
- 💭 Big-endian host support (s390x) — only if anyone needs it

## M2 — Retargetable backend (the seam) 🟡

Make output target a pluggable choice instead of hard-wired i386. See
[`RETARGET.md`](RETARGET.md) Part A. *(Work in progress on the `retarget` branch.)*

- ✅ Phase 0: i386 coupling audit ([`RETARGET-AUDIT.md`](RETARGET-AUDIT.md))
- ✅ Invariance oracle: `transpiler/invariance.sh` (diff emitted `.s`; no `-m32`)
- ✅ Phase 1: **target descriptor + backend seam** (data), i386-only, every step
  proven byte-identical — label prefix, symbol prefix, assembler directives,
  target word size all routed through `struct starget`
- 🟡 `WORDSIZE` split: all *target* sizing now reads `target.wordsize` (the host
  side is the seed toolchain's, never `WORDSIZE`); a distinct `HOST_WORDSIZE`
  only matters once cross-compiling
- 🟡 Phase 2: backend interface + x86_64 — design: [`RETARGET-PHASE2.md`](RETARGET-PHASE2.md)
  - ✅ 2a: arch-id dispatch; `cd_write` split into `cd_write_i386` + x86_64 stub
    (descriptor moved to `codegen.he`; byte-identical i386 output)
  - 🟡 2b: x86_64 backend
    - ✅ `-march=x86_64` flag; `inittarget_x86_64` (wordsize 8); per-arch `regnames`
    - ✅ `cd_write_x86_64` straight-line opcodes — arithmetic, compares,
      loads/stores, loops, pointers, arrays, structs run **natively (no -m32)**
    - 🟡 calling convention
      - ✅ 2b-iii-a: UPLNC↔UPLNC calls (stack convention; param base
        `2*wordsize`) — **functions and recursion run on x86_64**
      - ⏳ 2b-iii-b: libc calls (SysV register marshaling + 16-byte alignment +
        `%al`) → libc I/O; prerequisite for 2c
    - 14 golden programs in `transpiler/tests/progs/`
  - ⏳ 2c: native x86_64 self-host fixpoint (retires `-m32`)
- ✅ `-march=` target selection flag

## M3 — Real targets ⏳

- ⏳ **x86_64** backend (SysV ABI; 16-byte stack alignment; varargs `%al`).
  Bonus: removes the `-m32` dependency — the whole bootstrap runs natively.
- ⏳ **ARM64** backend (developed as a cross-compiler first, tested under QEMU)
- ⏳ Per-target **fixpoint in CI** (x86_64 native; i386 under `-m32`; arm64)
- 💭 RISC-V backend (also validates the abstraction on a non-x86 ISA)

## M4 — Floating-point arithmetic ⏳

Currently integer-only (`int`/`char`). FP is cross-cutting — it touches every
layer:

- ⏳ Lexer: float/double literals (`1.5`, `2e10`)
- ⏳ Types: `float`/`double` in the type system; usual arithmetic conversions
- ⏳ Codegen: SSE2 (`xmm`) on x86_64 / VFP-NEON on ARM; the FP register file and
  FP calling convention (xmm args in SysV)
- ⏳ Library glue: `printf` `%f`, math functions
- 💭 64-bit integers (`long long`) — related width work, often wanted alongside

## M5 — Optimization ⏳

The codegen is a naive stack machine (push/pop around every operation). Biggest
wins first:

- ⏳ **Peephole** pass over `scode` (kill `push`/`pop` pairs, redundant moves)
- ⏳ **Constant folding** in the expression tree
- ⏳ Light **register allocation** — use the register file instead of spilling
  every temporary to the stack
- ⏳ Dead-code / unreachable elimination
- 💭 A cleaner optimizer IR (basic blocks; later SSA) if warranted

## M6 — Toward real-world usability ⏳

What turns a teaching compiler into something you'd build a project with:

- ⏳ **Diagnostics**: line/column in errors, error recovery (not stop-on-first),
  warnings
- ⏳ A small **standard library** (instead of calling libc via bare `extern`s)
- ⏳ **Debug info** (DWARF) so `gdb` works
- ⏳ Language gaps: `unsigned` types, `enum`, `switch`/`case`, robust function
  pointers, proper varargs, `const`
- ⏳ A written **language specification** (the paper is the only spec today)
- ⏳ Tooling: a real driver (replacing `langdrv.pl`), a formatter, editor support
- 💭 Module/namespace system; package layout
- 💭 Robustness: the original compiler can loop on malformed input — add limits /
  graceful errors

## M7 — Proof it's real 💭

- 💭 Port a few non-trivial programs; build a small self-contained utility in UPLNC
- 💭 A test/benchmark suite of UPLNC programs with expected output
- 💭 Re-host: a `langc` that runs natively on arm64 *and* targets arm64, fixpoint-clean

---

### Suggested order

`M1` (cheap, in flight) → `M2` seam → `M3` x86_64 (drops `-m32`) → then parallel
tracks: more targets/hosts, `M4` floating point, `M5` optimization, with `M6`
usability work threaded throughout. The self-host **fixpoint** remains the
non-negotiable acceptance gate at every step.

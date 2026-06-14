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
- ✅ `WORDSIZE` split: target sizing reads `target.wordsize`; host sizing uses
  the host `sizeof` — they never cross, so no separate `HOST_WORDSIZE` is needed.
  Proven host-independent in CI (the *cross-compile* job): a native x86_64 langc
  (8-byte host word) cross-emits i386 (4-byte target word) that self-hosts, and
  its i386 output is byte-identical to the i386-host compiler's (stage-1 ==
  stage-2)
- ✅ Phase 2: backend interface + x86_64 — design: [`RETARGET-PHASE2.md`](RETARGET-PHASE2.md)
  - ✅ 2a: arch-id dispatch; `cd_write` split into `cd_write_i386` + x86_64 stub
    (descriptor moved to `codegen.he`; byte-identical i386 output)
  - ✅ 2b: x86_64 backend
    - ✅ `-march=x86_64` flag; `inittarget_x86_64` (wordsize 8); per-arch `regnames`
    - ✅ `cd_write_x86_64` straight-line opcodes — arithmetic, compares,
      loads/stores, loops, pointers, arrays, structs run **natively (no -m32)**
    - ✅ 2b-iii: **uniform System V calling convention** (Path A) — *every* call
      (UPLNC and libc alike) follows the platform ABI: caller marshals args to
      `rdi…r9` with 16-byte stack alignment (computed from `Zsp`) + `%al=0`;
      callee spills the arg registers to negative param slots. Functions,
      recursion, methods, and **libc** (`printf`/`putchar`/`strlen`) all run
      natively. Args 1-6 in registers, 7+ on the stack (mixed param frame).
      Output is non-PIC → link `-no-pie`.
    - 18 golden programs in `transpiler/tests/progs/`
  - ✅ 2c: **native x86_64 self-host fixpoint** — `langc -march=x86_64` compiles
    its own source to native x86_64 (`gcc -no-pie`, **no -m32**); stage-2 ≡
    stage-3, byte-identical (even stage-1 ≡ stage-2). `fixpoint.sh x86_64`; CI
    gate. One x86_64-specific subtlety fixed: sign-extend `%eax`→`%rax` after
    `getchar`/`fgetc` only (their `int` result is compared), never after
    pointer-returning calls.
- ✅ `-march=` target selection flag
- ✅ **The compiler self-hosts on both i386 (`-m32`) and x86_64 (native).**

## M3 — Real targets 🟡

- ✅ **x86_64** backend (SysV ABI; 16-byte alignment; varargs `%al`) —
  self-hosts natively, removing the `-m32` dependency.
- ✅ **ARM64** (AArch64) backend — `cd_write_arm64`: `x0` accumulator, `x1` 2nd
  operand, `x9` scratch, `x29`/`x30`/`sp` frame; load/store architecture
  (`ldr`/`str`, `cmp`+`cset`, `adrp`+`add :lo12:` for globals), AAPCS64 calls
  (`bl`/`ret`, args `x0–x5`). The operand stack pushes **16-byte slots** so `sp`
  stays 16-aligned (a new `target.stackslot`, ==wordsize elsewhere). Developed as
  a cross-compiler (validated under qemu-user; native on arm64 CI). Integer/
  pointer only — **FP errors cleanly for now**. **Self-host fixpoint reached**
  (stage-2 ≡ stage-3), so UPLNC now self-hosts on three ISAs (i386, x86_64, arm64)
- ✅ Per-target **fixpoint in CI** — x86_64 native, i386 under `-m32`, arm64 native
- ⏳ ARM64 **floating point** (NEON/`d0`) — the remaining piece for FP parity
- 💭 RISC-V backend (also validates the abstraction on a non-x86 ISA)

## M4 — Floating-point arithmetic ✅

Currently integer-only (`int`/`char`). FP is cross-cutting. Design + slice
breakdown: [`FLOAT.md`](FLOAT.md). **x86_64/SSE2 first, then i386 x87**;
the compiler stays integer-only so the self-host bootstrap is unaffected; float
literals are emitted as `.double <text>` so the assembler computes the IEEE bits
(no float math in the compiler).

- ✅ Design ([`FLOAT.md`](FLOAT.md)) — `%xmm0` FP accumulator, type-routed codegen,
  the slice plan
- ✅ Slice 1: `double` literals + `T_DOUBLE` + `double`→`int` at return
  (`return 42.0;`/`255.9`/`4.2e1` → exit 42/255/42). Literals lex to text and
  emit `.double`; load `movsd .LF<n>(%rip),%xmm0`; `cvttsd2si` at return.
  Both self-host fixpoints still hold; i386 emits a clean "float not supported"
- ✅ Slice 2: `var double:x;` locals (`movsd` load/store), `+ - * /` via the
  xmm push/pop pattern (`fpush`/`fpop`/`addsd`/`subsd`/`mulsd`/`divsd`). Both
  fixpoints hold; mixed int/double errors cleanly (that's slice 3)
- ✅ Slice 3: int↔double conversions / mixed arithmetic — `cvtsi2sd` promotes an
  int operand in mixed `+ - * /` (either side); assignment converts the RHS to
  the target type (`x=5` int→double, `i=1.5` double→int). Both fixpoints hold
- ✅ Slice 4: FP calling convention
  - ✅ 4a: **caller** passes double args in `%xmm0–7` (separate from the integer
    `%rdi–r9` sequence) with `%al` = #vector regs for varargs — enables
    `printf("%f", x)`. Caller counts FP args via `cttype` (a pure, total type
    oracle), 16-byte-aligns, pushes by type, marshals in source order
    (`CD_MARGINT`/`CD_MARGFP`). Both fixpoints byte-identical (the compiler's own
    double-free source is unaffected); 3 `fparg_*` golden tests
  - ✅ 4b: **callee** double params + double return — prologue spills register
    params by SysV class (`CD_SARGFP` from `%xmm`, `CD_SARGINT` from `%rdi…`),
    leaving the all-integer `CD_SPILLARGS` path byte-identical. New optional
    `func f(x:double):double` return-type annotation (default `int`) disambiguates
    a double return from a truncated-to-int literal; `cttype` learns a call's type
    so double-returning calls used as args route through `%xmm`. UPLNC functions
    now take *and* return doubles; 4 `fpparam*`/`fpret*` golden tests; both
    fixpoints byte-identical
- ✅ Slice 5: globals + 4-byte `float`. Global doubles already worked (slice-2
  global opcodes). New `float` (`T_FLOAT`) is a 4-byte *storage* type widened to
  double on load (`cvtss2sd`) and narrowed on store (`cvtsd2ss`+`movss`); since it
  decays to a double in registers, arithmetic/conversions/calls reuse the double
  paths (an `isfp()` helper covers the few spots). Scalar locals + globals only;
  float params/returns are rejected cleanly (single-precision ABI deferred).
  5 golden tests; both fixpoints byte-identical
- ✅ FP arrays + pointer deref (follow-up to slice 5): reading/writing a double or
  float through a pointer or array element now loads into `%xmm0`
  (`movsd`/`cvtss2sd`) and stores from it (`movsd`/`cvtsd2ss`+`movss`) — the
  `loadbyre`/`store` `L_SP` paths gained FP branches. Unlocks `[N]double`/`[N]float`
  arrays and `*double`/`*float`; 5 golden tests; fixpoints byte-identical
- ✅ Slice 6: i386 x87 — floating point on the 32-bit target via the x87 FPU
  stack. `st(0)` is the accumulator (loads push, stores pop; operands spill to
  the integer stack via `FPUSH`/`FPOP`). `faddp`/`fsubp`/`fmulp`/`fdivp` give
  `left OP right` (GAS reverses `fsub`/`fdiv` vs Intel — verified empirically);
  `double→int` is the control-word truncation dance, `float` is `flds`/`fstps`.
  `run_tests.sh` gained an i386 `-m32` run-correctness section (the i386 backend
  is now *run*, not just fixpoint-checked) — all FP progs match x86_64; both
  fixpoints byte-identical.
- ✅ i386 FP calling convention (follow-up to slice 6): doubles cross i386 cdecl
  calls — the caller pushes a `double` arg as 8 bytes on the stack (`fpush` pops
  `st(0)`), and doubles return in `st(0)` (the callee side already worked from
  slice 4b). Enables `printf("%f")` and double params/returns on i386; the seven
  `fparg_*`/`fpparam*`/`fpret*` progs now run on i386 too (127 tests pass). `float`
  params/returns and FP *method* args remain rejected cleanly. Both fixpoints
  byte-identical
- 💭 64-bit integers (`long long`) — related width work, often wanted alongside

## M5 — Optimization 🟡

The codegen is a naive stack machine (push/pop around every operation). Biggest
wins first:

- 🟡 **Peephole** pass over `scode` (`peephole()` in `codegen.e`, run from
  `cg_print` before lowering, so it is target-neutral and both backends + both
  fixpoints benefit). Two rules so far:
  - **A — push/pop elision.** A binary op whose right operand is a single
    accumulator-only load (`CD_LD*`/`CD_LEA`) doesn't need the stack: rewrite
    `PUSH ; load→%rax ; POP` to `MOVAD(%rax→%rdx) ; load`, keeping the left
    operand in `%rdx`. Eliminated **1426** push/pop pairs across the compiler's
    own 5 units (≈2852 fewer memory accesses).
  - **B — dead-code elimination.** Code after an unconditional `RET`/`JUMP` is
    unreachable until the next label — dropped (e.g. the epilogue after a
    trailing `return`).
  - Net: the compiler's own code shrank **37991 → 36043** instructions (−5.1%);
    120 run-correctness tests pass on both targets and both fixpoints stay
    byte-for-byte self-reproducing (the optimizer changes output, so this is the
    real gate). Eliminated items become `CD_IGNORE`, so a single forward pass
    over a stable-index buffer suffices.
- ⏳ Further peepholes: fold `load→%rax ; MOVAD` into a direct load to `%rdx`;
  combine adjacent stack adjustments; redundant `mov` elimination
- ⏳ **Constant folding** in the expression tree
- ⏳ Light **register allocation** — use the register file instead of spilling
  every temporary to the stack
- 💭 A cleaner optimizer IR (basic blocks; later SSA) if warranted

## M6 — Toward real-world usability ⏳

What turns a teaching compiler into something you'd build a project with:

- ⏳ **Diagnostics**: line/column in errors, error recovery (not stop-on-first),
  warnings
- ⏳ A small **standard library** (instead of calling libc via bare `extern`s)
- ⏳ **Debug info** (DWARF) so `gdb` works
- ✅ ternary `?:` operator (was parsed but "to be implemented"; now codegen'd
  via `ct_COND`, dogfooded in the compiler's own source)
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

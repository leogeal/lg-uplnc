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

## M1 — Host portability ✅

Run the compiler on non-x86 CPUs. Cheap, thanks to the portable C seed.

- ✅ `-fsigned-char` in the build (match i386 `char` semantics everywhere)
- ✅ CI job building + testing on **arm64** — the `test-arm64` job runs on a
  native `ubuntu-24.04-arm` runner: builds stage-0 on arm64, runs the suite, and
  the native `fixpoint.sh arm64` (confirmed, not assumed)
- ✅ Verified on **riscv64** — the `fixpoint-riscv64` CI job cross-builds and runs
  the compiler under QEMU (the item's "native runner or QEMU" — QEMU)
- ✅ Host assumptions audited — LP64-vs-ILP32 is proven host-independent by the
  WORDSIZE split + the cross-compile CI job (x86_64 host emits i386), and the
  code's endianness assumptions were shaken out by the big-endian mips64 *target*
  (it surfaced and fixed the char-param spill + data-alignment bugs)
- 💭 Big-endian *host* support (s390x) — only if anyone needs it; distinct from
  the big-endian mips64 *target* above (this is running langc *on* a BE host)

## M2 — Retargetable backend (the seam) ✅

Make output target a pluggable choice instead of hard-wired i386. See
[`RETARGET.md`](RETARGET.md) Part A. *(Merged to `main`; the seam has since
carried four more backends — arm64/riscv64/mips64 in M3, plus FP in M4.)*

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

## M3 — Real targets ✅

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
- ✅ ARM64 **floating point** — `d0` FP accumulator, `d1` 2nd operand;
  `fadd`/`fsub`/`fmul`/`fdiv`, `fcvtzs`/`scvtf` conversions, `ldr`/`str d0` (and
  `s0`+`fcvt` for the 4-byte `float`), AAPCS64 FP calling convention (args in
  `d0–d7`, return in `d0`, **no vector-count register** unlike x86_64's `%al`).
  All 30 FP golden progs run on arm64 (full parity); the fixpoint is unaffected
  (the compiler uses no FP). FP doubles push 16-byte slots like integers
- ✅ **RISC-V (RV64)** backend — `cd_write_riscv`: `a0` accumulator, `a1` 2nd
  operand, `t0`/`t1` scratch, `s0`/`sp`/`ra` frame. **No condition flags** →
  comparisons synthesise 0/1 with `slt`/`sltu`/`seqz`/`snez`/`xori`, and
  `beqz`/`bnez` for test-and-branch; `li` assembles any immediate (so loadimm
  needs no chunking); `div`/`rem` native; globals via `la`; `call`/`ret`. Reuses
  the x86_64 calling convention (`stackslot=8`, 8-byte pushes — RISC-V doesn't
  fault on a misaligned `sp` like AArch64, so the pad-to-16-at-calls logic
  suffices). Integer/pointer only — **FP errors cleanly for now**. **Self-host
  fixpoint reached**: UPLNC now self-hosts on four ISAs (i386, x86_64, arm64,
  riscv64). Validated under qemu-user; CI cross-builds + runs it under qemu
- ✅ Per-target **fixpoint in CI** — x86_64 native, i386 `-m32`, arm64 native,
  riscv64 + mips64 under qemu
- ✅ RISC-V **floating point** (D extension) — `fa0` accumulator, `fa1` 2nd
  operand; `fadd.d`/`fsub.d`/`fmul.d`/`fdiv.d`, `fcvt.l.d`(rtz)/`fcvt.d.l`
  conversions, `fld`/`fsd` (and `flw`+`fcvt.d.s` for the 4-byte `float`). The
  twist: RISC-V passes **variadic FP args in *integer* registers** (what
  `printf` reads), and UPLNC can't see variadic-ness at the call site, so it
  passes *all* FP args as raw bits in `a0–a7` — which means they reuse the
  integer marshaling and the double return stays in `fa0`. This also needed the
  arg-register count to become a target field (`nargreg`: 6 elsewhere, **8** on
  riscv, since FP+int share the registers). All 30 FP progs run on riscv64 (full
  parity); all four fixpoints byte-identical
- ✅ **MIPS64 (N64)** backend — `cd_write_mips`: `$2` accumulator, `$3` 2nd
  operand, `$12`/`$13` scratch, `$fp`/`$sp`/`$ra` frame; **big-endian**, the
  first non-little-endian target (so it also guards endianness assumptions).
  LP64 with `d`-prefixed 64-bit ops (`daddu`/`dsubu`/`dmul`/`ddiv`/`drem`,
  `dsllv`/`dsrav`/`dsrlv`); **no condition flags** → `slt`/`sltu`/`sltiu`/`xori`
  synthesise 0/1 and `beqz`/`bnez` branch; globals via `dla` (full 64-bit
  absolute, non-PIC) and `ld`/`sd`/`lb`/`sb`. Three MIPS-isms, each found by a
  crash the smaller targets never hit: (1) calls go **through `$t9`** (`dla
  $25,f; jalr $25`) because glibc's PIC functions recompute `$gp` from `$t9` — a
  plain `jal` leaves it garbage and e.g. `malloc` then crashes; (2) linking is
  non-PIC with **`-G 0`** (`-mno-abicalls -fno-pic -G 0`) — without `-G 0` gas
  routes small globals through a 16-bit `$gp` window we never set up, which the
  big compiler's globals overflow on a newer linker; (3) **strict alignment** —
  MIPS faults (`SIGBUS`) on an unaligned `ld`/`sd`, but the data layout used the
  i386 4-byte rounding, so 8-byte fields/locals/globals landed 4-aligned. A
  `target.strictalign` flag lays all data out at word alignment on mips (the
  little-endian targets tolerate the misalignment and stay byte-identical). The
  big-endian char-param spill also needed a `target.bigendian` offset shift.
  Reuses the riscv-style calling convention (`stackslot=8`,
  `nargreg=8` for `$a0–$a7`). **Self-host fixpoint reached**: UPLNC now
  self-hosts on five ISAs (i386, x86_64, arm64, riscv64, mips64), and the
  big-endian one is byte-clean too. The growing per-backend mnemonic set also
  pushed `codegen.e` past the 8 KB string-literal pool, so `STSIZE` grew to 16 KB
- ✅ MIPS64 **floating point** (hard-float, N64) — `$f0` accumulator (also the
  double return reg), `$f2` 2nd operand, `$f4` widen/narrow scratch;
  `add.d`/`sub.d`/`mul.d`/`div.d`, `trunc.l.d`+`dmfc1` (double→int),
  `dmtc1`+`cvt.d.l` (int→double), `cvt.d.s`/`cvt.s.d` for the 4-byte `float`,
  `ldc1`/`sdc1` (and `lwc1`/`swc1` + convert). Like riscv, N64 passes variadic
  FP args in *integer* registers, so MIPS reuses the integer marshaling (all FP
  args as bits in `$a0–$a7`); the double return stays in `$f0`. The `.double`
  literal pool gets word-aligned on the strict target so `ldc1` doesn't fault.
  All 30 FP golden progs run on mips64 — full FP parity across all five ISAs,
  validated under a strict (CI-matching qemu 8.2) emulator
- 💭 More targets (s390x/big-endian-host, WASM) only if anyone needs them

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
  - **A/D — push/pop elision + load retarget.** A binary op whose right operand
    is a single accumulator-only load (`CD_LD*`/`CD_LEA`) doesn't need the stack.
    If the *left* operand (just before the `PUSH`) is also a pure load, retarget
    it straight into the 2nd register (set its `reg` field to `RG_D`, honoured by
    every backend via `regnames[reg]`) and drop the `PUSH`/`POP` outright —
    `load X ; PUSH ; load Y ; POP` → `load X→2nd ; load Y`. Otherwise keep the
    left operand with a `MOVAD` copy. The retarget folded **870** load+copy
    sequences (`MOVAD`s 1687 → 817) into single direct loads across the four
    backends' shared IR.
  - **B — dead-code elimination.** Code after an unconditional `RET`/`JUMP` is
    unreachable until the next label — dropped (e.g. the epilogue after a
    trailing `return`).
  - All four self-host fixpoints (x86_64, i386, arm64, riscv64) stay byte-for-byte
    self-reproducing — the optimizer changes output, so the fixpoint + the 235
    run-correctness tests are the gate. (A tried-and-dropped *modstk-coalescing*
    rule was reverted: arm64 rounds each `CD_MODSTK` up to 16 for `sp` alignment,
    so summing args then rounding ≠ rounding each — it broke arm64 self-hosting.)
- ⏳ Further peepholes: redundant `mov` elimination; a modstk-coalescer that is
  safe under arm64's alignment rounding
- ✅ **Constant folding** in the expression tree (`foldtree()` in `langc.e`, run
  on each expression after parsing, before codegen — target-neutral, so all four
  backends emit less code). Collapses a constant *integer* subtree to one `L_NUM`
  literal: `+ - * / % & | ^ << >>`, the comparisons/`&& ||` (→ 0/1), and unary
  `- ~ !`. Never folds float literals (the compiler does no float math) or
  division/remainder by zero. Folds in the host's 64-bit int (exact for the
  64-bit targets; matches i386 for the small constants that occur). All four
  self-host fixpoints stay byte-for-byte; a `const_fold` golden test + 239
  run-correctness checks pass
- 🟡 Light **register allocation** — use the register file instead of spilling
  every temporary to the stack. `regspill()` in `codegen.e` is a target-neutral
  peephole (after the A/D rule): a binary op with a *complex* right operand
  normally spills its left operand to the **memory** operand stack (`PUSH`/`POP`)
  across the right's evaluation; instead it holds it in a free register. Built in
  slices:
  - ✅ **Spill to a register, not memory.** The `PUSH`/`POP` pair becomes a move
    into a free save register, restricted to **call-free spans**: the save
    registers are caller-saved on arm64/riscv/mips, so a `CD_ZCALL` in the span
    reverts that save to memory — and that same invariant means they never need
    prologue save/restore even where they are callee-saved (x86_64 `%rbx`).
  - ✅ **Per-backend save registers** (`target.nsavereg` = how many are free, a
    `savereg()` mapping picks the *i*-th by nesting depth), each chosen clear of
    that backend's scratch so a held save survives every op in its span — three
    deep: `%rbx`/`%r12`/`%r13` (x86_64), `%ebx`/`%esi`/`%edi` (i386 — *not*
    `%ecx`, which shifts/div clobber), `x2`/`x3`/`x4` (arm64), `t1`/`t2`/`t3`
    (riscv), `$14`/`$15`/`$24` (mips). Works on all **five** ISAs.
  - ✅ **Operate directly on the save register** (`target.directop` + an `r2nd()`
    helper in the op lowerings): the op reads its 2nd operand straight from the
    save register, so the spill→`RG_D` move is dropped — 562 of 612 register-held
    spills on x86_64/arm64 (the rest feed a pointer store and keep the move).
  - ✅ **Three-deep nesting.** Saves up to two levels deep stay in registers
    (the third register, `RG_E`); deeper spills still go to memory, but those are
    rare (only 16 depth-2 spills in the whole compiler, so a 4th register would
    add little).
  - ✅ **Promote locals to registers (leaf functions).** A non-address-taken
    word-size scalar local in a function that makes no call lives in a free
    caller-saved register for its whole lifetime instead of the frame — no
    save/restore needed (no call to clobber it, and the caller doesn't expect a
    caller-saved register preserved). The front-end marks candidates (`CD_LOCAL`);
    `promote_locals()` keeps the ones never address-taken (no `CD_LEA` at that
    offset) and rewrites their `CD_LDLW`/`CD_STLW` to register moves. Two regs
    (`RG_L0`/`RG_L1`): `%r10`/`%r11` (x86_64), `x11`/`x12` (arm64), `t4`/`t5`
    (riscv); i386/mips have none free (`nlocalreg=0`, a no-op there). −48 of the
    compiler's own frame loads/stores on x86_64.
  - Result so far: ~12% of operand-stack spills avoid memory and leaf-local
    promotion trims frame traffic; all five self-host fixpoints stay byte-identical.
  - ⏳ Still open: non-leaf functions need callee-saved registers + prologue/
    epilogue save/restore (and frame-slot reservation) to promote locals — the
    bigger structural piece, deferred for its frame-layout risk
- 💭 A cleaner optimizer IR (basic blocks; later SSA) if warranted

## M6 — Toward real-world usability ⏳

What turns a teaching compiler into something you'd build a project with:

- ⏳ **Diagnostics**: line/column in errors, error recovery (not stop-on-first),
  warnings
- ⏳ A small **standard library** (instead of calling libc via bare `extern`s)
- ⏳ **Debug info** (DWARF) so `gdb` works
- ✅ ternary `?:` operator (was parsed but "to be implemented"; now codegen'd
  via `ct_COND`, dogfooded in the compiler's own source)
- 🟡 Language gaps:
  - ✅ `enum { NAME [= constexpr], ... };` — named integer constants, values
    running from 0 or a last-set value, with constant-expression values
    (including prior enum constants). Parsed by `doenum()`; a reference folds to
    an `L_NUM` literal in `primary()`, so enum constants work anywhere an int
    does, including array dimensions. The compiler uses none, so the self-host
    fixpoints stay byte-identical
  - ✅ `switch(expr){ case C: … break; … default: … }` — full C semantics
    including fall-through, stacked cases, `default` anywhere, and `break`.
    `doswitch()` evaluates the value once into a temp frame slot, then a
    dispatch-first layout compares it against each constant-expression case label
    (enum constants work as labels) and jumps to the matching body. `break` uses
    the existing loop queue (so it exits only the switch); `continue` targets the
    enclosing loop. Target-neutral (reuses the ordinary `==`/jump IR), so all five
    backends and the byte-identical fixpoints come for free
  - ✅ Pointer/char **return types are type-correct at the call site** —
    `ct_FUNC` now propagates the callee's declared return type to the call
    expression (matching `cttype`, which already did), so `*f()`, `f()[i]`,
    `f()+n` and `f()->m` work on a call result. Previously every non-`double`
    return collapsed to `int`. The compiler declares no return types, so the
    fixpoints are byte-identical
  - ✅ Whole-struct **assignment** `s1 = s2` (M6 2a) — `ct_structasgn` copies a
    struct by value between named struct variables (and struct sub-fields, any
    nesting) word-by-word via the existing `getmem`/`store` at incrementing
    offsets, so no new opcode and every backend gets it. Through-pointer struct
    operands error cleanly (not yet supported). The compiler uses no struct
    assignment, so the fixpoints stay byte-identical. This is the copy foundation
    for struct return.
  - ✅ struct **return by value** (M6 2b) — a `:Struct` function takes a hidden
    sret pointer as its *last* parameter (so it slots in after the explicit params
    and lands in the last argument register); `doreturn` copies the result through
    it (`copystructp`). At the call site `s = f(...)` routes the call's sret to
    `&s` (no temporary, no second copy), via a `g_sretp` hand-off into `ct_FUNC`,
    which pushes `&s` first so it maps to that last parameter. Reuses the ordinary
    argument marshaling, so all five backends work. Capture is by direct
    assignment (`s = f()`, incl. sub-fields and nested struct-returning functions);
    the returned value must be a named struct (not `return *p`), and on the
    register targets the explicit args must leave a free register for the sret
    pointer (i386 has no such limit). Other uses (`f().m`, struct-by-value args,
    FP args alongside, `return f()`) error cleanly rather than miscompiling. The
    compiler returns no structs, so the fixpoints stay byte-identical
  - ⏳ `unsigned` types, robust function pointers, proper varargs, `const`;
    struct-return follow-ups (`f().m`, struct-by-value args)
- ⏳ A written **language specification** (the paper is the only spec today)
- ⏳ Tooling: a real driver (replacing `langdrv.pl`), a formatter, editor support
- 💭 Module/namespace system; package layout
- 🟡 Robustness: the original compiler can loop on malformed input — add limits /
  graceful errors. One instance fixed: a non-constant array dimension used to
  spin forever (`number()` not consuming the bad token); the `enum` work routed
  array dimensions through `constexpr()`, which consumes its tokens and reports a
  clean error. Other malformed-input loops remain

## M7 — Proof it's real 🟡

- 🟡 Port a few non-trivial programs; build a small self-contained utility in UPLNC
  - ✅ `examples/wc.e` — a faithful `wc` (lines/words/chars from stdin) written
    in UPLNC. Exercises `getchar`/EOF, a whitespace state machine, and `printf`
  - ✅ `examples/cat.e` — `cat` taking file arguments (`main(argc,argv)`,
    `fopen`/`fgetc`/`fclose`, `stderr`, exit status; `-`/no-args read stdin)
  - Both build with the stage-0 tools and run on all **five** backends matching
    the system tools; gated by `run_tests.sh` section `[11]`
  - ⏳ More / larger programs to keep surfacing real language and usability gaps
- 💭 A test/benchmark suite of UPLNC programs with expected output
- ✅ Re-host: a `langc` that runs natively on arm64 *and* targets arm64,
  fixpoint-clean — achieved via the M3 arm64 backend + the host-portability CI.
  The `test-arm64` job (native `ubuntu-24.04-arm` runner) builds stage-0 with the
  host `gcc` (a native arm64 binary) and runs `./fixpoint.sh arm64`, which on an
  `aarch64` host links with the native `gcc` (no qemu): the langc-produced
  `langc1`/`langc2` run natively and reproduce their own arm64 assembly
  byte-for-byte. Gated every CI run

---

### Suggested order

`M1` (cheap, in flight) → `M2` seam → `M3` x86_64 (drops `-m32`) → then parallel
tracks: more targets/hosts, `M4` floating point, `M5` optimization, with `M6`
usability work threaded throughout. The self-host **fixpoint** remains the
non-negotiable acceptance gate at every step.

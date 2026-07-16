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
- ✅ FP in boolean/relational/unary contexts (audit follow-up): M4 wired FP
  *values* (arithmetic, load/store, return, args) but every boolean/unary path
  still operated on the integer accumulator — a silent wrong result on all five
  backends. Now `< > <= >= == !=`, `if`/`while`/`for` and `?:` truthiness,
  `! && ||`, unary `-`, `++`/`--`, and the mixed-type `?:` result class all
  consult `isfp()`: new `CD_FCMP`/`FBOOL`/`FNEG`/`FINC`/`FDEC` (+ i386-only
  `FDUP` so the popping x87 store keeps the value) and an `fcompare()` mirror of
  `fparith()`. Non-FP paths are byte-identical, so all five fixpoints hold;
  `fp_cmp`/`fp_bool`/`fp_neg`/`fp_incdec`/`fp_ternary` golden tests
- ✅ NaN- and unsigned-complete (follow-up): FP is now IEEE- and sign-correct.
  Unordered comparisons match C — `!=` is true on NaN, the ordered compares are
  false, and a NaN is truthy — via `setp`/`setnp` masks (x86), a `vc` (ordered)
  mask on arm64 `<`/`<=`, and ordered mips predicates (`feq/flt/fle` on RISC-V
  were already NaN-safe). An unsigned value with the high bit set promotes to its
  large positive double, not signed −1: new `CD_U2F`/`U2F1` routed by `fpconv()`
  (`ucvtf` on arm64, `fcvt.d.lu` on RISC-V, the shift-and-double trick on x86_64,
  `fildll` of a zero-extended word on i386, the same trick on mips). Nested `?:`
  type propagation fixed in `cttype`. `fp_ternary_nested`/`fp_nan`/`fp_uint`
  golden tests on all five backends; fixpoints byte-identical
- ✅ 64-bit integers (`long long`) — done; see the dedicated section below

## M4B — 64-bit integers (`long long`) ✅

A guaranteed-64-bit integer type — `long long` / `unsigned long long`
(`T_LLONG`/`T_ULLONG`, both 8 bytes). On x86_64/arm64/riscv/mips `int` is already
64-bit (`target.wordsize`==8), so `long long` reuses the word codegen there; on
i386 (32-bit word) it is a genuine 64-bit type built from `%edx:%eax` register
pairs. Every 64-bit-specific i386 path is gated behind
`ll32(t)` = `target.arch==ARCH_I386 && is64(t)`, and the i386-only `CD_*64`
opcodes are lowered only in `cd_write_i386`, so the four 64-bit backends stay
byte-identical and all five self-host fixpoints reach at every step.

- ✅ Slice 1 — **the four 64-bit backends.** `T_LLONG`/`T_ULLONG` parsed by
  `gettypen` (`long long`, `unsigned long long`; `long`/`unsigned long` alias the
  word int/uint). `is64()`/`isunsigned()` thread through `issigned`, `uresult`
  (propagates 64-bit-ness and unsignedness), `gettsize`, and the word load/store
  gates. On the 64-bit targets `long long` behaves exactly like `int`; i386
  rejected cleanly at this stage. Bumping `F_TYPE` only shifts the compiler's own
  struct type-numbers in debug comments (machine code unchanged), so the fixpoints
  stay byte-identical. (PR #63)
- ✅ i386 slice 2a — **foundations.** 64-bit value in `%edx:%eax`; a binary op's
  left operand stays 8 bytes on the stack and is read with carry/borrow (no scarce
  second register pair). Load/store, load-immediate, add/sub/neg, all six compares
  (signed + unsigned, via `sub`/`sbb` + ZF-free `setcc`; `>`/`<=` swapped;
  `==`/`!=` branch-based), int↔ll conversion, and mixed-width (`ll op int`).
  Multiply/divide/shift still rejected cleanly. (PR #64)
- ✅ i386 slice 2b — **multiply.** Low 64 bits of `A*B` via three 32-bit
  multiplies (`a_lo*b_lo` full 64-bit + the cross terms folded into the high
  word); one `mull` routine serves both signed and unsigned. (PR #65)
- ✅ i386 slice 2c — **divide/modulo** via the libgcc helpers
  (`__divdi3`/`__udivdi3`/`__moddi3`/`__umoddi3`) — what gcc itself emits for i386
  (32-bit x86 has no 64-bit divide). The toolchain links libgcc and the compiler
  never divides 64-bit, so the fixpoints are unaffected; `llong.e` (`* / %`) now
  runs on i386 too. (PR #66)
- ✅ i386 slice 2d — **shifts.** `shld`/`shrd` for the cross-word bits, `testb
  $32` for the count≥32 case; `long long` gets arithmetic right-shift,
  `unsigned long long` logical. Completes every 64-bit *integer* op on i386. (PR #67)
- ✅ i386 slice 2e — **`long long`↔`double`** via x87 (`fildll`/`fistpll`, which
  load/store 64-bit integers directly), plus mixed `ll`/`double` arithmetic (a
  64-bit left operand is pushed 8 bytes and loaded with `fildll` from the stack;
  `wide64` excludes the FP case so mixed ops go through the x87 path). (PR #68)
- ✅ i386 slice 2f — **8-byte function args/returns.** A `long long` argument is
  pushed as 8 bytes across the cdecl boundary (the callee already laid out 8-byte
  param slots) and returned in `%edx:%eax`; a returned `long long` needs the
  `: long long` return annotation (same convention as `: double`). This makes
  `long long` fully first-class on i386, so the harness's i386 "not supported"
  skip is retired and every `long long` test runs on all five backends. (PR #69)
- ✅ i386 `unsigned long long` >= 2^63 → `double` — the last edge, now correct. A
  signed `fildll` reads such a value as `v - 2^64`, so `ull2f`/`ull2f1` add `2^64`
  back when the top bit is set (the exact double `0x43F0000000000000`, pushed as
  bytes so no data-section constant is needed; x87's 80-bit registers make the
  correction exact — no double rounding). i386 now matches the 64-bit backends'
  `u2f`, so `long long` ↔ `double` is fully correct on every backend.
  (`llong_u2f` golden test)
- ✅ i386 remaining edges (PR #72) — bitwise `| ^ &` (word-wise on the 8-byte
  stack operand), truthiness in every boolean context (`if`/`while`/`for`/`do`,
  `&& || !`, `?:` — `testjump64`/`lnot64` OR both halves, so a value with only
  the *high* word set is truthy), `++`/`--` with carry (`adcl`/`sbbl`),
  pointer/array indirection (`*p`, `p[i]` — `LBRW64` loads via `%ecx`; `STOW264`
  reads the pointer from the stack since `%edx` holds the value's high word), and
  return conversions via a unified `convto(dst,src)` helper (also used by
  assign/init/ternary). Extending the `cttype` oracle to propagate 64-bit-ness
  through binary/bitwise/shift/unary/ternary shapes also fixed a latent
  mixed-width stack bug (`int + (ll*ll)` pushed 4 bytes where the 64-bit op
  popped 8). Five golden tests (`llong_bitwise`/`bool`/`ternary`/`indirect`/`ret`);
  all five fixpoints byte-identical.
- ✅ **Wide (64-bit) integer literals** — `x = 10000000000;` used to silently
  truncate to 32 bits on *every* backend: the lexer accumulated into the
  compiler's own int, which is 32-bit in the stage-0 seed (C `int`) and on an
  i386 host. Following the float-literal precedent, a literal that does not fit
  a signed 32-bit int is now kept as *text* (`L_WNUM`, sharing the float pool)
  and the assembler computes the 64-bit value — so it works whatever the
  compiler's own host width: `movabsq $<text>` (x86_64), `ldr =<text>` (arm64),
  `li` (riscv), `dli` (mips), and on i386 a `.LF<i>: .quad <text>` pool entry
  loaded as two words into `%edx:%eax` (typed `long long`). Decimal and hex
  (`0x…`), negatives, and a "too large" diagnostic past 2^63-1 / 16 hex digits;
  8-digit high-bit hex (`0xffffffff`) is now 4294967295 on every target and
  stage — the old accumulate path made it -1 in a 32-bit build but positive in
  a self-hosted 64-bit build (a stage divergence, unified). Wide literals fold
  like floats (i.e. not at all), so the deferred `1<<33` fold-width note is now
  only about *folded expressions*, not literals. lpp1's macro pool grew
  3000→6000 (the compiler's own headers filled it). `llong_lit` golden test on
  all five backends; all five fixpoints byte-identical.

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
  - ✅ **Promote locals in non-leaf functions.** The same safety analysis now
    assigns up to two locals to free callee-saved registers: `%r14`/`%r15`
    (x86_64), `x19`/`x20` (arm64), `s1`/`s2` (riscv), and `$16`/`$17` (mips).
    The late pass reserves one ABI-aligned save area, shifts every negative
    frame-relative IR reference below it, and emits save/restore code around
    every return. i386 remains a no-op because regspill already occupies its
    available callee-saved registers. Recursive and address-taken-local tests
    run on all five targets, and assembly checks pin each promoted register
    class. **Profitability follow-up:** after dead-code elimination, the pass
    counts each candidate's surviving loads/stores and charges one entry save
    plus one restore per surviving return. It ranks candidates by that net
    benefit, independent of declaration order, and leaves break-even or losing
    locals in memory; the zero-save-cost leaf path is unchanged. On the current
    compiler's x86_64 self-output this cuts non-leaf preservation instructions
    from 1,143 to 725 while retaining 1,978 of 2,080 promoted accesses: net
    avoided frame-memory operations rise from 937 to 1,253, and output shrinks
    by 523 assembly lines (10,752 bytes).
  - Result so far: ~12% of operand-stack spills avoid memory, and both leaf and
    non-leaf scalar locals can avoid frame traffic; all five self-host fixpoints
    stay byte-identical.
- 💭 A cleaner optimizer IR (basic blocks; later SSA) if warranted

## M6 — Toward real-world usability ⏳

What turns a teaching compiler into something you'd build a project with:

- 🟡 **Diagnostics**: line-numbered errors ✅ — every langc error now reports
  `<file>:<line>:` (plus the offending line and a caret, which existed), correct
  **across `#include` boundaries**: lpp1 emits classic `# <n> "<file>"` line
  markers at the start of the input, on entering an include, and on returning
  from one; langc's `insline` swallows the markers and resyncs `cline` and a new
  `cfile` from them (input without markers falls back to plain `line N:`).
  lpp1's own errors also carry `<file>:<line>`. The markers are invisible to
  the emitted assembly (not echoed), so clean compiles are unchanged and all
  five fixpoints reach; two harness checks pin the location accuracy inside an
  include and after the resync. **Part 2 — error recovery + warnings ✅**:
  - *Location fidelity fix*: lpp1 collapses a K-line `/* comment */` (or an
    escaped-newline literal) into one output line, drifting every later
    location by K−1 — 312 lines across langc.e. `process()` now emits a resync
    marker whenever `prep()` consumed continuation lines. Found by the new
    unused-variable warnings pointing 97 lines off inside the compiler itself.
  - *Panic-mode recovery*: after any error inside a statement, `compound`
    resyncs at the next `;`/`}` (`syncstmt`), so one mistake yields one
    message — and the parser always makes progress: an unrecognized token or a
    broken local declaration used to **hang** langc (two live loops fixed); a
    broken declarator list now reports exactly one error and bails. Follow-up:
    recovery tracks whether the failed statement already consumed its boundary,
    so it does not discard the next statement; `switch`'s separate statement
    loop uses the same recovery instead of relying on the 30-error cap.
  - *Error flood cap*: 30 errors → "too many errors, giving up", exit 1 — a
    backstop against pathological input and any future recovery loop.
  - *Warnings*: `warning()` mirrors error locations but never fails the
    compile (exit stays 0; the `N warning(s)` summary appears only when
    nonzero, so warning-free compiles stay byte-identical). Two v1 warnings:
    **unused variable** (body locals never referenced; parameters and hidden
    temps exempt; located at the declaration file and line) and **no-effect
    comparison statement** (`x == 5;` — the `==`-vs-`=` typo). Dogfooding them found and
    removed nine dead variables in the compiler's own source; self-compile is
    warning-free. Six harness checks pin recovery, the cap, and both warnings.
  Still open: columns in the caret line are byte-offsets (good enough)
- 🟡 A small **standard library** — v0 started, grown from the M7 dogfooding
  needs: `lib/fmt.e` provides `putf(fmt,...)`, a mini printf (`%d %u %x %c %s
  %%`, space/zero width padding) built on the new varargs (`vastart()`) with
  only libc `putchar` underneath, plus the `putd`/`putu`/`putx`/`putstr`
  building blocks. Callers include declarations from `fmt.he`; `fmt.e` is
  compiled and linked once, so multi-file programs do not get duplicate
  definitions. Quoted lpp1 includes now resolve relative to the including file
  rather than its working directory. v0 limits documented in the header: no
  `%f` (FP varargs are rejected on x86_64/arm64), word-size args (64-bit
  varargs are rejected on i386), and `nargreg`-capped calls on register targets.
  The output contract is pinned byte-for-byte by `examples/fmtdemo.e` in
  `run_tests.sh` `[11]`, and verified byte-identical on all five backends
- ✅ **Debug info** (minimal, source-level) so `gdb` works — `langc -g` (and
  `langdrv.pl -g`) emits GNU-as `.file`/`.loc` directives at statement
  boundaries through a new pass-neutral `CD_LOC` opcode, and the assembler
  builds the DWARF `.debug_line` table from them; `gdb` can then set
  breakpoints by `file:line`, stop with source display, and step line-by-line
  (backtraces already work via frame pointers). One shared lowering serves all
  five backends (identical directive syntax); per-file numbering follows
  `lpp1`'s line markers across `#include`. `-g` provably never changes the
  generated instructions — `run_tests.sh` `[12]` strip-diffs the assembly on
  every backend, checks statement-accurate line numbers, and (host) verifies a
  real gdb `file:line` breakpoint; the compiler compiles its own sources with
  `-g` cleanly under ASan/UBSan/LSan.
  - ✅ **Part 2: CFI unwind + variable/type DIEs** — `gdb` is now fully
    usable. CFI: every backend annotates its own prologue/epilogue
    (`.cfi_def_cfa*`/`.cfi_offset`, callee-saved CSR/promotion saves included);
    mid-function epilogues are bracketed with `remember_state`/`restore_state`
    because the CFI table is address-ordered; directives go to the strippable
    `.debug_frame` (never `.eh_frame`), so the loaded image is unchanged.
    DIEs: hand-written DWARF 4 in `.debug_abbrev`/`.debug_info` via label
    arithmetic (endian-safe — verified on big-endian mips64). One DIE per
    `typtab` entry gives full types: base types, pointers, arrays with counts,
    and structs **with members**, so `print p`, `p.x + p.y`, `info locals`,
    and `ptype` all work; params and memory-resident locals get
    `DW_OP_fbreg` locations (post-promotion-shift offsets), including explicit
    parameter tags for stack-passed arguments; variadic functions retain their
    `...`. Register-promoted locals honestly report `<optimized out>`, globals
    use relocatable `DW_OP_addr` locations (including global-only units), and
    block-scoped locals are harvested at scope exit (`ssymtabcut`) so they
    appear too. The CU's
    `stmt_list` uses the label-in-`.debug_line` idiom, so multi-unit `-g`
    links resolve each unit's line table (verified: two-unit program, both
    CUs correct, cross-unit `bt` shows parameter values). The fuzz harness
    now runs langc with `-g`, so the debug emitters face malformed input in
    CI too; the strip-diff `[12]` equality gate covers the new output on all
    five backends. Remaining ideas: lexical-block scoping for shadowed block
    locals, and location lists for promoted locals
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
  - ✅ `unsigned` int (M6) — a new `T_UINT` base type (`var unsigned:x`).
    `issigned()` is false for it, so comparisons already route to the unsigned
    variants; `>>` uses a logical shift (the `CD_SHR` opcode was lowered on every
    backend but never emitted); arithmetic propagates unsignedness (`uresult`) so
    nested expressions stay unsigned. Unsigned `/` and `%` use new `CD_UDIV2REGS`
    / `CD_UMOD2REGS` opcodes lowered per backend (`divq`+zeroed `rdx`, `udiv`,
    `divu`/`remu`, `ddivu`/`dremu`), mirroring the signed division. Adding the
    base type bumped `F_TYPE`, shifting the compiler's own struct type-numbers,
    so the self-host output differs from the pre-`unsigned` `main` only in
    vestigial `typptr=` debug comments (the machine code is unchanged); every
    later change, including the div/mod opcodes, is byte-identical again. The
    compiler uses no unsigned, so all five fixpoints reach.
  - 🟡 `const` + variable initializers (M6). Local initializers landed:
    `var TYPE:name = expr;` emits a direct store at the declaration point (UPLNC
    had no initializer syntax before this). `const` (a `cnst` flag on `ssym`,
    added at the struct's end so only `sizeof` moves) is enforced in `ct_ASSIGN`
    and `++`/`--` for a by-name `L_ID` target -- so a `const` local is initialized
    once and then immutable, while a write *through* a const pointer (`*p = x`,
    `L_POI`) is still allowed. The compiler declares no `const`, so all five
    fixpoints reach (the self-output differs from the prior `main` only in a few
    `calloc(sizeof(ssym...))` size constants).
  - ✅ **Global variable initializers + usable global `const`** —
    `var TYPE:name = constexpr;` at file scope lays the value down statically:
    `dumpglbs` emits the variable into `.data` instead of `.comm` — or into
    **`.rodata` when it is `const`**, so a stray write through a pointer faults
    instead of corrupting silently (the compile-time `cnst` check already covered
    by-name writes). The initializer must fold to a constant leaf: an integer
    (`GI_VAL`, emitted `.byte`/`.long`/`.quad` by type), a wide 64-bit literal
    (`GI_WIDE`, `.quad <text>` — the assembler computes it), or a float literal
    (`GI_FLT`, `.double`/`.float <text>`); a unary minus on a float literal is
    folded textually (foldtree never folds FP). Same last-declarator rule as
    locals; extern+initializer, non-constant expressions, wide-on-32-bit-int and
    float/int mismatches all diagnose cleanly. The kind lives in a new
    `ssym.ginit` field (value/pool-index in `sym.offset`), so like the `cnst`
    field only the `calloc` size constants move — all five fixpoints reach.
    `globinit` golden test on all five backends.
  - ✅ **Name-first initializers** — `var name:TYPE = expr;` now takes an
    initializer too (locals and globals), closing the asymmetry with the
    type-first form: after `gettypen()` the parser accepts `=` where it used to
    demand `;`, and the existing shared init machinery (runtime store for
    locals, constant `.data`/`.rodata` emission for globals, last-declarator
    rule, `const` enforcement) does the rest. `init_namefirst` golden test on
    all five backends.
  - ✅ **Function pointers** — a bare function name (or `&f`) is now a value:
    its address, loaded like a global's (`CD_LDA`). Any expression can be
    *called*: variables, parameters (callbacks — `apply(f,x){return f(x);}`),
    dispatch-table elements (`tab[i](x)`); the postfix-`(` grammar already
    parsed these, so the work was `ct_FUNC`'s indirect branch + one `CD_ICALL`
    opcode. The callee address is evaluated first and pushed as the deepest
    stack slot — *below* the args, so the existing marshal offsets are unchanged
    — then `CD_ICALL` loads it into a per-backend scratch register and calls
    through it: `call *%r11` (x86_64, `%al`=0), `call *%ecx` (i386 cdecl),
    `blr x9` (arm64), `jalr t0` (riscv), and `jalr $25` on mips — which is
    exactly the `$t9` PIC convention that target already requires for direct
    calls. Indirect calls take int/pointer args and return int/pointer;
    FP args, more than `nargreg` args, and double returns through a pointer
    error cleanly. `fnptr`/`fnptr_nest` golden tests (calls through variables,
    `&f`, callbacks, composition `f(g(x))`, dispatch tables) on all five
    backends; all five fixpoints byte-identical. Follow-up (PR #79): the two
    span-based optimizer passes only knew `CD_ZCALL` as a call boundary —
    `promote_locals` kept a local in a caller-saved register across an indirect
    call (clobbered by the callee), and `regspill` register-held the callee-
    address PUSH (no matching POP), mispairing it with a later operand POP so
    the indirect call jumped through garbage (SIGSEGV). Both passes now treat
    `CD_ICALL` like `CD_ZCALL`; `fnptr_promote`/`fnptr_spill` regression tests.
  - ✅ **Variadic functions** — `func f(a:int,...)` can now be *defined*, not
    just called: `vastart()` in the body yields a `*int` to the first variadic
    argument, and the varargs are word-size values at `p[0]`, `p[1]`, ....
    The caller needs no special convention — UPLNC's marshal is position-based
    and already matches the variadic ABI everywhere (riscv/mips pass everything
    variadic-style, x86_64 sets `%al`, i386 is cdecl) — so the whole feature is
    callee-side: the prologue spills the *remaining* argument registers just
    below the named params in reverse register order, making the tail
    contiguous and upward-walkable (`CD_SARGINT`, newly lowered on riscv/mips
    too); on i386 the caller's cdecl stack already *is* the va area
    (`vastart() = fp+8+argstk`, no prologue cost). Works with zero named
    params (`func f(...)`), non-leaf variadic functions, pointer varargs, and
    forward declarations. Errors cleanly: `vastart()` outside a variadic
    function, params after `...`, FP named params, and ≥`nargreg` named params
    on the register targets (the tail must be all-register to be contiguous;
    variadic *calls* are likewise capped there). Follow-up: function symbols now
    remember `isva`/`nfixed`, so direct calls to known UPLNC variadic functions
    reject spilled register-target varargs and FP varargs on x86_64/arm64
    cleanly instead of reading the wrong frame/register area. `varargs` golden
    test plus diagnostics on all five backends; all five fixpoints byte-identical.
  - ✅ **`const` parameters + `unsigned char`** — the last two small gaps.
    `func f(const a:int)` marks the parameter's symbol `cnst`, so the existing
    enforcement rejects assignment and `++`/`--` in the body (both declaration
    forms). `unsigned char` (`T_UCHAR`) is byte storage **zero-extended on
    load** — new `CD_LDBU`/`CD_LDLBU`/`CD_LBRBU` opcodes lowered on all five
    backends (`movzbq`/`movzbl`, `ldrb`, `lbu`) beside the sign-extending
    char forms; stores share the byte-store path. Like C, it *promotes to a
    signed word* (values 0..255), so `issigned()` includes it and compares/
    shifts/division use the signed forms — `u > s` with `s:char = 200` is
    200 > −56, not an unsigned surprise. One genuine big-endian catch: a
    byte-typed initialized global must emit `.byte`, not `.quad` — on mips the
    value would land at the wrong end of the symbol (little-endian targets
    passed by luck). `uchar` golden test + const-param harness checks on all
    five backends; all five fixpoints reach (the `F_TYPE` bump only shifts
    debug-comment type numbers, per precedent). Follow-up (PR #83): byte
    conversions previously happened only at store+reload, but function
    *returns* and assignment-*expression* values hand the value over in the
    accumulator — `return 300` from a `:unsigned char` function yielded 300,
    and `(u=300)==44` was false. `convto` now emits a `CD_BYTECONV`
    (sign/zero-extend the low byte, per the destination's signedness) for
    byte-typed destinations, lowered on all five backends; it layers after the
    fp/ll conversions, so `double → char` returns narrow correctly too.
    `byte_ret` golden test.
  - ✅ **Struct-return follow-ups** — an *uncaptured* struct-returning call now
    materializes its result into a hidden frame temporary and the call
    expression becomes that temp: an ordinary named struct lvalue. So `f().m`
    (and nested `f().sub.m`), `s = f().sub`, **`return f()`** (chained struct
    returns), a struct call as an *argument*, and a discarded `f();` all work
    through the existing struct machinery; `s = f()` keeps its direct-sret fast
    path (no temp, no copy). Key subtlety: the temps are **pre-allocated at
    statement level** (`prestemps` walks the expression tree after `foldtree`,
    stashing each temp on its `OP_FUNC` node) — allocating mid-expression would
    move `sp` under a pushed operand and the later pop would grab the temp
    (found by a two-calls-in-one-expression stress test). Temps release at
    block exit, so loops reuse the slot (million-iteration test, no frame
    leak). Struct *values* in argument position decay to a pointer to the
    temp — like C arrays — so callees take `*Struct` params (`p->m`); true
    struct-by-value *parameters* remain unsupported (the callee-side copy
    convention is a separate piece). `struct_use`/`struct_temp` golden tests
    on all five backends; all five fixpoints byte-identical.
  - 💭 **True struct-by-value parameters** — assessed 2026-07; *deliberately
    deferred*, and since the review of PR #86 the syntax is **rejected** rather
    than accepted-and-miscompiled: `dofunc` errors on struct (and array)
    parameters — previously `func f(p:pair)` compiled, laid the param out by
    value, and read garbage against the caller's decayed pointer (found by the
    other agent's review; two harness rejection checks pin it). Not needed for
    expressiveness: `var t:S; t = s; g(&t);` already expresses a copy, the
    compiler's own source never wants it, and none of the libc calls this
    project uses takes a struct by value. It would buy aliasing safety (today a
    named struct passed as an argument gives the callee a live reference —
    `p->` writes mutate the caller's struct, which surprises C-trained readers,
    while a call-result argument mutates only its discarded temp). If/when real
    programs keep wanting it (the M7 dogfooding is the forcing function), build
    the **callee-side-copy design**: keep the wire format a pointer exactly as
    today, and have a struct-typed (or `byval`-marked, avoiding any silent
    semantics change) parameter allocate a frame-local copy filled by a
    `copystructp`-style prologue copy, its symbol bound to the copy — zero ABI
    change, zero caller-side knowledge (so it composes with indirect calls and
    declaration-order freedom automatically). The work centers on `dofunc`
    (param slot handling, local allocation, symbol rebinding, the copy) plus
    tests — modest, but not a one-liner; and it always copies through memory,
    which C ABIs avoid for small structs (registers), so the cost is
    C-*like*, not identical. Do **not** build the C-style
    caller-side SysV classification ABI (per-eightbyte register classing):
    it breaks the one-word-per-position marshal, needs per-target work,
    collides with single-pass compilation (a call before the declaration
    would silently miscompile — the varargs PR #81 hazard class with worse
    failure modes), is unsolvable for indirect calls (function pointers carry
    no signature), and multiplies against varargs/sret/FP-args/methods — all
    for interop UPLNC does not need. Revisit only if C-ABI struct interop with
    external libraries becomes a goal, as its own milestone.
- ✅ A written **language specification v0** — [`LANGUAGE.md`](LANGUAGE.md)
  defines the current preprocessor and lexical rules, prefix type grammar,
  target data models, declarations, functions and methods, control flow,
  expression precedence, conversions, structure semantics, separate
  compilation, undefined behavior, implementation limits, and unsupported C
  constructs. It is derived from `langc`/`lpp1` plus the tested corpus rather
  than treating the historical paper or bootstrap subset as the current
  contract; a canonical fixture compiles on all five targets and runs as
  expected on x86_64.
- 🟡 Tooling: **real compiler driver ✅** — `langdrv.pl` now provides a quiet,
  target-aware CLI with `-march`, `-o`, `-S`, `-c`, and `-v`; accepts multiple
  `.e`/`.s`/`.o` inputs; uses collision-free temporary intermediates; preserves
  frontend and linker failures; handles paths with spaces without a shell; and
  selects the established assembler/linker and ABI flags for all five targets.
  Tool paths are discoverable relative to the repository and overridable by
  flags or environment. The test suite builds examples through the driver and
  pins separate compilation, multi-file linking, quiet/verbose behavior, error
  propagation, and path safety. Still open: a formatter and editor support
- 💭 Module/namespace system; package layout
- ✅ Robustness: the original compiler can loop or corrupt memory on malformed
  input — add limits / graceful errors. Fixed so far: non-constant array
  dimensions route through `constexpr()` instead of spinning; overlong numeric
  literals, method names, identifiers, string literal pools, and float literal
  pools now diagnose instead of overflowing or silently truncating; `lpp1` now
  returns nonzero on preprocessing errors and guards overlong source lines; the
  statement parser recovers at `;`/`}` instead of looping on unrecognized
  tokens or broken declarations (two hangs fixed), and an error-flood cap (30)
  backstops anything that still spins while emitting errors.
  - ✅ A **deliberate sanitizer + fuzzing pass** (`transpiler/sanitize.sh`,
    `transpiler/fuzz/`): builds ASan+UBSan-instrumented `lpp1`/`langc` and runs
    a deterministic, seeded mutation fuzzer over a seed corpus (plus every
    `tests/progs` program) into both tools; a CI job (`sanitize-fuzz`) runs it
    on every push. The pass found and fixed seven real defects the happy-path
    suite never caught (it does not run under sanitizers). Five are on
    error-recovery paths: a signed-overflow while scanning wide integer literals
    (`number`); folding an out-of-range shift count (`foldtree`); an
    uninitialised result `elval` that let a garbage type index `typtab` out of
    bounds after a codegen error (`treetocode` — the general fix, since every
    `ct_` handler shares that lval); a null-child walk on a binary operator
    missing its right operand (`ct_LOR`/`ct_LAND`); and a write through an unset
    symbol pointer when a global initializer had no valid name (`doginit`). Two
    are memory leaks on *well-formed* programs: a name-list head node never
    freed by its owner (`snamelist.done`), and each block scope's per-symbol
    name list dropped on scope exit (`ssymtabcut`). Minimised repros live in
    `fuzz/corpus/recovery-crashes.e`; ~240k mutated cases run clean under
    ASan+UBSan, and the leak-detecting CI configuration is clean too. Review
    follow-up completed the fold fix with checked 32-bit add/subtract/multiply,
    divide/remainder, negation, and left shift; fixed `INT_MIN` assembly-text
    emission; and made LeakSanitizer/runtime failures unambiguously fail the
    harness. `fold_overflow.e` runs the target-width behavior on all five
    backends and is also a sanitizer seed.

## M7 — Proof it's real 🟡

- 🟡 Port a few non-trivial programs; build a small self-contained utility in UPLNC
  - ✅ `examples/wc.e` — a faithful `wc` (lines/words/chars from stdin) written
    in UPLNC. Exercises `getchar`/EOF, a whitespace state machine, and `printf`
  - ✅ `examples/cat.e` — `cat` taking file arguments (`main(argc,argv)`,
    `fopen`/`fgetc`/`fclose`, `stderr`, exit status; `-`/no-args read stdin)
  - ✅ `examples/fmtdemo.e` — exercises every `lib/fmt.e` format feature and
    prints the library's fixed output contract (diffed byte-for-byte in `[11]`)
  - ✅ `examples/hexdump.e` — an `od`-lite (offset + 16 hex bytes + ASCII
    column) built on `lib/fmt.e`: dogfoods **varargs** (`putf`), `%08x`/`%02x`
    padding, byte handling and array-decay argument passing, in one real
    utility
  - ✅ `examples/grep.e` + `grep_match.e/.he` — the first substantial
    **multi-file utility** built by the real driver. Supports multiple files,
    stdin, `-n`/`-i`/`-v`, conventional 0/1/2 statuses, and a documented regex
    subset (literal/`.`/`^`/`$`/`*`/escaping). Pattern/line limits diagnose
    instead of truncating, and a work budget bounds pathological backtracking.
  - ✅ `examples/sort.e` + `sort_lines.e/.he` + `sort_order.e/.he` — a
    three-unit stable text sort and the first utility to own a substantial
    dynamic data set. The input unit grows both line buffers and a heap array of
    owned line pointers (with complete teardown and explicit limits of 1 MiB
    per line and 262,144 lines); the ordering unit implements bottom-up stable
    mergesort and invokes a comparator callback passed across object boundaries.
    The CLI supports multiple files/stdin, `-f` ASCII folding, `-r`, `-u`,
    combined options, and `--`; it reports conventional status 2 on input,
    output, allocation, limit, or embedded-NUL errors. Differential tests use
    `LC_ALL=C sort` as the oracle, including stable folded ordering, uniqueness,
    dynamic growth, unsigned non-ASCII bytes, and unterminated final lines.
  - All build with the stage-0 tools; wc/cat/grep/sort run on all **five**
    backends (grep's matcher and sort's three units are separately linked per
    target), while fmtdemo/hexdump print byte-identical output on all five.
    Native grep/sort tests compare supported behavior with the system tools and
    pin options, file/error statuses, escaping, resource limits, dynamic
    storage, and text edge cases; gated by `run_tests.sh` `[11]`
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

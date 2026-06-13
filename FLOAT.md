# M4 — floating point: design

Plan for adding floating-point arithmetic to UPLNC. Status/tracking lives in
[`ROADMAP.md`](ROADMAP.md); this is the design and slice breakdown.

## Scope decisions

- **x86_64 / SSE2 first.** Doubles live in `%xmm` registers; arithmetic is
  `addsd`/`subsd`/`mulsd`/`divsd`. i386's x87 FPU stack is painful and is
  **deferred** — on i386 the FP paths emit a clean "float not supported on
  i386 yet" error.
- **`double` first** (8 bytes). `float` (4 bytes, `movss`/`cvtss2sd`) is a later
  slice.
- **The compiler stays integer-only.** It never does float arithmetic itself, so
  the **self-host bootstrap is unaffected** (the FP codegen paths simply go
  unexercised when compiling the float-free compiler — i386 and x86_64 self-host
  exactly as before).

## The key trick: the assembler computes the bits

The integer-only compiler can't evaluate `1.5` into IEEE-754. It doesn't need to:
it stores the literal **as text** and emits `.double 1.5` into `.rodata`, letting
**gas** compute the bit pattern. The compiler only ever copies/loads 8-byte
blobs. So float literals need a text pool, not float math.

## Codegen model (x86_64)

- **FP accumulator = `%xmm0`** (parallel to the integer accumulator `%rax`).
- **FP temporaries** spill to the stack: `subq $8,%rsp; movsd %xmm0,(%rsp)` /
  `movsd (%rsp),%xmm1; addq $8,%rsp` (mirrors the integer push/pop).
- **Load/store** doubles with `movsd` (local: `n(%rbp)`, global: `sym`, literal:
  `.LFn` in `.rodata`).
- **Conversions**: `cvttsd2si %xmm0,%rax` (double→int), `cvtsi2sd %rax,%xmm0`
  (int→double).
- **Compare**: `ucomisd` + `setcc` (+ unordered handling later).

Codegen is **type-routed**: the existing dispatch points (`getmem`, the store
paths, `loadnum`, the `ct_*` binary-op handlers, `return`) gain a `T_DOUBLE`
branch that emits the FP form. New `CD_*` opcodes carry the FP operations; only
`cd_write_x86_64` lowers them (i386 errors).

## Calling convention (SysV, later slice)

Doubles are passed in `%xmm0–7` (a separate sequence from the integer
`%rdi–r9`), the return value is in `%xmm0`, and a variadic call (`printf("%f")`)
must set `%al` = number of vector registers used. This extends the marshaling
(`CD_MARSHAL`/`CD_SPILLARGS`) with a parallel xmm track — it is the trickiest
slice and is sequenced after scalar FP works.

## Slices (each verified; i386 self-host stays byte-identical throughout)

1. **Literal → int.** Lex `double` literals; add `T_DOUBLE`; load a double
   literal into `%xmm0`; convert to int at a return. Test: `return 42.0;` → exit
   42. *(This slice — the minimal end-to-end path.)*
2. **Locals + arithmetic.** `var double:x;` load/store (`movsd`); `+ - * /` via
   the xmm push/pop pattern; double→int return. Test: `x=20.0+22.0; return x;`.
3. **Conversions + mixed.** int↔double at assignment/return; usual arithmetic
   conversions for `1.5 + 2`.
4. **Calling convention.** Split in two:
   - **4a — caller (done).** Pass double *arguments* in `%xmm0–7` (a separate
     sequence from the integer `%rdi–r9`), set `%al` = number of vector registers
     for variadic callees. Enables `printf("%f", x)`. The caller counts FP args
     via `cttype` (a pure type oracle), pads for 16-byte alignment, pushes each
     arg by type, then marshals to registers walking the int/fp sequences in
     source order (`CD_MARGINT`/`CD_MARGFP`). Verified by stdout *and* by exit
     code (round-trip a double through `sprintf`/`atoi`).
   - **4b — callee + return (done).** Receive double *params* and return a double
     in `%xmm0`, so UPLNC functions take *and* return doubles. The prologue spills
     each register param to its slot by SysV class — doubles from `%xmm0–7`
     (`CD_SARGFP`), ints/ptrs from `%rdi–r9` (`CD_SARGINT`) — keeping the existing
     all-integer `CD_SPILLARGS` path byte-identical. A new optional return-type
     annotation `func f(x:double):double` (default `int`, fully backward-compatible)
     disambiguates "return a double" from "return a double literal truncated to int"
     (which `main` relies on); `cttype` learns that a call yields its callee's type,
     so a double-returning call used as an argument is itself routed through `%xmm`.
5. **Globals + `float` (done).** Global doubles already worked (they fell out of
   the slice-2 global load/store opcodes — `.comm name,8,4`, `movsd name(%rip)`).
   The new piece is the 4-byte **`float`** type (`T_FLOAT`): a *storage* type that
   is widened to a double on load (`cvtss2sd`) and narrowed on store
   (`cvtsd2ss`+`movss`, narrowing into `%xmm1` so the `%xmm0` accumulator is
   preserved for chained assignments). Because a float decays to a double the
   moment it is in a register, all arithmetic, conversions, and the calling
   convention reuse the existing double paths unchanged — `float` awareness is
   confined to the type table, `getmem`/`store`, and an `isfp()` helper used where
   double was special-cased. Single-precision rounding is real (`0.1f` loads back
   as `0.100000001…`). Scope: scalar locals + globals only — `float` *params* and
   *returns* are rejected with a clear error (they need single-precision ABI
   handling).
   - **FP arrays + pointer deref (done, follow-up to 5).** Reading/writing a
     double or float through a pointer or array element used to load the FP bits
     into `%rax` as an integer (`movq off(%rax),%rax`) — or, for `float`, error
     outright — because the deref/index path (`loadbyre`, the `store` `L_SP` case)
     had no FP branch. Now an FP element loads into `%xmm0` (`movsd off(%rax)` /
     `cvtss2sd` widening a float) and stores from `%xmm0` to the popped address in
     `%rdx` (`movsd ->off(%rdx)` / `cvtsd2ss`+`movss` narrowing a float). This
     unlocks `[N]double`/`[N]float` arrays (element stride is the type size — `*8`
     / `*4`) and `*double`/`*float` pointers, including the compact-storage use
     case `float` was added for. Address arithmetic was already correct; only the
     load/store at the deref needed FP awareness.
6. **i386 x87 (done).** Floating point on the 32-bit target via the x87 FPU.
   The flat-register FP IR maps onto the x87 register *stack* with `st(0)` as the
   accumulator (mirroring `%xmm0`): loads push (`fldl`/`flds`), stores pop
   (`fstpl`/`fstps`), and binary-op operands spill to the integer stack via
   `FPUSH`/`FPOP`, so the x87 depth stays ≤ 2 during evaluation and 0 between
   statements. After `FPOP` the stack is `st0=left, st1=right`; the GAS mnemonics
   `faddp`/`fsubp`/`fmulp`/`fdivp` then give `left OP right` — **verified
   empirically**, because GAS reverses `fsub`/`fdiv` operand order vs Intel
   syntax (the `fsubr`/`fdivr` you'd reach for give `right OP left`). `double→int`
   truncation is the control-word dance (save CW, set RC=11/chop, `fistpl`,
   restore); `int↔double` is `fildl`; `float` is just `flds`/`fstps` (the x87
   loads/stores the narrower width directly — no explicit convert). A double is
   8 bytes even though the target word is 4, so `FPUSH` reserves 8 and `Zsp`
   tracks 8. **Scope: scalar only** — the i386 FP *calling convention* (passing
   doubles on the cdecl stack, `st(0)` returns) is not implemented; FP function
   arguments are rejected with a clear error. Both self-host fixpoints stay
   byte-identical (the compiler uses no FP).

## Testing

Scalar slices (1–3) are validated by **exit code** (convert the double result to
int and return it). The calling-convention slice (4) is validated by **stdout**
(`printf("%f", …)`) and — so it gates in the exit-code CI harness — by
round-tripping the formatted double back through `sprintf`/`atoi`
(`fparg_printf`/`fparg_sum`/`fparg_mixed` for 4a). 4b is exit-code-checkable on its
own: a double param truncated to int, mixed int/double params, and a `:double`
return assigned to a double local or fed into another double param
(`fpparam`/`fpparam_mixed`/`fpret`/`fpret_chain`). Slice 5 is exit-code-checkable
too: float store/load truncation, a global float, float arithmetic, int→float
round-trip, and a global double (`float_store`/`float_global`/`float_arith`/
`float_fromint`/`global_double`). The FP array/deref follow-up adds
variable-indexed `[N]double`/`[N]float` read and write and `*double`/`*float`
load/store (`double_array`/`double_array_write`/`double_ptr`/`float_array`/
`float_ptr`). All go in `transpiler/tests/progs/` and run on the x86_64 CI job;
both self-host fixpoints stay byte-identical (the compiler's own source uses no
doubles or floats).

Slice 6 (i386 x87) reuses the **same** exit-code progs: `run_tests.sh` gained an
i386 run-correctness section that compiles every prog with `-march=i386`,
assembles/links/runs it under `-m32`, and checks the exit code — so the i386
backend is finally *run*, not just fixpoint-checked. The scalar FP progs produce
the same exit codes on i386 x87 as on x86_64/SSE2; the seven FP-calling-convention
progs (`fparg_*`/`fpparam*`/`fpret*`) are skipped on i386 by design. The CI test
job installs `gcc-multilib` so this section gates there too.

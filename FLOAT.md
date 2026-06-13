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
5. **Globals + `float`.** global doubles; the 4-byte `float` type.
6. **i386 x87** *(optional)* — only if i386 FP is wanted.

## Testing

Scalar slices (1–3) are validated by **exit code** (convert the double result to
int and return it). The calling-convention slice (4) is validated by **stdout**
(`printf("%f", …)`) and — so it gates in the exit-code CI harness — by
round-tripping the formatted double back through `sprintf`/`atoi`
(`fparg_printf`/`fparg_sum`/`fparg_mixed` for 4a). 4b is exit-code-checkable on its
own: a double param truncated to int, mixed int/double params, and a `:double`
return assigned to a double local or fed into another double param
(`fpparam`/`fpparam_mixed`/`fpret`/`fpret_chain`). All go in
`transpiler/tests/progs/` and run on the x86_64 CI job; both self-host fixpoints
stay byte-identical (the compiler's own source uses no doubles).

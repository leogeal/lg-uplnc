# Phase 2 design note — the backend interface + x86_64

Phase 1 ([`RETARGET-AUDIT.md`](RETARGET-AUDIT.md)) routed every target *datum*
through `struct starget`, proven byte-identical. Phase 2 is the harder half: make
the **instruction lowering** and **calling convention** pluggable per target, then
add an **x86_64** backend behind that seam. This note proposes the interface, the
plan, and how verification evolves. Context: [`RETARGET.md`](RETARGET.md) Part A.

## What Phase 1 already bought us

- The `scode`/`CD_*` IR (~57 opcodes, `codegen.he`) is a reasonable, mostly
  target-neutral boundary: opcodes like `CD_EQ`, `CD_DIV2REGS`, `CD_ADD2REGS` are
  abstract; the x86-isms (flags+`setcc`, the `idiv` dance) live only in the
  *lowering* (`cd_write`), not the IR. So Phase 2 is "two lowerings", not an IR
  redesign.
- **Pointer width comes for free.** Slice 4 made all target sizing read
  `target.wordsize`; an x86_64 backend just sets `wordsize = 8` and the type
  system sizes pointers/offsets at 8 bytes automatically.

## Constraint that shapes everything: no function pointers

UPLNC's `func`/method slots are statically dispatched and are never assigned (we
confirmed this in the bootstrap). The language has no usable function-pointer
values, so a **vtable-style backend interface is not available** without first
adding a language feature (an M6 item). Therefore:

> Backends are selected by an **arch id** in the descriptor (`target.arch`), and
> the lowering is **one function per target**, dispatched at a single point —
> not a table of function pointers.

```
#define ARCH_I386    0
#define ARCH_X86_64  1
/* in starget: int arch; */

func cd_write(this:*scode)        /* dispatch */
{
  if(target.arch==ARCH_X86_64) cd_write_x86_64(this);
  else                          cd_write_i386(this);
}
```

Two ~400-line lowering functions is more code than a parameterized one, but it is
**legible** (each backend reads top-to-bottom) and matches RETARGET.md's
anti-goal of building an instruction selector. Registers/mnemonics/addressing
differ enough that per-target functions beat per-instruction `if(arch)`.

## The backend surface

Each target provides:

| Kind | Item | Today | Phase 2 |
|------|------|-------|---------|
| data | label/sym prefix, directives, **word size** | `starget` ✅ | + `arch`, register names/roles, stack alignment |
| code | **instruction lowering** (the 57 `CD_*`) | `cd_write` (i386, inline) | `cd_write_<arch>` + dispatch |
| code | **calling convention** | `CD_*` sequence from `langc.e` + `cd_write` | see below |

Register roles to capture as data (names already partly in `regnames`):
accumulator/return, second operand, shift-count, byte register, frame & stack
pointers — and, new for SysV, the **argument registers**.

## The calling convention — the real divergence

This is the one place the IR *shape* differs, not just the spelling.

- **i386 cdecl** (today): `langc.e`'s `OP_FUNC` path evaluates each arg and emits
  `CD_PUSH`; after `CD_ZCALL` the caller cleans with `CD_MODSTK(nargs)`. Result in
  the accumulator. The convention is encoded as a *sequence of `CD_*` opcodes*.
- **x86_64 SysV**: first six int/pointer args in `rdi,rsi,rdx,rcx,r8,r9`; caller
  cleans nothing for register args; **`%rsp` must be 16-byte aligned at the
  `call`**; variadic callees (it calls `printf`/`fprintf` heavily) need `%al = 0`.

Recommended bounded approach — **keep the IR sequence target-neutral, localize the
convention in the backend**:

1. `langc.e` keeps evaluating args and emitting `CD_PUSH` (neutral), and emits the
   call opcode carrying the **arg count** (extend `CD_ZCALL`'s `arg` field, which
   is currently unused for calls).
2. `cd_write_i386(CD_ZCALL)` → `call name` (unchanged; the existing `CD_MODSTK`
   still cleans).
3. `cd_write_x86_64(CD_ZCALL)` → pop the N pushed args into the SysV registers in
   the correct order, fix 16-byte alignment, zero `%al`, `call`. (No caller
   cleanup of register args; `langc.e` emits `CD_MODSTK(0)` / skips it for
   x86_64.)

This confines the convention change to the call opcode's lowering plus a small
tweak to how `langc.e` sizes the post-call cleanup. The alternative — making
arg-passing a backend operation `pass_arg(i)`/`emit_call(name,n)` invoked from
`langc.e` — is cleaner separation but edits the `OP_FUNC` path more invasively;
propose we start with the localized version and refactor only if it gets ugly.

**Risks specific to this:** 16-byte alignment (the classic "works until libc
segfaults"); `%al=0` for varargs; and `rdx` doing double duty as the second
operand *and* the 4th argument register — the pop-into-registers step must not
clobber a value mid-marshal.

## Target selection

A `-march=i386|x86_64` flag (parsed in `parseopt`, which already handles `-m`/`-g`
options) selects `target.arch` and the descriptor values. `inittarget` splits into
`inittarget_i386` / `inittarget_x86_64` (or one function switching on arch) that
set prefixes, directives, `wordsize`, register names. Default stays i386.

## Phased plan

- **2a — behaviour-preserving i386 split.** Rename the current `cd_write` body to
  `cd_write_i386`; add the dispatch and `target.arch` (= `ARCH_I386`). Thread the
  arg count into `CD_ZCALL`. **No output change** — verified byte-identical with
  `transpiler/invariance.sh`, then fixpoint-gated in CI, exactly like Phase 1.
- **2b — x86_64 backend.** Implement `cd_write_x86_64` and the SysV call handling;
  add `inittarget_x86_64` (`wordsize=8`, `%rax/%rdx/...`, arg registers, align 16).
  This is *new* output and cannot be byte-compared to i386 — see verification.
- **2c — bootstrap + CI on x86_64.** `langc -march=x86_64` compiles the sources to
  x86_64 `.s`, assembled/linked with **native `gcc` (no `-m32`)** → a native
  self-host fixpoint. Add a CI job for it; the i386 fixpoint stays under `-m32`.

## How verification evolves

Phase 1's oracle was "i386 output unchanged." Phase 2 keeps that for 2a, and adds
two more for the new target:

1. **Invariance (2a only):** `invariance.sh` — i386 still byte-identical.
2. **Run-correctness (2b):** a small corpus of UPLNC programs compiled with
   `-march=x86_64`, assembled+run with native `gcc`, output diffed against
   expected. (This is also worth having for i386 under QEMU later.) Needs a few
   golden test programs — a new `transpiler/tests/progs/`.
3. **Per-target self-host fixpoint (2c):** the gold standard, now run *natively*
   for x86_64. `fixpoint.sh` grows a `-march` parameter; CI runs it per target.

So the i386 path is protected by byte-identity throughout, and the x86_64 path is
proven first by running real programs, then by the native fixpoint.

## Decision: uniform System V (Path A) — implemented

Rather than the localized libc-only marshaling above, we chose **uniform SysV**:
*every* x86_64 call follows the platform ABI. This drops the fragile
libc-name-detection, gives C interop and standard tooling, and keeps one
alignment invariant. Implementation (all x86_64-only; i386 stays byte-identical):
- **Callee**: params get negative offsets `-(i·wordsize)(%rbp)`; the prologue
  reserves that space and `CD_SPILLARGS` spills `rdi…r9` into the slots.
- **Caller**: count args → pad so `Zsp ≡ 0 (mod 16)` at the `call` → push args →
  `CD_MARSHAL` loads them into `rdi…r9` → `%al=0` → `call` → unwind.
- Args 1-6 go in registers; args 7+ are pushed on the stack (the caller marshals
  6 into registers and leaves the rest positioned for the callee, whose params
  7+ live at positive `(%rbp)` offsets). The compiler's own source never exceeds
  6, so its self-hosting exercises only the register path.
- Output is non-PIC (absolute addressing, like i386) → link with `-no-pie`.

Verified: non-commutative arg order, recursion, methods, and libc (`printf`,
`putchar`, `strlen`) all run natively; i386 unchanged.

## Open decisions (resolved / historical)

- **Convention approach:** localized call-opcode lowering (recommended) vs. a
  `pass_arg`/`emit_call` backend interface. Start localized?
- **Test corpus:** agree a handful of golden UPLNC programs for run-correctness
  (arithmetic, pointers, structs/methods, recursion, libc I/O).
- **Scope of x86_64 backend:** integer/pointer only for now (floating point is
  M4); confirm we defer FP register args (`xmm`) until then.

## Summary

The `CD_*` IR is already the seam; Phase 2 adds a second lowering function behind
an arch-id dispatch (no function pointers in the language), localizes the
SysV-vs-cdecl convention difference in the call opcode, and leans on the slice-4
word-size routing so x86_64 pointers are free. 2a is byte-identical and safe; 2b
is validated by running real programs and then by a **native** self-host fixpoint
— which is the milestone that finally retires `-m32`.

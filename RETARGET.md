# Retargeting UPLNC: multi-target and multi-host

This document is the design plan for evolving `langc` from its current
single-target (i386), single-host (x86_64) form into a **retargetable,
multi-host** compiler. It captures the architecture, the phased plan, and the
concrete interfaces involved. The higher-level priorities (and where this sits
among floating point, optimization, etc.) live in [`ROADMAP.md`](ROADMAP.md);
the original bootstrap is in [`BOOTSTRAP.md`](BOOTSTRAP.md).

## Two independent axes

The single most important framing: **host** and **target** are orthogonal.

- **Host** — the CPU the `langc` *binary runs on*.
- **Target** — the CPU the *assembly `langc` emits* is for.

A compiler can run on ARM and emit i386, or run on x86_64 and emit ARM64
(a cross-compiler), etc. The "diagonal" (host == target) is what you want for a
self-hosting native toolchain on a given machine.

|              | emit i386 | emit x86_64 | emit ARM64 |
|--------------|:---------:|:-----------:|:----------:|
| **host x86_64** | ✅ today | ⏳ target backend | ⏳ target backend |
| **host arm64**  | ⚠️ likely runs (emits i386 — not native) | — | 🎯 native ARM self-host |

## Where we are now

- Parse → **`scode` / `CD_*` IR** → assembly. The ~60 `CD_*` opcodes in
  `src/codegen.he` (buffered as `scode` items) are already an abstract
  instruction set — a backend seam exists, it just isn't *clean* yet.
- Target = i386 only; ABI = cdecl + glibc; assembler = AT&T via `gcc`.
- Host = x86_64 (the `uplnc2c` stage-0 is a native 64-bit C program).
- `WORDSIZE 4` (in `tlangc.he`) does double duty (see the word-size split below).

---

## Part A — Multi-target (vary the output)

### A.1 The plan is *refactor-first*, not mutate-in-place

A one-off x86_64 port would edit `codegen.e` in place. For retargetability the
order inverts:

| Phase | Work | Validated by |
|------:|------|--------------|
| 0 | **Audit** every i386 assumption in `codegen.e` → becomes the descriptor schema | — |
| 1 | **Introduce a backend seam, i386-only, behaviour-preserving** | fixpoint output **byte-identical** |
| 2 | Add **x86_64** as a *second* backend behind the seam + `-march` flag | x86_64 fixpoint (native, no `-m32`) |
| 3 | Re-bootstrap; run the **fixpoint per target** in CI | i386 (under `-m32`) + x86_64 |
| 4 | *(optional)* a third, RISC-y backend to prove the design | that arch's fixpoint |

Phase 1 is the load-bearing step: moving target-specific things behind an
interface **without changing the emitted i386 a single byte**. The existing
fixpoint check is the correctness oracle — if i386 output drifts, the refactor
has a bug. This is uniquely safe for a self-hosting compiler.

Phase 1 (the data seam) is complete; Phase 2 (the instruction-lowering and
calling-convention backend interface, plus the x86_64 target) is designed in
[`RETARGET-PHASE2.md`](RETARGET-PHASE2.md).

### A.2 What becomes *data* vs. *code*

Most variation collapses into a **target descriptor** (data):

- word/pointer size; alignment (data, stack, struct)
- register file: count, names, arg-passing set, caller/callee-saved, accumulator
  & return register
- assembler syntax: section/`.globl`/`.align` directives, comment char, and the
  **symbol prefix** (some ABIs prepend `_`)

A smaller part must be *code*, because targets differ structurally, not by a
constant:

- **Calling convention** — a small interface:
  `emit_prologue(frame)`, `emit_epilogue()`, `pass_arg(i)`, `emit_call(target, n)`,
  `read_result()`. i386 cdecl (all args on the stack) and x86_64 SysV (6 register
  args + 16-byte stack alignment at the call + `%al = 0` for varargs) are
  different *shapes*. A bounded implementation trick: keep the existing
  "evaluate args, push to stack" machinery and only change the call site — pop
  the accumulated args into `rdi, rsi, …` (spill the 7th+), fix alignment, zero
  `%al`. This localizes the convention change to one opcode path.
- **Compares and division** — today these emit x86-isms inline (flags + `setcc`;
  the `eax:edx`/`idiv` register dance). They must move *behind* the backend so a
  target can lower `dst = (a < b)` or `dst = a / b` its own way (e.g. ARM
  `cmp`+`cset`, a single `sdiv`).
- **Addressing modes** — if the IR emits x86 `base+index*scale` directly, that is
  an x86 assumption hiding in the "generic" layer; a load/store target needs it
  expressed as an abstract address computation.

### A.3 The word-size split (a subtlety the one-off port dodges)

`WORDSIZE` currently sizes **the compiler's own data structures** *and* **the
offsets it computes for the emitted program**. Those coincide only because host
== target. The moment target ≠ host they diverge:

- `HOST_WORDSIZE` — fixed by the host the compiler was built for (x86_64 ⇒ 8);
  governs the compiler's internal layout when it runs.
- `TARGET_WORDSIZE` — per backend; governs symbol-table offsets / sizing of the
  *emitted* program.

Multitarget **forces** disentangling these; conflating them is a latent
cross-compile bug. This is a concrete, findable refactor.

### A.4 Keep the abstraction honest

The only reliable way to verify an abstraction is general is to design it against
a target *structurally unlike* the one you have. Abstracting only "i386 vs
x86_64" will bake in x86-isms (accumulator-centric, two-operand, flags, ALU
memory operands). So even if only i386 + x86_64 ship, **sketch on paper how an
ARM64 / RISC-V backend (3-operand, load/store, no ALU memory operands,
`cmp`+`cset`) would slot in.** That paper exercise shapes a correct
convention/compare/addressing interface.

### A.5 Anti-goal: do **not** build an instruction selector

For an experimental/teaching compiler, a general instruction-selection framework
is over-engineering. Keep the dumb stack-machine codegen — just *parameterize*
it with the descriptor + the thin convention/compare interface. That is enough
for i386 + x86_64 + a plausible ARM64, and it keeps the compiler legible.

---

## Part B — Multi-host (run on other CPUs)

### B.1 Host portability is *nearly free* — thanks to `uplnc2c`

`uplnc2c` emits standard C with no inline asm and no libc headers, clean under
**LP64** (`int` 32-bit, pointer 64-bit). ARM64 and riscv64 Linux are LP64
little-endian — the same model as x86_64. So `build.sh` on those hosts should
produce a native `langc` binary that **runs**. Gotchas:

- **`char` signedness** — the real one. x86 `char` is signed; ARM/RISC-V `char`
  is unsigned by default, and the lexer assumes signed `char`. Mitigation:
  **`-fsigned-char`** (already in `build.sh`).
- **Endianness** — the compiler is text-in/text-out and serializes no multi-byte
  binary, so LE hosts are fine; big-endian (s390x) would need an audit.
- **LP64** — holds on mainstream 64-bit arches; 32-bit ARM (ILP32) reverts to the
  original `int == pointer == 4` model.

### B.2 The seed is architecture-independent

Because the seed is portable C, **any architecture with a C compiler can
bootstrap `langc` from source** — *provided `langc` has a backend for that arch*.
This decouples the two hard problems:

- "get a seed compiler on arch X" → free, via `uplnc2c` → C → native `gcc`.
- "make `langc` target arch X" → the backend work (Part A).

Native self-hosting on, e.g., ARM64 then needs no x86, no QEMU, no cross-binaries:

```
on arm64:  source ──uplnc2c──▶ C ──gcc(arm)──▶ langc (stage 0, emits ARM64)
           langc ─self-compiles→ ARM64 .s ─as/ld→ langc1 → … → fixpoint on arm64
```

### B.3 Sequence for a new architecture (e.g. ARM64)

1. **Develop the ARM64 backend as a cross-compiler on x86_64** — fastest feedback;
   test the emitted ARM64 under **QEMU user-mode** (`qemu-aarch64`).
2. **Harden the host build** (`-fsigned-char`, confirm LP64). The
   ARM-backend-containing `langc` can then be transpiled+built natively on ARM.
3. **Native bootstrap + fixpoint on ARM64** (B.2).
4. **CI matrix** — `ubuntu-24.04-arm` runners (or QEMU) run the fixpoint *per
   architecture*, proving self-hosting on each.

---

## Testing strategy

- **Fixpoint per target** is the acceptance test throughout (`fixpoint.sh`
  generalized to take `-march`).
- **Phase-1 invariance**: i386 output must stay byte-identical across the seam
  refactor.
- **QEMU user-mode** to run cross-emitted code and foreign-host binaries in CI.
- **CI matrix** over {host} × {target} cells that make sense.

## Summary

Host-portability is a cheap bonus the transpiler already hands us (`-fsigned-char`
+ an arm64 CI job). The real cost is the per-target backends — which is exactly
what the Phase-1 seam refactor is designed to make repeatable. Do the seam first;
then each new target (and, with the portable seed, each new host) is incremental.

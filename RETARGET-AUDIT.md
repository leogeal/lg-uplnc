# Phase 0 — i386 coupling audit

A concrete inventory of every place the compiler assumes the i386 target, with
file:line references, classified into **data** (→ the `starget` descriptor) and
**code** (→ a per-target instruction-lowering backend). This is the input to the
Phase 1 seam refactor (see [`RETARGET.md`](RETARGET.md) Part A). Each Phase-1
slice is proven byte-identical with `transpiler/invariance.sh`.

## The emit layer is already target-neutral ✅

The lowest output layer in `langc.e` has no target assumptions and is the stable
foundation everything else builds on:

| Helper | Line | Role |
|--------|------|------|
| `outbyte`/`outbyte1` | 4255 | the single raw byte sink (`putchar`, or the literal-capture stack) |
| `outasm`/`outstr` | 4266 / 4270 | emit a string |
| `ot` / `ol` | 4250 / 4139 | tab+string / tab+string+newline |
| `nl` `tab` `col` `comma` `comment` | 4229+ | punctuation |
| `outdec`/`outint` | 4106 / 4114 | decimal numbers |

## Data coupling → `starget` descriptor

Pure target *data*; varying it needs no logic changes. Wired incrementally:

| Item | i386 value | Where | Status |
|------|-----------|-------|:------:|
| local label prefix | `.L` | `printlab` `langc.e:1858` | ✅ `target.label_prefix` |
| symbol prefix | `""` (ELF; no `_`) | `outname` `langc.e:4066` | ⏳ `target.sym_prefix` |
| target word size | `4` | `WORDSIZE` `tlangc.he:18`; used `langc.e:691,698,702` | ⏳ `target.wordsize` |
| function-header directives | `.text` / `.align 16` / `.globl` / `.type …,@function` / `name:` | `header` `langc.e:1123-1135` | ⏳ |
| read-only data section | `.section` `.rodata` | `dumplits` `langc.e:4149` | ⏳ |
| globals / bss emission | (`.comm`/`.long`/…) | `dumpglbs` `langc.e:4195` | ⏳ audit |

## Code coupling → per-target backend

Structural target logic, almost all in `cd_write` (`codegen.e:82-524`), the
`scode`/`CD_*` → assembly lowering (57 opcodes). This is the bulk of Phase 2 and
needs a backend *interface*, not just data.

- **Register file** — `%eax` accumulator, `%edx` 2nd operand, `%ecx`/`%cl` shift
  count, `%al` byte, `%ebp`/`%esp` frame/stack; `regnames` = eax/ebx/ecx/edx
  (`codegen.e:998`). RG_A..RG_D abstraction exists in `langc.e` but `cd_write`
  hardcodes the names.
- **Mnemonics with size suffixes** — `movl/movb/movsbl/movzbl`, `pushl/popl`,
  `addl/subl/imull/idivl`, `testl`, `sete/setne/…`, `negl/notl`, `sall/sarl/shrl`,
  `incl/decl`, `leal`, `xchgl`, `andl/orl/xorl`, `jmp/je/jne`, `call`, `ret`.
- **Prologue / epilogue** — `CD_STKENTER`/`CD_STKLEAVE` (`codegen.e:292-301`):
  `push %ebp; mov %esp,%ebp` / `mov %ebp,%esp; pop %ebp`.
- **Stack adjust** — `CD_MODSTK` (`codegen.e:334`): `add/sub $n,%esp`.
- **Calling convention** — cdecl: `CD_PUSH`/`CD_POP`/`CD_ZCALL`, caller-cleans via
  `CD_MODSTK`, result in `%eax`. Arg evaluation/push is driven from `langc.e`
  (the `OP_FUNC` path). *(SysV x86_64 differs in shape — see RETARGET.md A.2.)*
- **Div/mul register dance** — `CD_DIV2REGS` (`codegen.e:275-290`):
  `xchg`/`mov %ecx`; `idivl`; the `%eax:%edx` pair. `imull %edx`.
- **Comparisons** — flags + `set<cc> %al` + `movzbl %al,%eax` (`codegen.e:135-249`).
- **Addressing modes** — `n(%ebp)` locals, `n(%eax)`/`n(%edx)` indirect,
  `symbol+offset` for globals (`CD_LDW`/`CD_STOW`/`CD_LDLW`/…).
- **Sign/zero extension** — `movsbl` (byte load, sign-extend), `movzbl` (boolean
  zero-extend): width/extension semantics.

## Word-size double-duty (the cross-compile hazard)

`WORDSIZE` (`tlangc.he:18`) sizes **the compiler's own data** *and* **the offsets
it computes for the emitted program**. These coincide only because host==target;
multi-target must split them into `HOST_WORDSIZE` / `TARGET_WORDSIZE`
(RETARGET.md A.3). `target.wordsize` is the target side.

## Phase 1 plan (data slices, each invariance-checked)

1. ✅ label prefix → `target.label_prefix`
2. ⏳ symbol prefix → `target.sym_prefix` (`outname`)
3. ⏳ assembler directives (function header + rodata section) → `target` fields
4. ⏳ target word size → `target.wordsize` (type-size init)

Once the data seam is in place and proven invariant, Phase 2 introduces the
backend *interface* (instruction lowering + calling convention) and adds the
x86_64 backend behind it.

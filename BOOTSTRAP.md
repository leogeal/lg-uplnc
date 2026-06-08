# Bootstrapping the UPLNC compiler

UPLNC is **self-hosting**: its compiler is written in UPLNC, so building it from
source requires a working UPLNC compiler — the classic chicken-and-egg problem.
This document captures (a) what the build actually needs, (b) a precise
feature/grammar inventory of the language *as used by the compiler sources*, and
(c) a concrete plan to break the cycle and reach a verified self-hosting build.

Everything below is derived directly from the sources in [`src/`](src/) and the
driver `langdrv.pl`, not from external documentation.

---

## 1. What the build needs

The pipeline, per [`src/langdrv.pl`](src/langdrv.pl):

```
lpp1 file.e | langc > file.s      # preprocess, then compile UPLNC -> asm
gcc -o a.out *.s                  # gcc assembles + links the .s against glibc
```

There are **two binaries to produce**, both written in UPLNC:

| Binary | Built from | Has `main` | Role |
|--------|-----------|:----------:|------|
| `lpp1` | `lpp1.e` | yes | Preprocessor (`#include`, `#define`, macros) |
| `langc` | `langc.e` + `codegen.e` + headers `tlangc.he`, `codegen.he` | yes | Compiler (UPLNC → i386 asm) |

Auxiliary modules, **not required** for a minimal bootstrap:

| File | `main`? | Role |
|------|:-------:|------|
| `grph.e` | no | Emits the syntax-tree graph behind the paper's `tlgraph` figures |
| `autodyn.e` | no | Automatic allocation/deallocation helper |

### Compilation target

The emitted `.s` assumes:

- **32-bit x86 (i386)**, AT&T syntax — registers `%esp`/`%eax`, `WORDSIZE 4`
  (`tlangc.he`), code-gen register set `RG_A..RG_D` = eax/ebx/ecx/edx.
- **cdecl** calls into **stock glibc** — referenced symbols include `fprintf`
  (≈128 call sites), `calloc`, `free`, `fopen`, `exit`, `strlen`, `fgetc`,
  `fputc`, `getchar`, `putchar`. No custom runtime is needed.
- gcc both **assembles and links** the output, so a 32-bit toolchain is required
  to build the compiler's *own output* (including when it compiles itself).

There is **no inline assembly anywhere in the compiler sources** — although the
language supports an `asm` statement (`stasm` in `tlangc.he`), the compiler
itself never uses it. Nothing exotic needs to survive translation.

---

## 2. UPLNC feature / grammar inventory

This is the subset of UPLNC the bootstrap tooling must accept — i.e. every
construct that appears in `lpp1.e`, `langc.e`, `codegen.e`, and the headers. It
is C-like in semantics but differs in declaration syntax and adds methods.

### 2.1 Declarations — `var name : type`

Type comes *after* a colon; the pointer/array markers are **prefix**:

```c
var int:_dynw;                       // int _dynw;
var **char: _dyn_ptr;                // char** _dyn_ptr;
var lptr,rlptr:int;                  // multiple names share one type
var stderr,stdin,stdout:*int;        // int *stderr, *stdin, *stdout;
var line,rline:[160]char;            // char line[160], rline[160];
var ifiles:[MAXINC]*int;             // int* ifiles[MAXINC];  (array of pointers)
var extern int :Zsp;                 // extern int Zsp;
var **char extern: regnames;         // extern char** regnames;  (extern can follow type)
```

- **Pointer** type: `*T`, `**T` (prefix `*`).
- **Array** type: `[N]T`, and `[N]*T` (array of pointers). Size precedes element type.
- `extern` may appear before *or* after the type keyword.
- Locals may be declared **mid-block**, after statements (see `langc.e:main`,
  `var *char:pp,pp2;` appearing partway through the body) → transpile to C must
  target **C99** or hoist declarations.

### 2.2 Functions — `func`

```c
func main(argc:int,argv:**char) { ... }   // int main(int argc, char** argv)
func cg_init(this:*scodegen);             // prototype
func chkmem();                            // no params, default return type = int
```

- Parameters are `name:type`, same rules as `var`.
- No explicit return type syntax observed → **default return type is `int`**.

### 2.3 Structs and methods

```c
struct cmac{ *char n; *char sub; };       // one-liner form
struct snamenode{
  [NAMESIZE]char name;
  *snamenode next;
  func init;                              // method *slots* (declared, see below)
  func done;
};
```

Methods are defined out-of-line and dispatched **statically** by the receiver's
struct type (the `func` members are **never assigned function pointers** — checked
across all sources — so there is no virtual dispatch):

```c
method snamenode.init(){ next=0; name[0]=0; }
method snamelist.addm(s:*char){ ... }
```

Two semantics the translator must reproduce:

1. **Static name-mangling by receiver type.**
   - `cnmlst->addm(nm)`  →  `snamelist_addm(cnmlst, nm)`
   - `q->sym.done()`     →  `ssym_done(&q->sym)`   (value receiver → take address)
2. **Implicit `this`.** Inside a method body, a bare identifier that names a field
   of the receiver resolves to `this->field`. In `snamenode.done`:
   ```c
   method snamenode.done(){ if(next){ next->done(); free(next); } }
   //                            ^^^^ this->next        ^^^^^^^^^^^^ snamenode_done(this->next)
   ```
   This requires the translator to carry a **struct-layout model** so it knows
   which bare names are members. The same model drives method mangling.

### 2.4 Control flow

Present and used: `if` / `else`, `while`, `for`, `do`, `break`, `continue`,
`return`. **Not used anywhere** in the compiler sources: `switch`/`case`,
`goto`, and (as noted) `asm`. Operators and expression syntax match C.

### 2.5 Misc

- `sizeof(*char)` etc. — operand uses UPLNC type syntax → `sizeof(char*)`.
- Standard glibc names (`stderr`/`stdin`/`stdout`, `fprintf`, …) are declared
  `extern` in the headers and called directly.
- Preprocessor (`#include`, `#define`, macros, nested includes) is handled by
  **`lpp1`**, not by cpp — and `lpp1` is itself one of the two UPLNC programs we
  must build, so once it is bootstrapped no cpp substitution is needed.

---

## 3. Strategy: a UPLNC→C transpiler, then self-host

UPLNC is semantically C-with-different-skin, and the only program we ever need to
translate is the compiler itself (fully self-contained). A source-to-source
**UPLNC→C transpiler** is therefore the lowest-risk way to mint a throwaway
"stage-0" compiler and let gcc do the heavy lifting.

Alternatives considered (kept as fallbacks):

1. **UPLNC→C transpiler** — *recommended*; mechanical, gcc-backed.
2. **Hand-port to C** — reliable but ~6,000 throwaway lines; use as a *local*
   patch for any single construct the transpiler can't yet handle.
3. **UPLNC interpreter** (e.g. Python) good enough to *run* `langc.e` on itself —
   avoids C-codegen mismatch but must model pointers, manual `calloc`/`free`, and
   `FILE*`/`fprintf`; comparable effort, slower.
4. **Locate the author's original Small-C bootstrap or a binary** — quick to
   check, almost certainly a dead end (arXiv carries only the paper).

### What the transpiler must do

A small recursive-descent translator with a struct-layout model, applying:

- `var n:T;` → `T n;`  ·  `*T`/`**T` → `T*`/`T**`  ·  `[N]T n` → `T n[N]`
- multi-name decls split out  ·  `extern` (either position) → C `extern`
- `func f(a:int){…}` → `int f(int a){…}`; prototypes pass through
- `sizeof(*char)` → `sizeof(char*)`; struct `func x;` slots dropped
- **method mangling** + **implicit `this`** (§2.3) — the hard part
- emit **C99** (mid-block declarations) and `#include` the transpiled `.h`
  headers (the `.he` files run through the same rules first)

---

## 4. Bootstrap stages and the proof

```
stage 0   transpiler:  *.he→*.h, *.e→*.c → gcc -m32 → langc-0, lpp1-0
stage 1   langc-0:     compile langc.e+codegen.e, lpp1.e → *.s → gcc -m32 → langc-1, lpp1-1
stage 2   langc-1:     recompile the same sources         → *.s → gcc -m32 → langc-2
verify    FIXPOINT:    stage-1 .s  ==  stage-2 .s   (byte-identical)
```

The **fixpoint** — `langc-1` and `langc-2` emitting identical assembly — is the
real acceptance test: it proves the transpiler reproduced UPLNC's semantics
faithfully *and* that the compiler is genuinely self-hosting. Once it holds, the
**stage-0 transpiler is disposable**; the compiler reproduces itself unaided.

Build **stage 0 with `-m32` too**, so the host's word size (pointer = 4) matches
the compiler's internal `WORDSIZE 4` assumption — keeping everything i386 end to
end and avoiding 64-bit pointer-width surprises.

---

## 5. Toolchain & runtime

- **32-bit toolchain:** `gcc-multilib` + 32-bit glibc dev libs (`-m32`), or an
  i686 cross-toolchain, or run the whole flow under `qemu-i386` / a 32-bit
  container. Needed to assemble+link the compiler's own output.
- **Runtime:** stock glibc, cdecl — no custom runtime to write.

---

## 6. Test corpus & acceptance

1. **Self-host fixpoint** holds (primary gate, §4).
2. Compile + run the optional modules (`grph.e`, `autodyn.e`) and a handful of
   small UPLNC programs exercising pointers, multidimensional arrays, structs,
   and methods.
3. End-to-end sanity: regenerate the paper's `tlgraph` figures via `grph` and
   eyeball them.

---

## 7. Risks → mitigations

| Risk | Mitigation |
|------|-----------|
| Implicit-`this` / method type resolution wrong | Build the struct model first; unit-test on the small `snamenode`/`snamelist` methods before the 4,331-line `langc.e` |
| A UPLNC construct the transpiler doesn't cover | Hand-port that one function to C (approach 2 as a local patch) |
| 32-bit toolchain unavailable | `qemu-i386` or a 32-bit container; document in README |
| Mid-block declarations rejected | Target C99 (or hoist locals) |
| stage-1 ≠ stage-2 (no fixpoint) | Diff the `.s`, localize the diverging function, fix the transpiler rule, repeat |

---

## Implementation status

Steps 2–3 are working — see [`transpiler/`](transpiler/) (`uplnc2c.py`). Every
source transpiles; the stage-0 `langc` builds (64-bit) and **self-compiles every
one of its own units, including the 4,331-line `langc.e`, to i386 assembly with 0
errors**; `lpp1` runs as a working preprocessor. Return-type inference closed the
int/pointer width hazard (§7), so no `-m32` is needed to *run* the stage-0
compiler. The only remaining step is the self-host **fixpoint** (§4), which needs
the 32-bit libc to assemble/link `langc`'s i386 output. Details in
[`transpiler/README.md`](transpiler/README.md).

## 8. Rough sequencing

1. **Recon (½ day):** finalize this inventory against the sources; quick hunt for
   any original binary; stand up the `-m32` toolchain.
2. **Transpiler core (2–4 days):** lexer + struct model + declaration / pointer /
   array / method / implicit-`this` rules; round-trip the *small* methods first.
3. **Compile the real sources (1–2 days):** push `lpp1.e`, then `codegen.e` +
   `langc.e` through; close gaps until `langc-0` / `lpp1-0` link.
4. **Self-host + fixpoint (1 day):** run stages 1→2, diff, converge.
5. **Corpus + docs (½ day):** sample programs, figures, document the build.

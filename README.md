# UPLNC Compiler

Source code for the compiler of the **UPLNC** language, by Evgueniy Vitchev.

UPLNC is an experimental, C-like systems language created as part of a DIY
platform project (language + tools + OS kernel + utilities). It supports
unlimited levels of indirection, multidimensional arrays, structures, methods
on structures, and most C-style control statements. Its syntax parser is
similar to Small C, and — notably — the compiler is **self-hosting**: it is
written in UPLNC itself and can compile its own source.

The compiler runs in three stages:

1. **Parse** the source and build a syntax tree.
2. Generate an **intermediate representation** of the program.
3. Emit **assembly** code.

## Provenance

There is no upstream code-hosting repository for UPLNC. The complete source was
published as a full listing inside the paper:

> **The UPLNC Compiler: Design and Implementation** — Evgueniy Vitchev
> arXiv: [`cs/0402043`](https://arxiv.org/abs/cs/0402043) (submitted 18 Feb 2004; only version)

The files in [`src/`](src/) were extracted verbatim from the arXiv e-print
archive (the LaTeX `verbatim` listing wrappers were stripped; the code itself is
unmodified). The original paper and raw archive are kept alongside for reference.

## Layout

| Path | Description |
|------|-------------|
| [`src/`](src/) | Clean compiler source (self-hosting; written in UPLNC) |
| `uplnc-compiler-paper.pdf` | The full 134-page paper (design + implementation) |
| `uplnc-eprint.tar.gz`, `uplnc-eprint/` | Original arXiv e-print archive and its extracted contents |

### Source files (`src/`)

`.e` files are source; `.he` files are headers.

| File | Role |
|------|------|
| `langc.e` | Main language compiler (lexer, parser, tree builder) |
| `codegen.e` / `codegen.he` | Code generator (IR → assembly) |
| `tlangc.he` | Core compiler declarations / header |
| `autodyn.e` | Automatic allocation / deallocation |
| `lpp1.e` | Preprocessor |
| `grph.e` | Graph utilities |
| `langdrv.pl` | Perl build/driver script |

## Building

Because the compiler is written in UPLNC, building it from scratch requires
bootstrapping with an existing UPLNC compiler binary. The paper (included as
`uplnc-compiler-paper.pdf`) is the authoritative reference for the toolchain and
the three-stage architecture.

See [`BOOTSTRAP.md`](BOOTSTRAP.md) for a concrete bootstrapping plan — what the
build actually needs (two binaries, `lpp1` and `langc`, targeting i386 + glibc),
a UPLNC feature/grammar inventory drawn from the sources, and a transpiler-based
strategy with a self-host fixpoint as the acceptance test.

## License

The compiler is released under the **GNU General Public License, version 2 (or,
at your option, any later version)**, © 2003 E.V. See the license headers at the
top of each source file in `src/`.

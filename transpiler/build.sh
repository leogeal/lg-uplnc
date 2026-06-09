#!/usr/bin/env bash
# Build the UPLNC stage-0 tools (lpp1, langc) via the uplnc2c transpiler.
# See ../BOOTSTRAP.md and ./README.md.
set -euo pipefail
cd "$(dirname "$0")"

SRC=../src
OUT=build
mkdir -p "$OUT"
T="python3 uplnc2c.py"

echo "[build] transpiling UPLNC -> C"
# Every unit is transpiled with all sibling sources passed as -I context, so the
# global type environment and return-type inference are complete (a pointer-
# returning function in one unit gets the right prototype in every caller).
COMPILER_SRCS="$SRC/langc.e $SRC/codegen.e $SRC/autodyn.e $SRC/grph.e \
               $SRC/tlangc.he $SRC/codegen.he"
ctx() { for f in $COMPILER_SRCS; do [ "$f" = "$1" ] || printf -- '-I %s ' "$f"; done; }

# headers -> .h (no prelude; #included into the .c units)
$T "$SRC/tlangc.he"  $(ctx "$SRC/tlangc.he")  -o "$OUT/tlangc.h"
$T "$SRC/codegen.he" $(ctx "$SRC/codegen.he") -o "$OUT/codegen.h"
# preprocessor (self-contained; works at 64-bit)
$T "$SRC/lpp1.e"     -o "$OUT/lpp1.c"
# compiler units
$T "$SRC/codegen.e"  $(ctx "$SRC/codegen.e")  -o "$OUT/codegen.c"
$T "$SRC/langc.e"    $(ctx "$SRC/langc.e")    -o "$OUT/langc.c"
$T "$SRC/autodyn.e"  $(ctx "$SRC/autodyn.e")  -o "$OUT/autodyn.c"
$T "$SRC/grph.e"     $(ctx "$SRC/grph.e")     -o "$OUT/grph.c"

# -fsigned-char: the original i386 compiler assumes signed `char`; force it on
# all hosts so the transpiled compiler behaves identically on ARM/RISC-V, where
# `char` is unsigned by default (host-portability; see RETARGET.md).
CC="gcc -std=gnu89 -fsigned-char -w"
# UPLNC is an i386 (4-byte int == 4-byte pointer) language. Prefer -m32.
if echo 'int main(void){return 0;}' | gcc -m32 -x c - -o /dev/null 2>/dev/null; then
    M="-m32"
    echo "[build] using -m32 (correct i386 target)"
else
    M=""
    echo "[build] WARNING: -m32 unavailable (install gcc-multilib / libc6-dev-i386)."
    echo "[build]          lpp1 works at 64-bit; langc needs -m32 or return-type"
    echo "[build]          inference to run correctly (see README 'Status')."
fi

echo "[build] compiling lpp1"
$CC $M -o "$OUT/lpp1" "$OUT/lpp1.c"

echo "[build] compiling langc (langc + codegen + autodyn + grph)"
$CC $M -o "$OUT/langc" "$OUT/langc.c" "$OUT/codegen.c" "$OUT/autodyn.c" "$OUT/grph.c"

echo "[build] done -> $OUT/lpp1  $OUT/langc"

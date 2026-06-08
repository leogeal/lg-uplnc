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
# headers -> .h (no prelude; #included into the .c units)
$T "$SRC/tlangc.he"  -o "$OUT/tlangc.h"
$T "$SRC/codegen.he" -o "$OUT/codegen.h"
# preprocessor (self-contained; works at 64-bit)
$T "$SRC/lpp1.e"     -o "$OUT/lpp1.c"
# compiler units (-I headers populate the type/method environment)
$T "$SRC/codegen.e"  -I "$SRC/codegen.he" -I "$SRC/tlangc.he" -o "$OUT/codegen.c"
$T "$SRC/langc.e"    -I "$SRC/tlangc.he"  -I "$SRC/codegen.he" -o "$OUT/langc.c"
$T "$SRC/autodyn.e"  -o "$OUT/autodyn.c"
$T "$SRC/grph.e"     -I "$SRC/tlangc.he"  -o "$OUT/grph.c"

CC="gcc -std=gnu89 -w"
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

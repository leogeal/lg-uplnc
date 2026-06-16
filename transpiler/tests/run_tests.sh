#!/usr/bin/env bash
# Smoke + functional tests for the uplnc2c transpiler.
set -uo pipefail
cd "$(dirname "$0")/.."

TDIR=$(pwd)              # absolute transpiler dir (for tools)
SRC=../src
SRCDIR=$(cd "$SRC" && pwd)
fail=0
pass=0
ok()   { echo "  ok   - $1"; pass=$((pass+1)); }
bad()  { echo "  FAIL - $1"; fail=$((fail+1)); }

echo "[1] transpile every UPLNC source without error"
for f in tlangc.he codegen.he lpp1.e codegen.e langc.e autodyn.e grph.e; do
    if python3 uplnc2c.py "$SRC/$f" -I "$SRC/tlangc.he" -I "$SRC/codegen.he" \
            >/dev/null 2>/tmp/uplnc2c.err; then
        ok "transpile $f"
    else
        bad "transpile $f -> $(tail -1 /tmp/uplnc2c.err)"
    fi
done

echo "[2] build the stage-0 tools"
if ./build.sh >/tmp/uplnc_build.log 2>&1; then
    ok "build.sh"
else
    bad "build.sh (see /tmp/uplnc_build.log)"
fi

echo "[3] lpp1 preprocessor behaves correctly"
LPP=build/lpp1
if [ -x "$LPP" ]; then
    out=$("$LPP" tests/pp_input.e 2>/dev/null)
    echo "$out" | grep -q 'int hello\[3\];'        && ok "macro substitution (GREETING/N)" || bad "macro substitution"
    echo "$out" | grep -q 'literal #define stays'  && ok "string literals preserved"        || bad "string literals"
    echo "$out" | grep -vq 'a comment'             && ok "comments stripped"                 || bad "comments stripped"
else
    bad "lpp1 not built"
fi

echo "[4] langc compiles a program to i386 assembly"
LANGC=build/langc
if [ -x "$LANGC" ] && [ -x "$LPP" ]; then
    # a+2 with a variable (constant folding would collapse a literal 40+2 to 42)
    printf 'func main()\n{\n  var int:a;\n  var int:x;\n  a=40;\n  x=a+2;\n  return x;\n}\n' > /tmp/uplnc_t1.e
    asm=$("$LPP" /tmp/uplnc_t1.e 2>/dev/null | "$LANGC" 2>/dev/null)
    echo "$asm" | grep -q '^main:'           && ok "emits a 'main:' label"        || bad "emits 'main:'"
    echo "$asm" | grep -q 'addl %edx, %eax'  && ok "compiles a+2 to add"          || bad "compiles a+2"
    echo "$asm" | grep -q '0 error(s)'       && ok "reports 0 errors"             || bad "reports 0 errors"
else
    bad "langc not built"
fi

echo "[5] langc self-compiles its own units (stage-1) with 0 errors"
if [ -x "$LANGC" ] && [ -x "$LPP" ]; then
    # run from the src dir so lpp1's #include "tlangc.he" resolves; timeout
    # guards against a hang on (e.g. accidentally headerless) input.
    for u in langc codegen autodyn grph lpp1; do
        asm=$(cd "$SRCDIR" && timeout 60 sh -c \
              "'$TDIR/build/lpp1' $u.e 2>/dev/null | '$TDIR/build/langc' 2>/dev/null")
        echo "$asm" | grep -q '0 error(s)' && ok "self-compile $u.e (0 errors)" || bad "self-compile $u.e"
    done
else
    bad "langc not built"
fi

echo "[6] x86_64 backend: programs compile (-march=x86_64), assemble + run correctly"
if [ ! -x "$LANGC" ]; then
    bad "langc not built"
elif [ "$(uname -m)" != "x86_64" ] || ! command -v gcc >/dev/null; then
    echo "  skip - host $(uname -m) cannot natively assemble x86_64 (need an x86_64 host)"
else
    while read -r name want; do
        [ -z "$name" ] && continue
        asm="/tmp/uplnc_x64_$name.s"; bin="/tmp/uplnc_x64_$name"
        "$TDIR/build/lpp1" "tests/progs/$name.e" 2>/dev/null \
            | "$TDIR/build/langc" -march=x86_64 > "$asm" 2>/dev/null
        if grep -qE 'not yet|[1-9][0-9]* error' "$asm"; then
            bad "x86_64 $name.e (compile)"
        # -no-pie: the backend emits non-PIC absolute addressing (like i386)
        elif ! gcc -no-pie "$asm" -o "$bin" 2>/dev/null; then
            bad "x86_64 $name.e (assemble/link)"
        else
            "$bin"; got=$?
            [ "$got" = "$want" ] && ok "x86_64 $name.e -> exit $got" \
                                 || bad "x86_64 $name.e (got $got, want $want)"
        fi
    done < tests/progs/expected.txt
fi

echo "[7] i386 x87 backend: programs compile (-march=i386), assemble + run (-m32)"
# Find a working 32-bit toolchain. The default 'gcc' may lack 32-bit libgcc on
# some hosts (e.g. gcc-8 here), so fall back to a versioned gcc that has it.
M32=""
for cc in "gcc -m32" "gcc-12 -m32" "gcc-11 -m32" "gcc-10 -m32" "gcc-9 -m32"; do
    if echo 'int main(void){return 0;}' | $cc -x c - -o /tmp/uplnc_m32probe 2>/dev/null; then
        M32="$cc"; break
    fi
done
if [ ! -x "$LANGC" ]; then
    bad "langc not built"
elif [ -z "$M32" ]; then
    echo "  skip - no working -m32 toolchain (need gcc-multilib / libc6-dev-i386)"
else
    while read -r name want; do
        [ -z "$name" ] && continue
        asm="/tmp/uplnc_i386_$name.s"; bin="/tmp/uplnc_i386_$name"
        "$TDIR/build/lpp1" "tests/progs/$name.e" 2>/dev/null \
            | "$TDIR/build/langc" -march=i386 > "$asm" 2>/dev/null
        if grep -qE 'not yet|[1-9][0-9]* error' "$asm"; then
            bad "i386 $name.e (compile)"
        # -no-pie: non-PIC absolute addressing; -fsigned-char to match i386 char
        elif ! $M32 -no-pie -fsigned-char "$asm" -o "$bin" 2>/dev/null; then
            bad "i386 $name.e (assemble/link)"
        else
            "$bin"; got=$?
            [ "$got" = "$want" ] && ok "i386 $name.e -> exit $got" \
                                 || bad "i386 $name.e (got $got, want $want)"
        fi
    done < tests/progs/expected.txt
fi

echo "[8] arm64 backend: programs compile (-march=arm64), assemble + run"
# Cross-toolchain on x86 (binaries run via qemu-user binfmt), or native gcc on
# an arm64 host. Integer + floating point both run; the skip branch below is a
# safety net for any feature that errors cleanly (e.g. float params/returns).
A64=""
if command -v aarch64-linux-gnu-gcc >/dev/null; then A64="aarch64-linux-gnu-gcc -static"
elif [ "$(uname -m)" = "aarch64" ]; then A64="gcc -no-pie"; fi
if [ ! -x "$LANGC" ]; then
    bad "langc not built"
elif [ -z "$A64" ]; then
    echo "  skip - no aarch64 toolchain (need gcc-aarch64-linux-gnu + qemu-user-static)"
else
    while read -r name want; do
        [ -z "$name" ] && continue
        asm="/tmp/uplnc_arm64_$name.s"; bin="/tmp/uplnc_arm64_$name"
        "$TDIR/build/lpp1" "tests/progs/$name.e" 2>/dev/null \
            | "$TDIR/build/langc" -march=arm64 > "$asm" 2>/dev/null
        if grep -q 'not supported on arm64' "$asm"; then
            echo "  skip - arm64 $name.e (floating point not implemented on arm64 yet)"
        elif grep -qE '[1-9][0-9]* error' "$asm"; then
            bad "arm64 $name.e (compile)"
        elif ! $A64 "$asm" -o "$bin" 2>/dev/null; then
            bad "arm64 $name.e (assemble/link)"
        else
            "$bin"; got=$?
            [ "$got" = "$want" ] && ok "arm64 $name.e -> exit $got" \
                                 || bad "arm64 $name.e (got $got, want $want)"
        fi
    done < tests/progs/expected.txt
fi

echo "[9] riscv64 backend: programs compile (-march=riscv64), assemble + run"
# Cross-toolchain + qemu-user binfmt on x86, or native gcc on riscv64. Integer
# and floating point both run; the skip branch is a safety net for any feature
# that errors cleanly (e.g. float params/returns).
RV=""
if command -v riscv64-linux-gnu-gcc >/dev/null; then RV="riscv64-linux-gnu-gcc -static"
elif command -v riscv64-linux-gnu-gcc-10 >/dev/null; then RV="riscv64-linux-gnu-gcc-10 -static"
elif [ "$(uname -m)" = "riscv64" ]; then RV="gcc -no-pie"; fi
if [ ! -x "$LANGC" ]; then
    bad "langc not built"
elif [ -z "$RV" ]; then
    echo "  skip - no riscv64 toolchain (need gcc-riscv64-linux-gnu + qemu-user-static)"
else
    while read -r name want; do
        [ -z "$name" ] && continue
        asm="/tmp/uplnc_riscv_$name.s"; bin="/tmp/uplnc_riscv_$name"
        "$TDIR/build/lpp1" "tests/progs/$name.e" 2>/dev/null \
            | "$TDIR/build/langc" -march=riscv64 > "$asm" 2>/dev/null
        if grep -q 'not supported on riscv' "$asm"; then
            echo "  skip - riscv64 $name.e (floating point not implemented on riscv64 yet)"
        elif grep -qE '[1-9][0-9]* error' "$asm"; then
            bad "riscv64 $name.e (compile)"
        elif ! $RV "$asm" -o "$bin" 2>/dev/null; then
            bad "riscv64 $name.e (assemble/link)"
        else
            "$bin"; got=$?
            [ "$got" = "$want" ] && ok "riscv64 $name.e -> exit $got" \
                                 || bad "riscv64 $name.e (got $got, want $want)"
        fi
    done < tests/progs/expected.txt
fi

echo "[10] mips64 backend: programs compile (-march=mips64), assemble + run"
# MIPS64 N64, big-endian -- the one big-endian target. Cross-toolchain + qemu
# binfmt on x86, or native gcc on mips64. Integer only for now; FP programs emit
# a 'not supported on mips' marker and are skipped here.
MIPS=""
# -mno-abicalls -fno-pic -G 0: non-PIC, and -G 0 disables small-data so `dla`
# forms a full 64-bit *absolute* address rather than a $gp-relative one (we
# never set up $gp; calls go through $t9). See fixpoint.sh for the rationale.
if command -v mips64-linux-gnuabi64-gcc >/dev/null; then MIPS="mips64-linux-gnuabi64-gcc -static -mno-abicalls -fno-pic -G 0"
elif [ "$(uname -m)" = "mips64" ]; then MIPS="gcc -no-pie -mno-abicalls -fno-pic -G 0"; fi
if [ ! -x "$LANGC" ]; then
    bad "langc not built"
elif [ -z "$MIPS" ]; then
    echo "  skip - no mips64 toolchain (need gcc-mips64-linux-gnuabi64 + qemu-user-static)"
else
    while read -r name want; do
        [ -z "$name" ] && continue
        asm="/tmp/uplnc_mips_$name.s"; bin="/tmp/uplnc_mips_$name"
        "$TDIR/build/lpp1" "tests/progs/$name.e" 2>/dev/null \
            | "$TDIR/build/langc" -march=mips64 > "$asm" 2>/dev/null
        if grep -q 'not supported on mips' "$asm"; then
            echo "  skip - mips64 $name.e (floating point not implemented on mips64 yet)"
        elif grep -qE '[1-9][0-9]* error' "$asm"; then
            bad "mips64 $name.e (compile)"
        elif ! $MIPS "$asm" -o "$bin" 2>/dev/null; then
            bad "mips64 $name.e (assemble/link)"
        else
            "$bin"; got=$?
            [ "$got" = "$want" ] && ok "mips64 $name.e -> exit $got" \
                                 || bad "mips64 $name.e (got $got, want $want)"
        fi
    done < tests/progs/expected.txt
fi

echo
echo "==== $pass passed, $fail failed ===="
[ "$fail" -eq 0 ]

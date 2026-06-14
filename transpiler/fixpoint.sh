#!/usr/bin/env bash
# Self-host fixpoint check for the UPLNC compiler (BOOTSTRAP.md §4).
#
# Usage:  ./fixpoint.sh [i386|x86_64]      (default: i386)
#
# Three generations of the compiler are produced and their *output* compared:
#
#   stage-0  build/langc        the transpiled-C compiler (built by build.sh)
#   stage-1  langc1  = link( stage-0 compiling the UPLNC sources to .s )
#   stage-2  langc2  = link( langc1  compiling the sources )
#            (stage-3) .s        = langc2 compiling the sources
#
# A true self-hosting compiler is a fixpoint: langc1 and langc2 are both
# "self-built" compilers, so the assembly they emit must be byte-identical.
# Hence the acceptance test is  stage-2 .s == stage-3 .s.  We also report
# stage-1 vs stage-2 (whether the transpiled stage-0 already matches).
#
# Preprocessing uses the stage-0 lpp1 throughout: its output is deterministic,
# architecture-independent text, so holding it constant isolates langc's asm.
#
#   i386   : langc emits i386; assemble/link needs a 32-bit toolchain (-m32).
#   x86_64 : langc emits System V x86_64; links natively (gcc -no-pie). No -m32.
set -uo pipefail
cd "$(dirname "$0")"

ARCH="${1:-i386}"
BUILD="$(pwd)/build"
SRCDIR="$(cd ../src && pwd)"
LPP0="$BUILD/lpp1"
UNITS="langc codegen autodyn grph lpp1"
LINK="langc codegen autodyn grph"

die() { echo "fixpoint: $*" >&2; exit 1; }

# --- per-arch configuration ----------------------------------------------
case "$ARCH" in
i386)
    MARCH=""                       # langc default target is i386
    # Find a working 32-bit toolchain. The default 'gcc' may lack 32-bit libgcc
    # on some hosts, so fall back to a versioned gcc that has it.
    LINKER=""
    for cc in "gcc -m32" "gcc-12 -m32" "gcc-11 -m32" "gcc-10 -m32" "gcc-9 -m32"; do
        if echo 'int main(void){return 0;}' | $cc -x c - -o /dev/null 2>/dev/null; then
            LINKER="$cc -w"; break
        fi
    done
    if [ -z "$LINKER" ]; then
        cat >&2 <<'EOF'
fixpoint: i386 needs a 32-bit toolchain (gcc-multilib / libc6-dev-i386).
  Install it, or run the native x86_64 fixpoint instead:  ./fixpoint.sh x86_64
EOF
        exit 1
    fi
    ;;
x86_64)
    MARCH="-march=x86_64"
    LINKER="gcc -no-pie -w"        # backend emits non-PIC absolute addressing
    ;;
arm64)
    MARCH="-march=arm64"
    # Cross-assemble/link with the aarch64 toolchain (binaries run via qemu-user
    # binfmt on x86); on a native arm64 host the plain `gcc` targets aarch64.
    if command -v aarch64-linux-gnu-gcc >/dev/null; then
        LINKER="aarch64-linux-gnu-gcc -static -w"
    elif [ "$(uname -m)" = "aarch64" ]; then
        LINKER="gcc -no-pie -w"
    else
        die "arm64 needs gcc-aarch64-linux-gnu (+ qemu-user-static to run on x86)"
    fi
    ;;
*)
    die "unknown arch '$ARCH' (use i386, x86_64 or arm64)" ;;
esac
echo "fixpoint: target = $ARCH"

if [ ! -x "$BUILD/langc" ] || [ ! -x "$LPP0" ]; then
    echo "fixpoint: stage-0 tools missing; running build.sh ..."
    ./build.sh || die "build.sh failed"
fi

# --- helpers --------------------------------------------------------------
compile_stage() {                  # $1 = compiler  $2 = outdir
    local cc="$1" outdir="$2" u rc=0
    mkdir -p "$outdir"
    for u in $UNITS; do
        ( cd "$SRCDIR" && "$LPP0" "$u.e" 2>/dev/null ) \
            | "$cc" $MARCH > "$outdir/$u.s" 2>"$outdir/$u.err"
        if ! grep -q '0 error(s)' "$outdir/$u.s"; then
            echo "  !! $u.e failed to compile cleanly ($(basename "$cc"))"
            grep -E 'error\(s\)' "$outdir/$u.s" | tail -1 | sed 's/^/     /'
            rc=1
        fi
    done
    return $rc
}

link_langc() {                     # $1 = .s dir  $2 = output binary
    local d="$1" bin="$2" objs=""
    for u in $LINK; do objs="$objs $d/$u.s"; done
    $LINKER -o "$bin" $objs || die "link failed: $bin"
}

compare_stage() {                  # $1,$2 dirs; return 0 if all .s match
    local a="$1" b="$2" u allok=0
    for u in $UNITS; do
        if cmp -s "$a/$u.s" "$b/$u.s"; then
            echo "  ok    $u.s  identical"
        else
            echo "  DIFF  $u.s  differs ($(cmp "$a/$u.s" "$b/$u.s" 2>&1 | head -1))"
            allok=1
        fi
    done
    return $allok
}

# --- run the stages -------------------------------------------------------
S="$BUILD/$ARCH"   # keep arches' artifacts separate
echo "== stage 1: stage-0 langc compiles the sources -> s1/, link langc1"
compile_stage "$BUILD/langc"   "$S/s1" || die "stage-0 could not compile the sources"
link_langc    "$S/s1"          "$S/langc1"

echo "== stage 2: langc1 compiles the sources -> s2/, link langc2"
compile_stage "$S/langc1"      "$S/s2" || die "langc1 could not compile the sources"
link_langc    "$S/s2"          "$S/langc2"

echo "== stage 3: langc2 compiles the sources -> s3/"
compile_stage "$S/langc2"      "$S/s3" || die "langc2 could not compile the sources"

# --- compare --------------------------------------------------------------
echo
echo "-- stage-1 vs stage-2 (transpiled stage-0 vs self-built compiler):"
compare_stage "$S/s1" "$S/s2"; s12=$?
echo
echo "-- stage-2 vs stage-3  (THE fixpoint):"
compare_stage "$S/s2" "$S/s3"; s23=$?

echo
if [ "$s23" -eq 0 ]; then
    echo "FIXPOINT REACHED ($ARCH): langc reproduces its own assembly byte-for-byte."
    [ "$s12" -eq 0 ] \
        && echo "(stage-1 == stage-2 too: the transpiled stage-0 already matched.)" \
        || echo "(stage-1 differs from stage-2, which is fine; stage-0 is a separate" \
                "implementation. stage-2 == stage-3 is the fixpoint that counts.)"
    exit 0
else
    echo "NOT a fixpoint ($ARCH): stage-2 and stage-3 assembly differ."
    echo "Inspect e.g.:  diff $S/s2/langc.s $S/s3/langc.s"
    exit 1
fi

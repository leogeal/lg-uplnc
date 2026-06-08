#!/usr/bin/env bash
# Self-host fixpoint check for the UPLNC compiler (BOOTSTRAP.md §4).
#
# Three generations of the compiler are produced and their *output* compared:
#
#   stage-0  build/langc        the transpiled-C compiler (built by build.sh)
#   stage-1  langc1  = link( stage-0 compiling the UPLNC sources to i386 .s )
#   stage-2  langc2  = link( langc1  compiling the sources )
#            (stage-3) .s        = langc2 compiling the sources
#
# A true self-hosting compiler is a fixpoint: langc1 and langc2 are both
# "self-built" i386 compilers, so the assembly they emit must be byte-identical.
# Hence the acceptance test is  stage-2 .s  ==  stage-3 .s.  We also report
# stage-1 vs stage-2 (whether the transpiled stage-0 already matches the
# self-built compiler -- a stronger, nice-to-have result).
#
# Preprocessing is done by the stage-0 lpp1 at every stage: lpp1's output is
# deterministic, line-oriented text and architecture-independent, so holding it
# constant isolates langc's assembly as the thing under test.
#
# Requires a 32-bit toolchain (gcc-multilib / libc6-dev-i386) to assemble and run
# langc's i386 output. This sandbox lacks it; run this where -m32 works.
set -uo pipefail
cd "$(dirname "$0")"

BUILD="$(pwd)/build"
SRCDIR="$(cd ../src && pwd)"
LPP0="$BUILD/lpp1"                 # stage-0 preprocessor (used throughout)
UNITS="langc codegen autodyn grph lpp1"   # all units compiled + compared
LINK="langc codegen autodyn grph"         # units linked into a langc binary

die() { echo "fixpoint: $*" >&2; exit 1; }

# --- preconditions --------------------------------------------------------
if ! echo 'int main(void){return 0;}' | gcc -m32 -x c - -o /dev/null 2>/dev/null; then
    cat >&2 <<'EOF'
fixpoint: a 32-bit toolchain is required but unavailable.

  Install it, e.g. on Debian/Ubuntu:
      sudo apt-get install gcc-multilib libc6-dev-i386
  then re-run ./build.sh (it will use -m32) and ./fixpoint.sh.
EOF
    exit 1
fi

if [ ! -x "$BUILD/langc" ] || [ ! -x "$LPP0" ]; then
    echo "fixpoint: stage-0 tools missing; running build.sh ..."
    ./build.sh || die "build.sh failed"
fi

# --- helpers --------------------------------------------------------------
# compile every UPLNC unit to i386 .s using compiler $1, into directory $2
compile_stage() {
    local cc="$1" outdir="$2" u rc=0
    mkdir -p "$outdir"
    for u in $UNITS; do
        # preprocess from the src dir so lpp1's #include "x.he" resolves
        ( cd "$SRCDIR" && "$LPP0" "$u.e" 2>/dev/null ) \
            | "$cc" > "$outdir/$u.s" 2>"$outdir/$u.err"
        if ! grep -q '0 error(s)' "$outdir/$u.s"; then
            echo "  !! $u.e failed to compile cleanly ($(basename "$cc"))"
            grep -E 'error\(s\)' "$outdir/$u.s" | tail -1 | sed 's/^/     /'
            rc=1
        fi
    done
    return $rc
}

# link the four langc units in $1 into the binary $2
link_langc() {
    local d="$1" bin="$2" objs=""
    for u in $LINK; do objs="$objs $d/$u.s"; done
    gcc -m32 -w -o "$bin" $objs || die "link failed: $bin"
}

# byte-compare each unit's .s between dirs $1 and $2; echo result; return 0 if all match
compare_stage() {
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
echo "== stage 1: stage-0 langc compiles the sources -> s1/, link langc1"
compile_stage "$BUILD/langc"  "$BUILD/s1" || die "stage-0 could not compile the sources"
link_langc    "$BUILD/s1"     "$BUILD/langc1"

echo "== stage 2: langc1 compiles the sources -> s2/, link langc2"
compile_stage "$BUILD/langc1" "$BUILD/s2" || die "langc1 could not compile the sources"
link_langc    "$BUILD/s2"     "$BUILD/langc2"

echo "== stage 3: langc2 compiles the sources -> s3/"
compile_stage "$BUILD/langc2" "$BUILD/s3" || die "langc2 could not compile the sources"

# --- compare --------------------------------------------------------------
echo
echo "-- stage-1 vs stage-2 (transpiled stage-0 vs self-built compiler):"
compare_stage "$BUILD/s1" "$BUILD/s2"; s12=$?

echo
echo "-- stage-2 vs stage-3  (THE fixpoint):"
compare_stage "$BUILD/s2" "$BUILD/s3"; s23=$?

echo
if [ "$s23" -eq 0 ]; then
    echo "FIXPOINT REACHED: langc reproduces its own assembly byte-for-byte."
    [ "$s12" -eq 0 ] \
        && echo "(stage-1 == stage-2 too: the transpiled stage-0 already matched.)" \
        || echo "(stage-1 differed from stage-2, which is acceptable; stage-0 is a" \
                "separate implementation. The stage-2==stage-3 fixpoint is what counts.)"
    exit 0
else
    echo "NOT a fixpoint: stage-2 and stage-3 assembly differ (see DIFF lines)."
    echo "Inspect e.g.:  diff build/s2/langc.s build/s3/langc.s"
    exit 1
fi

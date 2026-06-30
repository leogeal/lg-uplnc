#!/usr/bin/env bash
# Phase-1 invariance oracle for the retargeting work (see ../RETARGET.md, M2).
#
# A behaviour-preserving refactor of the compiler must not change the i386
# assembly it emits. We can check that here WITHOUT a 32-bit toolchain, because
# we compare the emitted .s text (not linked binaries): build the stage-0 langc
# via uplnc2c (native 64-bit) and have it compile every unit.
#
#   ./invariance.sh record   build stage-0 and snapshot each unit's .s -> baseline
#   ./invariance.sh check    rebuild, re-emit, and diff against the baseline
#
# Workflow: `record` on the pristine tree, make a change, then `check`.
set -uo pipefail
cd "$(dirname "$0")"

TDIR="$(pwd)"
SRCDIR="$(cd ../src && pwd)"
BASE="build/invariance-baseline"
NOW="build/invariance-now"
UNITS="langc codegen autodyn grph lpp1"

emit() {                              # $1 = output dir
    ./build.sh >/dev/null 2>&1 || { echo "build failed" >&2; exit 1; }
    mkdir -p "$1"
    local outdir
    outdir="$(cd "$1" && pwd)"
    for u in $UNITS; do
        if ! ( cd "$SRCDIR" && "$TDIR/build/lpp1" "$u.e" > "$outdir/$u.pp" 2>"$outdir/$u.lpp.err" ); then
            echo "lpp1 failed on $u.e" >&2
            tail -5 "$outdir/$u.lpp.err" >&2
            exit 1
        fi
        "$TDIR/build/langc" < "$outdir/$u.pp" > "$outdir/$u.s" 2>/dev/null
    done
}

case "${1:-check}" in
record)
    emit "$BASE"
    echo "baseline recorded in transpiler/$BASE ($(ls "$BASE" | wc -l) units)"
    ;;
check)
    [ -d "$BASE" ] || { echo "no baseline; run: $0 record" >&2; exit 2; }
    emit "$NOW"
    # Compare emitted assembly with `#:` source-echo comments stripped: the
    # compiler echoes its input as `#:` comments, so editing a shared header
    # (e.g. tlangc.he) changes those lines in every includer without changing
    # codegen. The real invariant is the emitted instructions/labels/directives.
    rc=0
    for u in $UNITS; do
        if diff -q <(grep -v '^#:' "$BASE/$u.s") \
                   <(grep -v '^#:' "$NOW/$u.s") >/dev/null; then
            echo "  ok    $u.s  emitted asm identical"
        else
            echo "  DIFF  $u.s  emitted asm changed"
            rc=1
        fi
    done
    echo
    if [ $rc -eq 0 ]; then
        echo "INVARIANT: codegen output unchanged for every unit."
    else
        echo "CHANGED: emitted asm differs. Expected ONLY for a unit whose own .e"
        echo "you edited (e.g. langc.e); a DIFF in any other unit is a real"
        echo "behaviour change. Inspect: diff <(grep -v ^#: $BASE/UNIT.s) <(grep -v ^#: $NOW/UNIT.s)"
    fi
    exit $rc
    ;;
*)
    echo "usage: $0 {record|check}" >&2; exit 2 ;;
esac

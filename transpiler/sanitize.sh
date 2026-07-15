#!/usr/bin/env bash
# Build sanitizer-instrumented stage-0 tools and fuzz malformed source inputs.
set -euo pipefail
cd "$(dirname "$0")"

OUT=build/sanitize
CC_BIN="${UPLNC_SAN_CC:-${CC:-gcc}}"
SANITIZERS="${UPLNC_SANITIZERS:-address,undefined}"
mkdir -p "$OUT"

# build.sh owns the UPLNC-to-C translation and keeps all cross-unit return-type
# inference in one place. The sanitizer binaries themselves are always native.
UPLNC_NATIVE=1 ./build.sh

COMMON=(
    -std=gnu89
    -fsigned-char
    -w
    -g
    -O1
    -fno-omit-frame-pointer
    -fno-sanitize-recover=all
    "-fsanitize=$SANITIZERS"
)

echo "[sanitize] compiling lpp1 with $CC_BIN ($SANITIZERS)"
"$CC_BIN" "${COMMON[@]}" -o "$OUT/lpp1" build/lpp1.c

echo "[sanitize] compiling langc with $CC_BIN ($SANITIZERS)"
"$CC_BIN" "${COMMON[@]}" -o "$OUT/langc" \
    build/langc.c build/codegen.c build/autodyn.c build/grph.c

# LeakSanitizer cannot run under some tracing sandboxes. Callers that can use it
# should override this, as CI does.
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0:halt_on_error=1}"
export UBSAN_OPTIONS="${UBSAN_OPTIONS:-halt_on_error=1:print_stacktrace=1}"

python3 -m unittest fuzz.test_fuzz

exec python3 fuzz/fuzz.py \
    --lpp "$OUT/lpp1" \
    --langc "$OUT/langc" \
    "$@"

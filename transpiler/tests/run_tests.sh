#!/usr/bin/env bash
# Smoke + functional tests for the uplnc2c transpiler.
set -uo pipefail
cd "$(dirname "$0")/.."

SRC=../src
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

echo
echo "==== $pass passed, $fail failed ===="
[ "$fail" -eq 0 ]

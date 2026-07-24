#!/usr/bin/env bash
# Smoke + functional tests for the uplnc2c transpiler.
set -uo pipefail
cd "$(dirname "$0")/.."

TDIR=$(pwd)              # absolute transpiler dir (for tools)
SRC=../src
SRCDIR=$(cd "$SRC" && pwd)
DRIVER="$SRCDIR/langdrv.pl"
fail=0
pass=0
ok()   { echo "  ok   - $1"; pass=$((pass+1)); }
bad()  { echo "  FAIL - $1"; fail=$((fail+1)); }
TMPD=$(mktemp -d "${TMPDIR:-/tmp}/uplnc-tests.XXXXXX")
trap 'rm -rf "$TMPD"' EXIT

buildgrep() { # $1 = target, $2 = output binary
    perl "$DRIVER" "-march=$1" -o "$2" \
        ../examples/grep.e ../examples/grep_match.e ../lib/fmt.e
}

buildsort() { # $1 = target, $2 = output binary
    perl "$DRIVER" "-march=$1" -o "$2" \
        ../examples/sort.e ../examples/sort_lines.e ../examples/sort_order.e
}

buildcalc() { # $1 = target, $2 = output binary
    perl "$DRIVER" "-march=$1" -o "$2" ../examples/calc.e ../lib/fmt.e
}

# one FP-heavy calc line per backend: %f formatting and IEEE inf must agree
# with the pinned host transcript byte-for-byte on every target
checkcalc() { # $1 = target label, $2 = binary, $3 = runner prefix (may be "")
    local got want rc
    got=$(printf 'x = 2.5\n3*(x-0.5)-1\n0.1+0.2\n1/0\n' | $3 "$2")
    rc=$?
    want=$(printf '2.500000\n5\n0.300000\ninf\n')
    [ "$rc" = 0 ] && [ "$got" = "$want" ] \
        && ok "$1 calc evaluates FP identically" \
        || bad "$1 calc FP evaluation"
}

gatebenches() { # $1 = target whose toolchain/runner was proven above
    local arch="$1" log="$TMPD/uplnc_bench_$1.log"
    if bash bench/bench.sh --target "$arch" --no-time --require-run >"$log" 2>&1; then
        ok "$arch benchmark kernels compile, run, and self-check"
    else
        bad "$arch benchmark kernels"
        tail -8 "$log" | sed 's/^/         /'
    fi
}

echo "[1] transpile every UPLNC source without error"
for f in tlangc.he codegen.he lpp1.e codegen.e langc.e autodyn.e grph.e; do
    if python3 uplnc2c.py "$SRC/$f" -I "$SRC/tlangc.he" -I "$SRC/codegen.he" \
            >/dev/null 2>"$TMPD/uplnc2c.err"; then
        ok "transpile $f"
    else
        bad "transpile $f -> $(tail -1 "$TMPD/uplnc2c.err")"
    fi
done

echo "[2] build the stage-0 tools"
if ./build.sh >"$TMPD/uplnc_build.log" 2>&1; then
    ok "build.sh"
else
    bad "build.sh (see $TMPD/uplnc_build.log)"
fi

echo "[2b] compiler driver handles build modes and multi-file programs"
case "$(uname -m)" in
    x86_64)  DRVARCH=x86_64 ;;
    i?86)    DRVARCH=i386 ;;
    aarch64) DRVARCH=arm64 ;;
    riscv64) DRVARCH=riscv64 ;;
    mips64)  DRVARCH=mips64 ;;
    *)       DRVARCH=x86_64 ;;
esac
DRVSPACE="$TMPD/uplnc driver space"
mkdir -p "$DRVSPACE"
printf 'func main(){return 42;}\n' > "$DRVSPACE/hello world.e"
if (cd "$DRVSPACE" && perl "$DRIVER" "-march=$DRVARCH" -o "hello world" "hello world.e" \
        >driver.out 2>driver.err); then
    "$DRVSPACE/hello world"; rc=$?
    [ "$rc" = 42 ] && ok "driver links a source whose path contains spaces" \
                       || bad "driver linked program exits $rc, want 42"
    if [ ! -s "$DRVSPACE/driver.out" ] && ! grep -q '^+ ' "$DRVSPACE/driver.err"; then
        ok "driver is quiet by default"
    else
        bad "driver is quiet by default"
    fi
else
    bad "driver links a source whose path contains spaces"
fi

if (cd "$DRVSPACE" && perl "$DRIVER" "-march=$DRVARCH" -S -o "hello world.s" "hello world.e" \
        >driver_S.out 2>driver_S.err) && grep -q '^main:' "$DRVSPACE/hello world.s"; then
    ok "driver -S emits assembly"
else
    bad "driver -S emits assembly"
fi
if (cd "$DRVSPACE" && perl "$DRIVER" "-march=$DRVARCH" -c -o "hello world.o" "hello world.s" \
        >driver_c.out 2>driver_c.err) && [ -s "$DRVSPACE/hello world.o" ]; then
    ok "driver -c assembles to an object"
else
    bad "driver -c assembles to an object"
fi
if (cd "$DRVSPACE" && perl "$DRIVER" "-march=$DRVARCH" -o relink "hello world.o" \
        >driver_obj.out 2>driver_obj.err); then
    "$DRVSPACE/relink"; rc=$?
    [ "$rc" = 42 ] && ok "driver links an existing object" \
                       || bad "driver object link exits $rc, want 42"
else
    bad "driver links an existing object"
fi

if perl "$DRIVER" "-march=$DRVARCH" -o "$DRVSPACE/fmtdemo" \
        ../examples/fmtdemo.e ../lib/fmt.e >"$DRVSPACE/multi.out" 2>"$DRVSPACE/multi.err" \
        && timeout 5 "$DRVSPACE/fmtdemo" >"$DRVSPACE/fmtdemo.out" \
        && grep -q '^int: 42 -7 0$' "$DRVSPACE/fmtdemo.out"; then
    ok "driver compiles and links multiple UPLNC sources"
else
    bad "driver compiles and links multiple UPLNC sources"
fi

printf 'func main(){return (1 + ;}\n' > "$DRVSPACE/bad.e"
printf 'preserve-existing-output\n' > "$DRVSPACE/bad.s"
if perl "$DRIVER" "-march=$DRVARCH" -S -o "$DRVSPACE/bad.s" "$DRVSPACE/bad.e" \
        >"$DRVSPACE/bad.out" 2>"$DRVSPACE/bad.err"; then
    bad "driver propagates compiler failure"
elif grep -q "compiling .*bad.e.* failed" "$DRVSPACE/bad.err"; then
    ok "driver propagates compiler failure"
else
    bad "driver compiler failure diagnostic"
fi
if grep -qx 'preserve-existing-output' "$DRVSPACE/bad.s"; then
    ok "driver preserves an existing output after failure"
else
    bad "driver preserves an existing output after failure"
fi

if perl "$DRIVER" "-march=$DRVARCH" -c -o "$DRVSPACE/both.o" \
        "$DRVSPACE/hello world.e" "$DRVSPACE/bad.e" \
        >"$DRVSPACE/invalid.out" 2>"$DRVSPACE/invalid.err"; then
    bad "driver rejects one -o output for multiple -c inputs"
elif grep -q 'requires exactly one input' "$DRVSPACE/invalid.err"; then
    ok "driver rejects one -o output for multiple -c inputs"
else
    bad "driver multiple-input -o diagnostic"
fi

if (cd "$DRVSPACE" && perl "$DRIVER" -v "-march=$DRVARCH" -S -o verbose.s "hello world.e" \
        >verbose.out 2>verbose.err) \
        && grep -q '^+ .*lpp1' "$DRVSPACE/verbose.err" \
        && grep -q "^+ .*langc.*-march=$DRVARCH" "$DRVSPACE/verbose.err"; then
    ok "driver -v reports the frontend commands"
else
    bad "driver -v reports the frontend commands"
fi

echo "[3] lpp1 preprocessor behaves correctly"
LPP=build/lpp1
if [ -x "$LPP" ]; then
    out=$("$LPP" tests/pp_input.e 2>/dev/null)
    echo "$out" | grep -q 'int hello\[3\];'        && ok "macro substitution (GREETING/N)" || bad "macro substitution"
    echo "$out" | grep -q 'literal #define stays'  && ok "string literals preserved"        || bad "string literals"
    echo "$out" | grep -vq 'a comment'             && ok "comments stripped"                 || bad "comments stripped"

    longid=abcdefghijklmnopq
    printf '#define %s 1\n' "$longid" > "$TMPD/uplnc_pp_longid.e"
    if "$LPP" "$TMPD/uplnc_pp_longid.e" > "$TMPD/uplnc_pp_longid.out" 2>"$TMPD/uplnc_pp_longid.err"; then
        bad "lpp1 long identifier exits nonzero"
    elif grep -q 'identifier too long' "$TMPD/uplnc_pp_longid.err"; then
        ok "lpp1 long identifier diagnosed"
    else
        bad "lpp1 long identifier diagnostic"
    fi

    longline=$(printf '%0170d' 0 | tr 0 ';')
    printf '%s\n' "$longline" > "$TMPD/uplnc_pp_longline.e"
    if "$LPP" "$TMPD/uplnc_pp_longline.e" > "$TMPD/uplnc_pp_longline.out" 2>"$TMPD/uplnc_pp_longline.err"; then
        bad "lpp1 long line exits nonzero"
    elif grep -q 'input line too long' "$TMPD/uplnc_pp_longline.err"; then
        ok "lpp1 long line diagnosed"
    else
        bad "lpp1 long line diagnostic"
    fi

    # Quoted includes resolve relative to the including file, independently of cwd.
    RELINC="$TMPD/uplnc_relinc/abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmnopqrstuvwxyz"
    mkdir -p "$RELINC"
    printf '#define RELVALUE 42\n' > "$RELINC/value.he"
    printf '#include "value.he"\nfunc main(){return RELVALUE;}\n' > "$RELINC/main.e"
    if "$LPP" "$RELINC/main.e" > "$TMPD/uplnc_relinc.out" 2>"$TMPD/uplnc_relinc.err" \
            && grep -q 'return 42' "$TMPD/uplnc_relinc.out"; then
        ok "lpp1 quoted include is relative to the including file"
    else
        bad "lpp1 relative quoted include"
    fi
    printf '#include "missing.he"\n' > "$RELINC/missing_main.e"
    if "$LPP" "$RELINC/missing_main.e" > /dev/null 2>"$TMPD/uplnc_relmissing.err"; then
        bad "lpp1 missing relative include exits nonzero"
    elif grep -Fq "$RELINC/missing_main.e:1:" "$TMPD/uplnc_relmissing.err"; then
        ok "lpp1 missing include is attributed to the including file"
    else
        bad "lpp1 missing include location"
    fi
else
    bad "lpp1 not built"
fi

echo "[4] langc compiles a program to i386 assembly"
LANGC=build/langc
if [ -x "$LANGC" ] && [ -x "$LPP" ]; then
    # a+2 with a variable (constant folding would collapse a literal 40+2 to 42)
    printf 'func main()\n{\n  var int:a;\n  var int:x;\n  a=40;\n  x=a+2;\n  return x;\n}\n' > "$TMPD/uplnc_t1.e"
    asm=$("$LPP" "$TMPD/uplnc_t1.e" 2>/dev/null | "$LANGC" 2>/dev/null)
    echo "$asm" | grep -q '^main:'           && ok "emits a 'main:' label"        || bad "emits 'main:'"
    echo "$asm" | grep -q 'addl %edx, %eax'  && ok "compiles a+2 to add"          || bad "compiles a+2"
    echo "$asm" | grep -qE '(^|[^0-9])0 error\(s\)'       && ok "reports 0 errors"             || bad "reports 0 errors"
else
    bad "langc not built"
fi

echo "[4b] langc rejects malformed input without crashing"
if [ -x "$LANGC" ] && [ -x "$LPP" ]; then
    printf 'func main(){ return (1 + ; }\n' > "$TMPD/uplnc_bad_syntax.e"
    if "$LPP" "$TMPD/uplnc_bad_syntax.e" 2>/dev/null \
            | "$LANGC" -march=x86_64 > "$TMPD/uplnc_bad_syntax.s" 2>"$TMPD/uplnc_bad_syntax.err"; then
        bad "bad syntax exits nonzero"
    elif grep -q 'Error:wrong expression' "$TMPD/uplnc_bad_syntax.s"; then
        ok "bad syntax exits nonzero"
    else
        bad "bad syntax diagnostic"
    fi

    printf 'func main(){var == 1;}\n' > "$TMPD/uplnc_bad_local_init.e"
    if "$LPP" "$TMPD/uplnc_bad_local_init.e" 2>/dev/null \
            | "$LANGC" -march=x86_64 > "$TMPD/uplnc_bad_local_init.s" 2>"$TMPD/uplnc_bad_local_init.err"; then
        bad "nameless local initializer exits nonzero"
    elif grep -q 'expected name of variable' "$TMPD/uplnc_bad_local_init.err"; then
        ok "nameless local initializer rejected without a store"
    else
        bad "nameless local initializer diagnostic"
    fi

    printf "func main(){ return 'unterminated; }\n" > "$TMPD/uplnc_bad_char.e"
    timeout 5 "$LANGC" -march=x86_64 > "$TMPD/uplnc_bad_char.s" 2>"$TMPD/uplnc_bad_char.err" \
        < "$TMPD/uplnc_bad_char.e"
    rc=$?
    if [ "$rc" = 124 ]; then
        bad "unterminated char literal does not hang"
    elif [ "$rc" = 0 ]; then
        bad "unterminated char literal exits nonzero"
    elif grep -q 'unterminated char const' "$TMPD/uplnc_bad_char.s"; then
        ok "unterminated char literal diagnosed"
    else
        bad "unterminated char literal diagnostic"
    fi

    printf 'func main(){ if(1){\n' > "$TMPD/uplnc_missing_brace.e"
    if "$LANGC" -march=x86_64 > "$TMPD/uplnc_missing_brace.s" 2>"$TMPD/uplnc_missing_brace.err" \
            < "$TMPD/uplnc_missing_brace.e"; then
        bad "missing nested brace exits nonzero"
    elif grep -q "missing '}'" "$TMPD/uplnc_missing_brace.s"; then
        ok "missing nested brace diagnosed"
    else
        bad "missing nested brace diagnostic"
    fi

    longnum=$(printf '%0200d' 0 | tr 0 1)
    printf 'func main(){ return %s; }\n' "$longnum" > "$TMPD/uplnc_long_numeric.e"
    if "$LPP" "$TMPD/uplnc_long_numeric.e" 2>/dev/null \
            | "$LANGC" -march=x86_64 > "$TMPD/uplnc_long_numeric.s" 2>"$TMPD/uplnc_long_numeric.err"; then
        bad "long numeric literal exits nonzero"
    elif grep -q 'numeric literal too long' "$TMPD/uplnc_long_numeric.s"; then
        ok "long numeric literal diagnosed"
    else
        bad "long numeric literal diagnostic"
    fi

    longfrac=$(printf '%044d' 0 | tr 0 2)
    {
        printf 'func main(){\n'
        for _ in $(seq 1 120); do printf '  return 1.%s;\n' "$longfrac"; done
        printf '}\n'
    } > "$TMPD/uplnc_float_pool.e"
    if "$LPP" "$TMPD/uplnc_float_pool.e" 2>/dev/null \
            | "$LANGC" -march=x86_64 > "$TMPD/uplnc_float_pool.s" 2>"$TMPD/uplnc_float_pool.err"; then
        bad "float literal pool overflow exits nonzero"
    elif grep -q 'float literal pool full' "$TMPD/uplnc_float_pool.s"; then
        ok "float literal pool overflow diagnosed"
    else
        bad "float literal pool overflow diagnostic"
    fi

    longid=abcdefghijklmnopq
    printf 'func main(){ var int:%s; return 0; }\n' "$longid" > "$TMPD/uplnc_long_ident.e"
    if "$LANGC" -march=x86_64 > "$TMPD/uplnc_long_ident.s" 2>"$TMPD/uplnc_long_ident.err" \
            < "$TMPD/uplnc_long_ident.e"; then
        bad "long identifier exits nonzero"
    elif grep -q 'identifier too long' "$TMPD/uplnc_long_ident.s"; then
        ok "long identifier diagnosed"
    else
        bad "long identifier diagnostic"
    fi

    strchunk=$(printf '%0100d' 0 | tr 0 a)
    {
        printf 'func main(){\n'
        for _ in $(seq 1 180); do printf '  "%s";\n' "$strchunk"; done
        printf '  return 0;\n}\n'
    } > "$TMPD/uplnc_string_pool.e"
    if "$LPP" "$TMPD/uplnc_string_pool.e" 2>/dev/null \
            | "$LANGC" -march=x86_64 > "$TMPD/uplnc_string_pool.s" 2>"$TMPD/uplnc_string_pool.err"; then
        bad "string literal pool overflow exits nonzero"
    elif grep -q 'string space exhausted' "$TMPD/uplnc_string_pool.s"; then
        ok "string literal pool overflow diagnosed"
    else
        bad "string literal pool overflow diagnostic"
    fi

    printf 'func main(){return 0;} /* unterminated\n' > "$TMPD/uplnc_bad_comment.e"
    if "$LPP" "$TMPD/uplnc_bad_comment.e" > "$TMPD/uplnc_bad_comment.pp" 2>"$TMPD/uplnc_bad_comment.err"; then
        bad "unterminated block comment exits nonzero"
    elif grep -q 'unterminated comment' "$TMPD/uplnc_bad_comment.err"; then
        ok "unterminated block comment diagnosed"
    else
        bad "unterminated block comment diagnostic"
    fi

    # A call with >32 arguments including a floating-point one used to overrun a
    # fixed [32] type array in ct_FUNC and stack-smash (SIGABRT).  It must now
    # error cleanly -- a normal nonzero exit, never a signal (>=128).
    printf 'func f();\nfunc main(){return f(1.0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1);}\n' > "$TMPD/uplnc_manyarg.e"
    "$LPP" "$TMPD/uplnc_manyarg.e" 2>/dev/null | "$LANGC" -march=x86_64 > "$TMPD/uplnc_manyarg.s" 2>/dev/null
    rc=$?
    if [ "$rc" -ge 128 ]; then
        bad "many-arg FP call crashes langc (signal $((rc-128)))"
    elif grep -qE '[1-9][0-9]* error' "$TMPD/uplnc_manyarg.s"; then
        ok "many-arg FP call errors cleanly (no arg-array overflow)"
    else
        bad "many-arg FP call: expected clean arg-count error"
    fi

    # a write to a const array element must be rejected (const-safety hole fix)
    printf 'func main(){var const [4]int:a;a[0]=9;return a[0];}\n' > "$TMPD/uplnc_constarr.e"
    "$LPP" "$TMPD/uplnc_constarr.e" 2>/dev/null | "$LANGC" -march=x86_64 > "$TMPD/uplnc_constarr.s" 2>/dev/null
    if grep -q 'const array element' "$TMPD/uplnc_constarr.s"; then
        ok "const array element write rejected"
    else
        bad "const array element write rejected"
    fi

    # const parameters: assignment and ++/-- on a const param are rejected
    printf 'func f(const a:int){a=5;return a;}\nfunc main(){return f(1);}\n' > "$TMPD/uplnc_constpar.e"
    "$LPP" "$TMPD/uplnc_constpar.e" 2>/dev/null | "$LANGC" -march=x86_64 > "$TMPD/uplnc_constpar.s" 2>/dev/null
    if grep -q 'assignment to a const variable' "$TMPD/uplnc_constpar.s"; then
        ok "const parameter write rejected"
    else
        bad "const parameter write rejected"
    fi
    printf 'func f(const a:int){a++;return a;}\nfunc main(){return f(1);}\n' > "$TMPD/uplnc_constpar2.e"
    "$LPP" "$TMPD/uplnc_constpar2.e" 2>/dev/null | "$LANGC" -march=x86_64 > "$TMPD/uplnc_constpar2.s" 2>/dev/null
    if grep -q 'modifying a const variable' "$TMPD/uplnc_constpar2.s"; then
        ok "const parameter ++ rejected"
    else
        bad "const parameter ++ rejected"
    fi

    # aggregate params must be rejected: the callee would lay them out by value
    # while the caller passes a pointer -- silent garbage pre-fix (PR #86 review)
    printf 'struct pr{int a;int b;};\nfunc f(p:pr){return p.a;}\nfunc main(){var s:pr;s.a=1;return f(s);}\n' > "$TMPD/uplnc_structpar.e"
    if "$LPP" "$TMPD/uplnc_structpar.e" 2>/dev/null \
            | "$LANGC" -march=x86_64 > "$TMPD/uplnc_structpar.s" 2>"$TMPD/uplnc_structpar.err"; then
        bad "struct parameter rejection exits nonzero"
    elif grep -q 'struct parameters are not supported' "$TMPD/uplnc_structpar.err"; then
        ok "struct parameter rejected"
    else
        bad "struct parameter rejection diagnostic"
    fi
    printf 'func f(a:[2]int){return a[0];}\nfunc main(){var [2]int:v;v[0]=1;return f(v);}\n' > "$TMPD/uplnc_arrpar.e"
    if "$LPP" "$TMPD/uplnc_arrpar.e" 2>/dev/null \
            | "$LANGC" -march=x86_64 > "$TMPD/uplnc_arrpar.s" 2>"$TMPD/uplnc_arrpar.err"; then
        bad "array parameter rejection exits nonzero"
    elif grep -q 'array parameters are not supported' "$TMPD/uplnc_arrpar.err"; then
        ok "array parameter rejected"
    else
        bad "array parameter rejection diagnostic"
    fi

    # error recovery (diagnostics part 2): one broken declaration = ONE error
    # (used to cascade, and inside a function it used to hang the parser)
    printf 'func main()\n{\n  var broken banana:int;\n  return 0;\n}\n' > "$TMPD/uplnc_rcv1.e"
    "$LPP" "$TMPD/uplnc_rcv1.e" 2>/dev/null | timeout 5 "$LANGC" -march=x86_64 > "$TMPD/uplnc_rcv1.s" 2>/dev/null
    rc=$?
    n=$(grep -c 'Error:' "$TMPD/uplnc_rcv1.s")
    if [ "$rc" = 124 ]; then bad "broken declaration does not hang"
    elif [ "$rc" = 0 ]; then bad "broken declaration exits nonzero"
    elif [ "$n" = 1 ]; then ok "broken declaration: exactly one error"
    else bad "broken declaration: one error (got $n)"; fi

    # unrecognized tokens: recover at the statement boundary, never loop
    printf 'func main()\n{\n  var x:int = 1;\n  @@@;\n  x = 2;\n  return x;\n}\n' > "$TMPD/uplnc_rcv2.e"
    "$LPP" "$TMPD/uplnc_rcv2.e" 2>/dev/null | timeout 5 "$LANGC" -march=x86_64 > "$TMPD/uplnc_rcv2.s" 2>/dev/null
    rc=$?
    if [ "$rc" = 124 ]; then bad "garbage statement does not hang"
    elif [ "$rc" = 0 ]; then bad "garbage statement exits nonzero"
    else ok "garbage statement recovered without hanging"; fi

    # If an erroneous statement already consumed its semicolon, recovery must
    # not skip the following statement. Both const writes must be diagnosed.
    printf 'func main(){var const int:x=1;var const int:y=1;x=2;y=3;return 0;}\n' > "$TMPD/uplnc_rcv3.e"
    "$LPP" "$TMPD/uplnc_rcv3.e" 2>/dev/null \
        | "$LANGC" -march=x86_64 > "$TMPD/uplnc_rcv3.s" 2>"$TMPD/uplnc_rcv3.err"
    n=$(grep -c 'assignment to a const variable' "$TMPD/uplnc_rcv3.err")
    [ "$n" = 2 ] && ok "recovery preserves the statement after a completed error" \
                   || bad "recovery skipped a following statement (got $n errors)"

    # switch has its own statement loop, so it needs the same recovery hook.
    printf 'func main(){switch(1){case 1:@@@;break;}return 0;}\n' > "$TMPD/uplnc_rcvsw.e"
    "$LPP" "$TMPD/uplnc_rcvsw.e" 2>/dev/null \
        | timeout 5 "$LANGC" -march=x86_64 > "$TMPD/uplnc_rcvsw.s" 2>/dev/null
    rc=$?
    n=$(grep -c 'Error:' "$TMPD/uplnc_rcvsw.s")
    if [ "$rc" = 124 ]; then bad "switch garbage does not hang"
    elif [ "$n" -lt 30 ] && ! grep -q 'too many errors' "$TMPD/uplnc_rcvsw.s"; then
        ok "switch statement recovery avoids the error flood cap"
    else bad "switch statement recovery (got $n errors)"; fi

    # error flood cap: pathological input stops at 30 with a clear message
    { printf 'func main()\n{\n'; for _ in $(seq 1 50); do printf '  var broken banana:int;\n'; done; printf '  return 0;\n}\n'; } > "$TMPD/uplnc_flood.e"
    "$LPP" "$TMPD/uplnc_flood.e" 2>/dev/null | timeout 5 "$LANGC" -march=x86_64 > "$TMPD/uplnc_flood.s" 2>/dev/null
    rc=$?
    if [ "$rc" = 124 ]; then bad "error flood does not hang"
    elif [ "$rc" = 0 ]; then bad "error flood exits nonzero"
    elif grep -q 'too many errors, giving up' "$TMPD/uplnc_flood.s"; then
        ok "error flood capped with a clear message"
    else bad "error flood cap"; fi

    # warnings: located, never fail the compile, and the output still runs
    printf 'func main()\n{\n  var dead:int;\n  var x:int = 41;\n  x == 42;\n  return x+1;\n}\n' > "$TMPD/uplnc_warn.e"
    if "$LPP" "$TMPD/uplnc_warn.e" 2>/dev/null | "$LANGC" -march=x86_64 > "$TMPD/uplnc_warn.s" 2>"$TMPD/uplnc_warn.err"; then
        grep -q ":3: Warning:unused variable 'dead'" "$TMPD/uplnc_warn.err" \
            && ok "unused-variable warning located at the declaration" || bad "unused-variable warning"
        grep -q ':5: Warning:comparison result is not used' "$TMPD/uplnc_warn.err" \
            && ok "no-effect comparison statement warned" || bad "no-effect comparison warning"
        grep -q '2 warning(s)' "$TMPD/uplnc_warn.s" \
            && ok "warning count summarized" || bad "warning summary"
    else
        bad "warnings alone must not fail the compile"
    fi

    # Deferred unused-variable warnings retain both the declaration file and line.
    printf '  var incdead:int;\n' > "$TMPD/uplnc_warn_inc.he"
    printf 'func main()\n{\n#include "uplnc_warn_inc.he"\n  return 0;\n}\n' > "$TMPD/uplnc_warn_outer.e"
    if "$LPP" "$TMPD/uplnc_warn_outer.e" 2>/dev/null \
            | "$LANGC" -march=x86_64 > "$TMPD/uplnc_warn_inc.s" 2>"$TMPD/uplnc_warn_inc.err"; then
        grep -Fq "$TMPD/uplnc_warn_inc.he:1: Warning:unused variable 'incdead'" "$TMPD/uplnc_warn_inc.err" \
            && ok "unused-variable warning retains the declaration file" \
            || bad "unused-variable warning declaration file"
    else
        bad "include-local warning must not fail the compile"
    fi

    # duplicate case labels must be diagnosed
    printf 'func main(){var int:x;x=1;switch(x){case 1:return 7;case 1:return 8;}return 0;}\n' > "$TMPD/uplnc_dupcase.e"
    "$LPP" "$TMPD/uplnc_dupcase.e" 2>/dev/null | "$LANGC" -march=x86_64 > "$TMPD/uplnc_dupcase.s" 2>/dev/null
    if grep -q 'duplicate case' "$TMPD/uplnc_dupcase.s"; then
        ok "duplicate case value diagnosed"
    else
        bad "duplicate case value diagnosed"
    fi

    # line-numbered diagnostics: errors carry <file>:<line> from lpp1's markers,
    # correct across an #include boundary and after returning from it
    printf '#define OK 1\n\nvar bad bad:int;\n' > "$TMPD/uplnc_loc.he"
    printf '#include "uplnc_loc.he"\nfunc main()\n{\n  var x:int = OK;\n  y = 2;\n  return x;\n}\n' > "$TMPD/uplnc_loc.e"
    (cd "$TMPD" && "$TDIR/build/lpp1" uplnc_loc.e 2>/dev/null) \
        | "$LANGC" -march=x86_64 > "$TMPD/uplnc_loc.s" 2>"$TMPD/uplnc_loc.err"
    grep -q 'uplnc_loc.he:3:' "$TMPD/uplnc_loc.err" && ok "error located in the include (file:line)" \
                                                    || bad "error located in the include"
    grep -q 'uplnc_loc.e:5:' "$TMPD/uplnc_loc.err"  && ok "error located after the include resync" \
                                                    || bad "error located after the include resync"

    # On register targets, user-defined variadic functions expose only the
    # register tail as a contiguous vastart() area. Calls that spill variadic
    # args to the stack must error instead of silently reading the wrong slots.
    printf 'func sum(n:int,...){var p:*int;var s:int;var i:int;p=vastart();s=0;i=0;while(i<n){s=s+p[i];i++;}return s;}\nfunc main(){return sum(7,1,2,3,4,5,6,7);}\n' > "$TMPD/uplnc_varargs_many.e"
    if "$LPP" "$TMPD/uplnc_varargs_many.e" 2>/dev/null \
            | "$LANGC" -march=x86_64 > "$TMPD/uplnc_varargs_many.s" 2>"$TMPD/uplnc_varargs_many.err"; then
        bad "variadic call with spilled args exits nonzero"
    elif grep -q 'variadic call' "$TMPD/uplnc_varargs_many.s"; then
        ok "variadic call with spilled args diagnosed"
    else
        bad "variadic call with spilled args diagnostic"
    fi

    # FP varargs travel as raw bits in the integer slots (see vararg_fp.e for
    # the cross-target run check); the call site must compile and marshal the
    # double through the integer registers, never %xmm (whose bits the
    # variadic callee's integer va-area spill would drop).
    printf 'func first(...){var p:*int;var dp:*double;p=vastart();dp=p;if(*dp==1.5)return 42;return 1;}\nfunc main(){return first(1.5);}\n' > "$TMPD/uplnc_varargs_fp.e"
    if "$LPP" "$TMPD/uplnc_varargs_fp.e" 2>/dev/null \
            | "$LANGC" -march=x86_64 > "$TMPD/uplnc_varargs_fp.s" 2>"$TMPD/uplnc_varargs_fp.err" \
            && ! grep -q 'movsd.*%xmm0, %xmm' "$TMPD/uplnc_varargs_fp.s" \
            && grep -qE 'movq [0-9]*\(%rsp\), %rdi' "$TMPD/uplnc_varargs_fp.s"; then
        ok "floating-point variadic arg marshals through integer registers"
    else
        bad "floating-point variadic arg marshaling"
    fi
    # typed-method diagnostics: the slot is authoritative; definitions must
    # agree, non-scalar returns and duplicate type forms are rejected, and an
    # unknown method is a compile-time error instead of a link failure.
    printf 'struct s{func m:double;};\nmethod s.m():int{return 1;}\nfunc main(){return 0;}\n' > "$TMPD/uplnc_meth1.e"
    "$LPP" "$TMPD/uplnc_meth1.e" 2>/dev/null | "$LANGC" -march=x86_64 >/dev/null 2>"$TMPD/uplnc_meth1.err"
    [ "$?" != 0 ] && grep -q 'conflicts with its struct declaration' "$TMPD/uplnc_meth1.err" \
        && ok "method definition/slot return-type conflict diagnosed" \
        || bad "method return-type conflict diagnostic"
    printf 'struct t{int v;};\nstruct s{func m:t;};\nfunc main(){return 0;}\n' > "$TMPD/uplnc_meth2.e"
    "$LPP" "$TMPD/uplnc_meth2.e" 2>/dev/null | "$LANGC" -march=x86_64 >/dev/null 2>"$TMPD/uplnc_meth2.err"
    [ "$?" != 0 ] && grep -q 'struct-returning method' "$TMPD/uplnc_meth2.err" \
        && ok "struct-returning method slot rejected" \
        || bad "struct-returning method diagnostic"
    printf 'struct s{int v;func m;};\nmethod s.m(){return 0;}\nfunc main(){var x:s;return x.nosuch();}\n' > "$TMPD/uplnc_meth3.e"
    "$LPP" "$TMPD/uplnc_meth3.e" 2>/dev/null | "$LANGC" -march=x86_64 >/dev/null 2>"$TMPD/uplnc_meth3.err"
    [ "$?" != 0 ] && grep -q 'no such method' "$TMPD/uplnc_meth3.err" \
        && ok "unknown method call diagnosed at compile time" \
        || bad "unknown method diagnostic"
    printf 'struct s{func m:[2]int;};\nfunc main(){return 0;}\n' > "$TMPD/uplnc_meth4.e"
    "$LPP" "$TMPD/uplnc_meth4.e" 2>/dev/null | "$LANGC" -march=x86_64 >/dev/null 2>"$TMPD/uplnc_meth4.err"
    [ "$?" != 0 ] && grep -q 'array-returning method' "$TMPD/uplnc_meth4.err" \
        && ok "array-returning method slot rejected" \
        || bad "array-returning method diagnostic"
    printf 'struct s{func int m:double;};\nfunc main(){return 0;}\n' > "$TMPD/uplnc_meth5.e"
    "$LPP" "$TMPD/uplnc_meth5.e" 2>/dev/null | "$LANGC" -march=x86_64 >/dev/null 2>"$TMPD/uplnc_meth5.err"
    [ "$?" != 0 ] && grep -q 'method return type given twice' "$TMPD/uplnc_meth5.err" \
        && ok "method slot with two return types rejected" \
        || bad "duplicate method return-type diagnostic"
    # i386 vastart() walks 4-byte slots; an 8-byte variadic integer would
    # misalign every following argument, so reject it at the known call site.
    printf 'func first(...){var p:*int;p=vastart();return p[0]+p[1];}\nfunc main(){return first(4294967295,42);}\n' > "$TMPD/uplnc_varargs_wide.e"
    if "$LPP" "$TMPD/uplnc_varargs_wide.e" 2>/dev/null \
            | "$LANGC" -march=i386 > "$TMPD/uplnc_varargs_wide.s" 2>"$TMPD/uplnc_varargs_wide.err"; then
        bad "64-bit i386 variadic arg exits nonzero"
    elif grep -q '64-bit variadic arguments' "$TMPD/uplnc_varargs_wide.err"; then
        ok "64-bit i386 variadic arg rejected"
    else
        bad "64-bit i386 variadic arg diagnostic"
    fi
else
    bad "langc not built"
fi

echo "[5] langc self-compiles its own units (stage-1) with 0 errors"
if [ -x "$LANGC" ] && [ -x "$LPP" ]; then
    # run from the src dir so lpp1's #include "tlangc.he" resolves; timeout
    # guards against a hang on (e.g. accidentally headerless) input.
    for u in langc codegen autodyn grph lpp1; do
        pp="$TMPD/uplnc_self_$u.pp"
        if ! (cd "$SRCDIR" && "$TDIR/build/lpp1" "$u.e" > "$pp" 2>"$TMPD/uplnc_self_$u.lpp.err"); then
            bad "self-compile $u.e (lpp1)"
            continue
        fi
        asm=$(timeout 60 "$TDIR/build/langc" < "$pp" 2>/dev/null)
        echo "$asm" | grep -qE '(^|[^0-9])0 error\(s\)' && ok "self-compile $u.e (0 errors)" || bad "self-compile $u.e"
    done
else
    bad "langc not built"
fi

echo "[5b] local promotion uses the target register budget and remains ABI-safe"
if [ -x "$LANGC" ] && [ -x "$LPP" ]; then
    for arch in x64 arm64 riscv mips; do
        case "$arch" in
            x64)   march=x86_64 ;;
            riscv) march=riscv64 ;;
            mips)  march=mips64 ;;
            *)     march="$arch" ;;
        esac
        for name in promote profit cold; do
            src="tests/progs/nonleaf_$name.e"
            "$LPP" "$src" 2>/dev/null \
                | "$LANGC" "-march=$march" > "$TMPD/uplnc_nonleaf_${arch}_$name.s" 2>/dev/null
        done
        "$LPP" tests/progs/leaf_promote4.e 2>/dev/null \
            | "$LANGC" "-march=$march" > "$TMPD/uplnc_leaf4_$arch.s" 2>/dev/null
    done

    if grep -Fq 'movq %rax, %r10' "$TMPD/uplnc_leaf4_x64.s" \
            && grep -Fq 'movq %rax, %r11' "$TMPD/uplnc_leaf4_x64.s" \
            && grep -Fq 'movq %rax, %r8' "$TMPD/uplnc_leaf4_x64.s" \
            && grep -Fq 'movq %rax, %r9' "$TMPD/uplnc_leaf4_x64.s"; then
        ok "x86_64 leaf promotion uses four caller-saved registers"
    else
        bad "x86_64 four-register leaf promotion"
    fi

    if grep -Fq 'mov x11, x0' "$TMPD/uplnc_leaf4_arm64.s" \
            && grep -Fq 'mov x12, x0' "$TMPD/uplnc_leaf4_arm64.s" \
            && grep -Fq 'mov x13, x0' "$TMPD/uplnc_leaf4_arm64.s" \
            && grep -Fq 'mov x14, x0' "$TMPD/uplnc_leaf4_arm64.s"; then
        ok "arm64 leaf promotion uses four caller-saved registers"
    else
        bad "arm64 four-register leaf promotion"
    fi

    if grep -Fq 'mv t4, a0' "$TMPD/uplnc_leaf4_riscv.s" \
            && grep -Fq 'mv t5, a0' "$TMPD/uplnc_leaf4_riscv.s" \
            && grep -Fq 'mv t6, a0' "$TMPD/uplnc_leaf4_riscv.s" \
            && grep -Fq 'mv a7, a0' "$TMPD/uplnc_leaf4_riscv.s"; then
        ok "riscv64 leaf promotion uses four caller-saved registers"
    else
        bad "riscv64 four-register leaf promotion"
    fi

    if grep -Fq 'move $8, $2' "$TMPD/uplnc_leaf4_mips.s" \
            && grep -Fq 'move $9, $2' "$TMPD/uplnc_leaf4_mips.s" \
            && grep -Fq 'move $10, $2' "$TMPD/uplnc_leaf4_mips.s" \
            && grep -Fq 'move $11, $2' "$TMPD/uplnc_leaf4_mips.s"; then
        ok "mips64 leaf promotion uses four caller-saved registers"
    else
        bad "mips64 four-register leaf promotion"
    fi

    if grep -Fq 'movq %r14, -16(%rbp)' "$TMPD/uplnc_nonleaf_x64_promote.s" \
            && grep -Fq 'movq -16(%rbp), %r14' "$TMPD/uplnc_nonleaf_x64_promote.s" \
            && grep -Fq 'movq %r14, -16(%rbp)' "$TMPD/uplnc_nonleaf_x64_profit.s" \
            && [ "$(grep -Fc 'movq %rax, %r14' "$TMPD/uplnc_nonleaf_x64_profit.s")" -ge 3 ] \
            && ! grep -Fq 'movq %r15, -8(%rbp)' "$TMPD/uplnc_nonleaf_x64_profit.s" \
            && ! grep -Fq 'movq %r14, -16(%rbp)' "$TMPD/uplnc_nonleaf_x64_cold.s"; then
        ok "x86_64 non-leaf promotion preserves only profitable registers"
    else
        bad "x86_64 non-leaf promotion profitability"
    fi

    if grep -Fq 'str x19, [x29, #-16]' "$TMPD/uplnc_nonleaf_arm64_promote.s" \
            && grep -Fq 'ldr x19, [x29, #-16]' "$TMPD/uplnc_nonleaf_arm64_promote.s" \
            && grep -Fq 'str x19, [x29, #-16]' "$TMPD/uplnc_nonleaf_arm64_profit.s" \
            && [ "$(grep -Fc 'mov x19, x0' "$TMPD/uplnc_nonleaf_arm64_profit.s")" -ge 3 ] \
            && ! grep -Fq 'str x20, [x29, #-8]' "$TMPD/uplnc_nonleaf_arm64_profit.s" \
            && ! grep -Fq 'str x19, [x29, #-16]' "$TMPD/uplnc_nonleaf_arm64_cold.s"; then
        ok "arm64 non-leaf promotion preserves only profitable registers"
    else
        bad "arm64 non-leaf promotion profitability"
    fi

    if grep -Fq 'sd s1, -16(s0)' "$TMPD/uplnc_nonleaf_riscv_promote.s" \
            && grep -Fq 'ld s1, -16(s0)' "$TMPD/uplnc_nonleaf_riscv_promote.s" \
            && grep -Fq 'sd s1, -16(s0)' "$TMPD/uplnc_nonleaf_riscv_profit.s" \
            && [ "$(grep -Fc 'mv s1, a0' "$TMPD/uplnc_nonleaf_riscv_profit.s")" -ge 3 ] \
            && ! grep -Fq 'sd s2, -8(s0)' "$TMPD/uplnc_nonleaf_riscv_profit.s" \
            && ! grep -Fq 'sd s1, -16(s0)' "$TMPD/uplnc_nonleaf_riscv_cold.s"; then
        ok "riscv64 non-leaf promotion preserves only profitable registers"
    else
        bad "riscv64 non-leaf promotion profitability"
    fi

    if grep -Fq 'sd $16, -16($fp)' "$TMPD/uplnc_nonleaf_mips_promote.s" \
            && grep -Fq 'ld $16, -16($fp)' "$TMPD/uplnc_nonleaf_mips_promote.s" \
            && grep -Fq 'sd $16, -16($fp)' "$TMPD/uplnc_nonleaf_mips_profit.s" \
            && [ "$(grep -Fc 'move $16, $2' "$TMPD/uplnc_nonleaf_mips_profit.s")" -ge 3 ] \
            && ! grep -Fq 'sd $17, -8($fp)' "$TMPD/uplnc_nonleaf_mips_profit.s" \
            && ! grep -Fq 'sd $16, -16($fp)' "$TMPD/uplnc_nonleaf_mips_cold.s"; then
        ok "mips64 non-leaf promotion preserves only profitable registers"
    else
        bad "mips64 non-leaf promotion profitability"
    fi
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
        asm="$TMPD/uplnc_x64_$name.s"; bin="$TMPD/uplnc_x64_$name"
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
    sortbin="$TMPD/uplnc_x64_sort"
    if buildsort x86_64 "$sortbin" 2>"$TMPD/uplnc_x64_sort.err"; then
        got=$(printf 'pear\napple\nBanana\nbanana\napple\n' | "$sortbin" -f)
        want=$(printf 'apple\napple\nBanana\nbanana\npear\n')
        [ "$got" = "$want" ] && ok "x86_64 multi-unit stable sort" \
                                 || bad "x86_64 multi-unit stable sort"
    else
        bad "x86_64 multi-unit sort build"
    fi
    calcbin="$TMPD/uplnc_x64_calc"
    if buildcalc x86_64 "$calcbin" 2>"$TMPD/uplnc_x64_calc.err"; then
        checkcalc x86_64 "$calcbin" ""
    else
        bad "x86_64 calc build"
    fi
    gatebenches x86_64
fi

echo "[6b] x86_64 ABI: a UPLNC function preserves callee-saved regs for a C caller"
if [ "$(uname -m)" = "x86_64" ] && command -v gcc >/dev/null && [ -x "$LANGC" ]; then
    # upf's expression is deep enough that regspill uses the callee-saved spill
    # registers (rbx/r12/r13). It returns 0, so a C caller that keeps a value in
    # a callee-saved register across three calls to upf must get it back unchanged.
    cat > "$TMPD/uplnc_csr.e" <<'EOFU'
func upf()
{
  var int:a;var int:b;var int:c;var int:d;var int:e;var int:f;
  a=1;b=2;c=3;d=4;e=5;f=6;
  return (a+b)*(c+d)+(b+c)*(d+e)+(c+d)*(e+f)+(a+f)*(b+e)-((a+b)*(c+d)+(b+c)*(d+e)+(c+d)*(e+f)+(a+f)*(b+e));
}
EOFU
    "$LPP" "$TMPD/uplnc_csr.e" 2>/dev/null | "$LANGC" -march=x86_64 > "$TMPD/uplnc_csr.s" 2>/dev/null
    cat > "$TMPD/uplnc_csr_h.c" <<'EOFC'
extern long upf(void);
long __attribute__((noinline)) outer(long x){
  long acc=x; acc+=upf(); acc+=upf(); acc+=upf(); return acc;
}
int main(void){ return outer(1000)==1000 ? 0 : 1; }
EOFC
    if gcc -no-pie -O2 -w "$TMPD/uplnc_csr_h.c" "$TMPD/uplnc_csr.s" -o "$TMPD/uplnc_csr" 2>/dev/null; then
        if "$TMPD/uplnc_csr"; then ok "callee-saved regs preserved across a UPLNC call"
        else bad "callee-saved regs clobbered across a UPLNC call"; fi
    else
        bad "C-interop test failed to build"
    fi
else
    echo "  skip - needs native x86_64 gcc"
fi

echo "[7] i386 x87 backend: programs compile (-march=i386), assemble + run (-m32)"
# Find a working 32-bit toolchain. The default 'gcc' may lack 32-bit libgcc on
# some hosts (e.g. gcc-8 here), so fall back to a versioned gcc that has it.
M32=""
for cc in "gcc -m32" "gcc-12 -m32" "gcc-11 -m32" "gcc-10 -m32" "gcc-9 -m32"; do
    if echo 'int main(void){return 0;}' | $cc -x c - -o "$TMPD/uplnc_m32probe" 2>/dev/null; then
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
        asm="$TMPD/uplnc_i386_$name.s"; bin="$TMPD/uplnc_i386_$name"
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
    drvbin="$TMPD/uplnc_i386_driver"
    if perl "$DRIVER" -march=i386 -o "$drvbin" tests/progs/ret_const.e \
            2>"$TMPD/uplnc_i386_driver.err"; then
        "$drvbin"; got=$?
        [ "$got" = 42 ] && ok "driver selects a working i386 toolchain" \
                            || bad "i386 driver binary exits $got, want 42"
    else
        bad "driver selects a working i386 toolchain"
    fi
    grepbin="$TMPD/uplnc_i386_grep"
    if buildgrep i386 "$grepbin" 2>"$TMPD/uplnc_i386_grep.err"; then
        got=$(printf 'abz\nno\naxyz\n' | "$grepbin" '^a.*z$')
        want=$(printf 'abz\naxyz\n')
        [ "$got" = "$want" ] && ok "i386 multi-file grep matcher" \
                                 || bad "i386 multi-file grep matcher"
    else
        bad "i386 multi-file grep build"
    fi
    sortbin="$TMPD/uplnc_i386_sort"
    if buildsort i386 "$sortbin" 2>"$TMPD/uplnc_i386_sort.err"; then
        got=$(printf 'pear\napple\nBanana\nbanana\napple\n' | "$sortbin" -f)
        want=$(printf 'apple\napple\nBanana\nbanana\npear\n')
        [ "$got" = "$want" ] && ok "i386 multi-unit stable sort" \
                                 || bad "i386 multi-unit stable sort"
    else
        bad "i386 multi-unit sort build"
    fi
    calcbin="$TMPD/uplnc_i386_calc"
    if buildcalc i386 "$calcbin" 2>"$TMPD/uplnc_i386_calc.err"; then
        checkcalc i386 "$calcbin" ""
    else
        bad "i386 calc build"
    fi
    gatebenches i386
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
        asm="$TMPD/uplnc_arm64_$name.s"; bin="$TMPD/uplnc_arm64_$name"
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
    drvbin="$TMPD/uplnc_arm64_driver"
    if perl "$DRIVER" -march=arm64 -o "$drvbin" tests/progs/ret_const.e \
            2>"$TMPD/uplnc_arm64_driver.err"; then
        "$drvbin"; got=$?
        [ "$got" = 42 ] && ok "driver selects the arm64 toolchain and flags" \
                            || bad "arm64 driver binary exits $got, want 42"
    else
        bad "driver selects the arm64 toolchain and flags"
    fi
    grepbin="$TMPD/uplnc_arm64_grep"
    if buildgrep arm64 "$grepbin" 2>"$TMPD/uplnc_arm64_grep.err"; then
        got=$(printf 'abz\nno\naxyz\n' | "$grepbin" '^a.*z$')
        want=$(printf 'abz\naxyz\n')
        [ "$got" = "$want" ] && ok "arm64 multi-file grep matcher" \
                                 || bad "arm64 multi-file grep matcher"
    else
        bad "arm64 multi-file grep build"
    fi
    sortbin="$TMPD/uplnc_arm64_sort"
    if buildsort arm64 "$sortbin" 2>"$TMPD/uplnc_arm64_sort.err"; then
        got=$(printf 'pear\napple\nBanana\nbanana\napple\n' | "$sortbin" -f)
        want=$(printf 'apple\napple\nBanana\nbanana\npear\n')
        [ "$got" = "$want" ] && ok "arm64 multi-unit stable sort" \
                                 || bad "arm64 multi-unit stable sort"
    else
        bad "arm64 multi-unit sort build"
    fi
    calcbin="$TMPD/uplnc_arm64_calc"
    if buildcalc arm64 "$calcbin" 2>"$TMPD/uplnc_arm64_calc.err"; then
        checkcalc arm64 "$calcbin" ""
    else
        bad "arm64 calc build"
    fi
    gatebenches arm64
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
        asm="$TMPD/uplnc_riscv_$name.s"; bin="$TMPD/uplnc_riscv_$name"
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
    drvbin="$TMPD/uplnc_riscv_driver"
    if perl "$DRIVER" -march=riscv64 -o "$drvbin" tests/progs/ret_const.e \
            2>"$TMPD/uplnc_riscv_driver.err"; then
        "$drvbin"; got=$?
        [ "$got" = 42 ] && ok "driver selects the riscv64 toolchain and flags" \
                            || bad "riscv64 driver binary exits $got, want 42"
    else
        bad "driver selects the riscv64 toolchain and flags"
    fi
    grepbin="$TMPD/uplnc_riscv_grep"
    if buildgrep riscv64 "$grepbin" 2>"$TMPD/uplnc_riscv_grep.err"; then
        got=$(printf 'abz\nno\naxyz\n' | "$grepbin" '^a.*z$')
        want=$(printf 'abz\naxyz\n')
        [ "$got" = "$want" ] && ok "riscv64 multi-file grep matcher" \
                                 || bad "riscv64 multi-file grep matcher"
    else
        bad "riscv64 multi-file grep build"
    fi
    sortbin="$TMPD/uplnc_riscv_sort"
    if buildsort riscv64 "$sortbin" 2>"$TMPD/uplnc_riscv_sort.err"; then
        got=$(printf 'pear\napple\nBanana\nbanana\napple\n' | "$sortbin" -f)
        want=$(printf 'apple\napple\nBanana\nbanana\npear\n')
        [ "$got" = "$want" ] && ok "riscv64 multi-unit stable sort" \
                                 || bad "riscv64 multi-unit stable sort"
    else
        bad "riscv64 multi-unit sort build"
    fi
    calcbin="$TMPD/uplnc_riscv_calc"
    if buildcalc riscv64 "$calcbin" 2>"$TMPD/uplnc_riscv_calc.err"; then
        checkcalc riscv64 "$calcbin" ""
    else
        bad "riscv64 calc build"
    fi
    gatebenches riscv64
fi

echo "[10] mips64 backend: programs compile (-march=mips64), assemble + run"
# MIPS64 N64, big-endian -- the one big-endian target. Cross-toolchain + qemu
# binfmt on x86, or native gcc on mips64. Integer + floating point both run; the
# skip branch below is a safety net for any feature that errors cleanly.
MIPS=""
# -mno-abicalls -fno-pic -G 0: non-PIC, and -G 0 disables small-data so `dla`
# forms a full 64-bit *absolute* address rather than a $gp-relative one (we
# never set up $gp; calls go through $t9). See fixpoint.sh for the rationale.
if command -v mips64-linux-gnuabi64-gcc >/dev/null; then MIPS="mips64-linux-gnuabi64-gcc -static -mno-abicalls -fno-pic -G 0"
elif [ "$(uname -m)" = "mips64" ]; then MIPS="gcc -no-pie -mno-abicalls -fno-pic -G 0"; fi
# QEMU_MIPS=/path/to/qemu-mips64-static runs the test binaries through that
# emulator instead of binfmt -- point it at a strict (CI-matching) qemu, since
# the system binfmt one may silently tolerate unaligned ld/sd. Empty -> binfmt.
MIPSRUN="${QEMU_MIPS:-}"
if [ ! -x "$LANGC" ]; then
    bad "langc not built"
elif [ -z "$MIPS" ]; then
    echo "  skip - no mips64 toolchain (need gcc-mips64-linux-gnuabi64 + qemu-user-static)"
else
    while read -r name want; do
        [ -z "$name" ] && continue
        asm="$TMPD/uplnc_mips_$name.s"; bin="$TMPD/uplnc_mips_$name"
        "$TDIR/build/lpp1" "tests/progs/$name.e" 2>/dev/null \
            | "$TDIR/build/langc" -march=mips64 > "$asm" 2>/dev/null
        if grep -q 'not supported on mips' "$asm"; then
            echo "  skip - mips64 $name.e (floating point not implemented on mips64 yet)"
        elif grep -qE '[1-9][0-9]* error' "$asm"; then
            bad "mips64 $name.e (compile)"
        elif ! $MIPS "$asm" -o "$bin" 2>/dev/null; then
            bad "mips64 $name.e (assemble/link)"
        else
            $MIPSRUN "$bin"; got=$?
            [ "$got" = "$want" ] && ok "mips64 $name.e -> exit $got" \
                                 || bad "mips64 $name.e (got $got, want $want)"
        fi
    done < tests/progs/expected.txt
    drvbin="$TMPD/uplnc_mips_driver"
    if perl "$DRIVER" -march=mips64 -o "$drvbin" tests/progs/ret_const.e \
            2>"$TMPD/uplnc_mips_driver.err"; then
        $MIPSRUN "$drvbin"; got=$?
        [ "$got" = 42 ] && ok "driver selects the mips64 toolchain and flags" \
                            || bad "mips64 driver binary exits $got, want 42"
    else
        bad "driver selects the mips64 toolchain and flags"
    fi
    grepbin="$TMPD/uplnc_mips_grep"
    if buildgrep mips64 "$grepbin" 2>"$TMPD/uplnc_mips_grep.err"; then
        got=$(printf 'abz\nno\naxyz\n' | $MIPSRUN "$grepbin" '^a.*z$')
        want=$(printf 'abz\naxyz\n')
        [ "$got" = "$want" ] && ok "mips64 multi-file grep matcher" \
                                 || bad "mips64 multi-file grep matcher"
    else
        bad "mips64 multi-file grep build"
    fi
    sortbin="$TMPD/uplnc_mips_sort"
    if buildsort mips64 "$sortbin" 2>"$TMPD/uplnc_mips_sort.err"; then
        got=$(printf 'pear\napple\nBanana\nbanana\napple\n' | $MIPSRUN "$sortbin" -f)
        want=$(printf 'apple\napple\nBanana\nbanana\npear\n')
        [ "$got" = "$want" ] && ok "mips64 multi-unit stable sort" \
                                 || bad "mips64 multi-unit stable sort"
    else
        bad "mips64 multi-unit sort build"
    fi
    calcbin="$TMPD/uplnc_mips_calc"
    if buildcalc mips64 "$calcbin" 2>"$TMPD/uplnc_mips_calc.err"; then
        checkcalc mips64 "$calcbin" "$MIPSRUN"
    else
        bad "mips64 calc build"
    fi
    gatebenches mips64
fi

echo "[11] example utilities: examples/*.e build and run (M7 'proof it's real')"
# Real self-contained utilities written in UPLNC. Build + run them for the host's
# native arch (x86_64 or arm64 CI runner) and check behaviour against the system.
HOSTM=$(uname -m)
if [ "$HOSTM" = "x86_64" ] && command -v gcc >/dev/null; then UM="-march=x86_64"
elif [ "$HOSTM" = "aarch64" ] && command -v gcc >/dev/null; then UM="-march=arm64"
else UM=""; fi
# build an example utility for the host arch; echoes the binary path or "" on fail
buildutil() {  # $1 = name (without .e); $2 = "fmt" to link lib/fmt.e
    local bin="$TMPD/uplnc_$1"
    local args=("$DRIVER" "$UM" -o "$bin" "../examples/$1.e")
    if [ "${2:-}" = fmt ]; then
        args+=("../lib/fmt.e")
    fi
    perl "${args[@]}" \
        2>"$TMPD/uplnc_$1.driver.err" || { bad "$1.e (driver build)"; return 1; }
    echo "$bin"
}
if [ ! -x "$LANGC" ]; then
    bad "langc not built"
elif [ -z "$UM" ]; then
    echo "  skip - no native toolchain to build the examples on $HOSTM"
else
    if WC=$(buildutil wc); then
        got=$(printf 'hello world\nfoo bar baz\n' | "$WC")
        [ "$got" = "2 5 24" ] && ok "wc.e -> '$got'" || bad "wc.e (got '$got', want '2 5 24')"
        got=$(printf '' | "$WC")
        [ "$got" = "0 0 0" ] && ok "wc.e empty input -> '$got'" || bad "wc.e empty (got '$got')"
        want=$(wc < "$0" | awk '{print $1, $2, $3}'); got=$("$WC" < "$0")
        [ "$got" = "$want" ] && ok "wc.e matches system wc on a real file" \
                             || bad "wc.e vs system wc (got '$got', want '$want')"
    else bad "wc.e build"; fi
    if CAT=$(buildutil cat); then
        printf 'line1\nline2\n' > "$TMPD/uplnc_catf1"; printf 'AAA\n' > "$TMPD/uplnc_catf2"
        cmp -s <("$CAT" "$TMPD/uplnc_catf1" "$TMPD/uplnc_catf2") <(cat "$TMPD/uplnc_catf1" "$TMPD/uplnc_catf2") \
            && ok "cat.e concatenates files" || bad "cat.e (files)"
        cmp -s <(printf 'piped\n' | "$CAT") <(printf 'piped\n') \
            && ok "cat.e reads stdin with no args" || bad "cat.e (stdin)"
        "$CAT" "$TMPD/uplnc_nope" 2>/dev/null; [ "$?" = 1 ] \
            && ok "cat.e exits 1 on a missing file" || bad "cat.e (error exit)"
    else bad "cat.e build"; fi
    # lib/fmt.e (stdlib v0): fmtdemo prints the library's fixed output contract
    if FD=$(buildutil fmtdemo fmt); then
        printf 'int: 42 -7 0\npad: [    42] [000042] [   -42]\nunsigned: 4294967295\nhex: ff [0000beef] [    beef]\nstr: abc, char: xyz, pct: 100%%\nmix: val=1000 (03e8)\nflt: 1.500000 3.14 3\nfpad: [    -2.500] [000002.500] [0.062]\nfedge: [-0.000000] [1.250000000000000000]\nfclamp: [1] [1.250000000000000000]\nsci: 1.500000e+00 1.00e+01 [00002.50e-04] -4.212500e+01\ngen: 2.5 100 0.0001 1e-05 123 1.23457e+06\nexact: 2.602900636204250e+180 8.41151214888311e+106 4.94065645841246544e-324 1.79769313486231571e+308\nhalf: 1.3e+00 1.3\n' > "$TMPD/uplnc_fmtdemo.want"
        if timeout 5 "$FD" > "$TMPD/uplnc_fmtdemo.out" 2>&1 \
                && cmp -s "$TMPD/uplnc_fmtdemo.out" "$TMPD/uplnc_fmtdemo.want"; then
            ok "fmtdemo.e matches the lib/fmt.e output contract"
        else
            bad "fmtdemo.e output or timeout"
        fi
    else bad "fmtdemo.e + lib/fmt.e build"; fi
    if HD=$(buildutil hexdump fmt); then
        printf 'hello world\n' | "$HD" > "$TMPD/uplnc_hex1.out"
        printf '00000000  68 65 6c 6c 6f 20 77 6f 72 6c 64 0a              |hello world.|\n' > "$TMPD/uplnc_hex1.want"
        cmp -s "$TMPD/uplnc_hex1.out" "$TMPD/uplnc_hex1.want" \
            && ok "hexdump.e partial line" || bad "hexdump.e partial line"
        printf 'ABCDEFGHIJKLMNO\377' | "$HD" > "$TMPD/uplnc_hex2.out"
        printf '00000000  41 42 43 44 45 46 47 48 49 4a 4b 4c 4d 4e 4f ff  |ABCDEFGHIJKLMNO.|\n' > "$TMPD/uplnc_hex2.want"
        cmp -s "$TMPD/uplnc_hex2.out" "$TMPD/uplnc_hex2.want" \
            && ok "hexdump.e full line + high byte" || bad "hexdump.e full line"
    else bad "hexdump.e + lib/fmt.e build"; fi

    GREP="$TMPD/uplnc_grep"
    if buildgrep "${UM#-march=}" "$GREP" 2>"$TMPD/uplnc_grep.driver.err"; then
        printf 'Alpha\naxb\nacccb\nomega\n' > "$TMPD/uplnc_grep_f1"
        printf 'alpha\nzzz\nab\n' > "$TMPD/uplnc_grep_f2"
        if cmp -s <("$GREP" '^a.*b$' "$TMPD/uplnc_grep_f1" "$TMPD/uplnc_grep_f2") \
                  <(grep '^a.*b$' "$TMPD/uplnc_grep_f1" "$TMPD/uplnc_grep_f2"); then
            ok "grep.e regex subset matches system grep across files"
        else
            bad "grep.e regex subset vs system grep"
        fi

        got=$(printf 'Alpha\nHELLO!\nalpha\n' | "$GREP" -ni '^alpha$')
        want=$(printf '1:Alpha\n3:alpha\n')
        [ "$got" = "$want" ] && ok "grep.e combined -n/-i options" \
                                 || bad "grep.e -n/-i (got '$got')"
        got=$(printf 'keep\ndrop\n' | "$GREP" -v '^drop$')
        [ "$got" = keep ] && ok "grep.e -v inversion" || bad "grep.e -v inversion"
        got=$(printf 'a.c\nabc\n' | "$GREP" 'a\.c')
        [ "$got" = 'a.c' ] && ok "grep.e backslash escaping" || bad "grep.e escaping"
        got=$(printf '%s\n' '-x' 'x' | "$GREP" -- '-x')
        [ "$got" = '-x' ] && ok "grep.e -- permits a dash pattern" \
                               || bad "grep.e -- handling"

        "$GREP" absent "$TMPD/uplnc_grep_f1" >/dev/null 2>&1
        [ "$?" = 1 ] && ok "grep.e exits 1 when no line is selected" \
                         || bad "grep.e no-match exit status"
        "$GREP" x "$TMPD/uplnc_grep_missing" >/dev/null 2>"$TMPD/uplnc_grep_missing.err"
        [ "$?" = 2 ] && grep -q 'cannot open' "$TMPD/uplnc_grep_missing.err" \
            && ok "grep.e exits 2 on an input error" || bad "grep.e input-error status"
        "$GREP" "abc\\" </dev/null >/dev/null 2>"$TMPD/uplnc_grep_pattern.err"
        [ "$?" = 2 ] && grep -q 'invalid or too long pattern' "$TMPD/uplnc_grep_pattern.err" \
            && ok "grep.e rejects an invalid pattern" || bad "grep.e invalid pattern"

        longline=$(printf '%01024d' 0 | tr 0 x)
        printf '%s\nok\n' "$longline" > "$TMPD/uplnc_grep_long"
        "$GREP" ok "$TMPD/uplnc_grep_long" >"$TMPD/uplnc_grep_long.out" \
            2>"$TMPD/uplnc_grep_long.err"
        rc=$?
        [ "$rc" = 2 ] && grep -q 'line too long' "$TMPD/uplnc_grep_long.err" \
            && grep -qx ok "$TMPD/uplnc_grep_long.out" \
            && ok "grep.e diagnoses and discards an overlong line" \
            || bad "grep.e overlong-line handling"

        hardpat=""
        for _ in $(seq 1 40); do hardpat="${hardpat}a*"; done
        hardpat="${hardpat}b"
        hardline="$(printf '%0500d' 0 | tr 0 a)c"
        printf '%s\n' "$hardline" | "$GREP" "$hardpat" >/dev/null \
            2>"$TMPD/uplnc_grep_steps.err"
        rc=$?
        [ "$rc" = 2 ] && grep -q 'match limit exceeded' "$TMPD/uplnc_grep_steps.err" \
            && ok "grep.e bounds pathological backtracking" \
            || bad "grep.e backtracking limit"
    else
        bad "grep.e multi-file build"
    fi

    SORT="$TMPD/uplnc_sort"
    if buildsort "${UM#-march=}" "$SORT" 2>"$TMPD/uplnc_sort.driver.err"; then
        printf 'pear\napple\n\nkiwi\n' > "$TMPD/uplnc_sort_f1"
        printf 'banana\napple\norange\n' > "$TMPD/uplnc_sort_f2"
        if cmp -s <("$SORT" "$TMPD/uplnc_sort_f1" "$TMPD/uplnc_sort_f2") \
                  <(LC_ALL=C sort "$TMPD/uplnc_sort_f1" "$TMPD/uplnc_sort_f2"); then
            ok "sort.e matches system sort across files"
        else
            bad "sort.e default ordering vs system sort"
        fi

        printf 'b\nA\na\nB\na\n' > "$TMPD/uplnc_sort_case"
        if cmp -s <("$SORT" -fr "$TMPD/uplnc_sort_case") \
                  <(LC_ALL=C sort -f -r -s "$TMPD/uplnc_sort_case"); then
            ok "sort.e combined -f/-r is stable"
        else
            bad "sort.e combined -f/-r"
        fi
        if cmp -s <("$SORT" -fu "$TMPD/uplnc_sort_case") \
                  <(LC_ALL=C sort -f -s -u "$TMPD/uplnc_sort_case"); then
            ok "sort.e -u uses the selected comparator"
        else
            bad "sort.e folded unique ordering"
        fi

        : > "$TMPD/uplnc_sort_grow"
        for n in $(seq 300 -1 1); do
            printf '%03d-%0200d\n' "$n" 0 >> "$TMPD/uplnc_sort_grow"
        done
        if cmp -s <("$SORT" "$TMPD/uplnc_sort_grow") \
                  <(LC_ALL=C sort "$TMPD/uplnc_sort_grow"); then
            ok "sort.e grows its line and pointer buffers"
        else
            bad "sort.e dynamic storage growth"
        fi

        printf 'z\n\ny' > "$TMPD/uplnc_sort_nonl"
        if cmp -s <("$SORT" "$TMPD/uplnc_sort_nonl") \
                  <(LC_ALL=C sort "$TMPD/uplnc_sort_nonl"); then
            ok "sort.e handles blank and unterminated final lines"
        else
            bad "sort.e final-line handling"
        fi
        if cmp -s <(printf '\377\n\200\nA\n' | "$SORT") \
                  <(printf '\377\n\200\nA\n' | LC_ALL=C sort); then
            ok "sort.e compares non-ASCII bytes as unsigned"
        else
            bad "sort.e unsigned-byte ordering"
        fi

        printf 'dash file\nalpha\n' > "$TMPD/-sort-data"
        if (cd "$TMPD" && "$SORT" -- -sort-data > uplnc_sort_dash.out) \
                && (cd "$TMPD" && LC_ALL=C sort -- -sort-data > uplnc_sort_dash.want) \
                && cmp -s "$TMPD/uplnc_sort_dash.out" "$TMPD/uplnc_sort_dash.want"; then
            ok "sort.e -- permits a dash-prefixed file"
        else
            bad "sort.e -- handling"
        fi

        "$SORT" "$TMPD/uplnc_sort_missing" "$TMPD/uplnc_sort_f2" \
            > "$TMPD/uplnc_sort_missing.out" 2> "$TMPD/uplnc_sort_missing.err"
        rc=$?
        [ "$rc" = 2 ] && grep -q 'cannot open' "$TMPD/uplnc_sort_missing.err" \
            && cmp -s "$TMPD/uplnc_sort_missing.out" <(LC_ALL=C sort "$TMPD/uplnc_sort_f2") \
            && ok "sort.e reports an input error after sorting valid files" \
            || bad "sort.e input-error handling"

        printf 'a\0b\n' | "$SORT" > "$TMPD/uplnc_sort_nul.out" \
            2> "$TMPD/uplnc_sort_nul.err"
        rc=$?
        [ "$rc" = 2 ] && grep -q 'embedded NUL' "$TMPD/uplnc_sort_nul.err" \
            && [ ! -s "$TMPD/uplnc_sort_nul.out" ] \
            && ok "sort.e rejects embedded NUL without truncating" \
            || bad "sort.e embedded-NUL handling"
    else
        bad "sort.e multi-unit build"
    fi

    # calc.e: expression interpreter (heap AST of struct nodes + methods, %f)
    if CALC=$(buildutil calc fmt); then
        printf '1+2*3\n(1+2)*3\n-4/8\nx = 2.5\nx*x\n3*(x-0.5)-1\n10/0\n-10/0\n0/0\n10000000000.0*3\n0.1+0.2\ny\n2+\n' \
            > "$TMPD/uplnc_calc.in"
        printf '7\n9\n-0.500000\n2.500000\n6.250000\n5\ninf\n-inf\nnan\n3.000000e+10\n0.300000\n' \
            > "$TMPD/uplnc_calc.want"
        printf 'calc:12: unset variable '"'"'y'"'"'\ncalc:13: parse error at column 3\n' \
            > "$TMPD/uplnc_calc.werr"
        timeout 5 "$CALC" < "$TMPD/uplnc_calc.in" \
            > "$TMPD/uplnc_calc.out" 2> "$TMPD/uplnc_calc.err"
        rc=$?
        [ "$rc" = 1 ] && cmp -s "$TMPD/uplnc_calc.out" "$TMPD/uplnc_calc.want" \
            && cmp -s "$TMPD/uplnc_calc.err" "$TMPD/uplnc_calc.werr" \
            && ok "calc.e evaluates the pinned session (values, inf/nan, errors)" \
            || bad "calc.e session transcript"
        got=$(printf '1+2*3\n-(2.5+1.5)/2\nz=1.5\nz*z*z\n' | timeout 5 "$CALC" -n)
        rc=$?
        want=$(printf '7  (5 nodes)\n-2  (6 nodes)\n1.500000  (1 nodes)\n3.375000  (5 nodes)\n')
        [ "$rc" = 0 ] && [ "$got" = "$want" ] \
            && ok "calc.e -n reports method-computed node counts, exit 0" \
            || bad "calc.e -n node counts"
        timeout 5 "$CALC" -q </dev/null >/dev/null 2>"$TMPD/uplnc_calc_use.err"
        [ "$?" = 2 ] && grep -q 'usage:' "$TMPD/uplnc_calc_use.err" \
            && ok "calc.e rejects unknown options with usage and status 2" \
            || bad "calc.e usage handling"
        python3 -c "print('1+'*100+'1'); print('2*3')" | timeout 5 "$CALC" \
            > "$TMPD/uplnc_calc_long.out" 2>/dev/null
        [ "$?" = 0 ] && [ "$(tail -1 "$TMPD/uplnc_calc_long.out")" = 6 ] \
            && [ "$(head -1 "$TMPD/uplnc_calc_long.out")" = 101 ] \
            && ok "calc.e handles a 100-term expression and continues" \
            || bad "calc.e long expression"
        python3 -c "print('1+'*200+'1')" | timeout 5 "$CALC" \
            >/dev/null 2>"$TMPD/uplnc_calc_over.err"
        [ "$?" = 1 ] && grep -q 'line too long' "$TMPD/uplnc_calc_over.err" \
            && ok "calc.e diagnoses an overlong line and exits 1" \
            || bad "calc.e overlong line"
        python3 -c "print('a='+'131'+'0'*152); print('a*a'); print('(a*a)/(a*a)'); print('2147483647')" \
            | timeout 5 "$CALC" >"$TMPD/uplnc_calc_bounds.out" 2>/dev/null
        rc=$?
        printf '1.310000e+154\n1.716100e+308\n1\n2147483647\n' \
            >"$TMPD/uplnc_calc_bounds.want"
        [ "$rc" = 0 ] && cmp -s "$TMPD/uplnc_calc_bounds.out" "$TMPD/uplnc_calc_bounds.want" \
            && ok "calc.e distinguishes finite extremes and exact integer bounds" \
            || bad "calc.e numeric output bounds"
        printf '1\0/0\n2+2\n' | timeout 5 "$CALC" \
            >"$TMPD/uplnc_calc_nul.out" 2>"$TMPD/uplnc_calc_nul.err"
        rc=$?
        [ "$rc" = 1 ] && [ "$(cat "$TMPD/uplnc_calc_nul.out")" = 4 ] \
            && grep -q 'calc:1: embedded NUL is not supported' "$TMPD/uplnc_calc_nul.err" \
            && ok "calc.e rejects an embedded NUL and continues with the next line" \
            || bad "calc.e embedded-NUL handling"
        timeout 5 "$CALC" < "$TMPD" \
            >"$TMPD/uplnc_calc_read.out" 2>"$TMPD/uplnc_calc_read.err"
        rc=$?
        [ "$rc" = 1 ] && [ ! -s "$TMPD/uplnc_calc_read.out" ] \
            && grep -q 'calc: input read error' "$TMPD/uplnc_calc_read.err" \
            && ok "calc.e reports an input read failure" \
            || bad "calc.e input read failure"
    else
        bad "calc.e + lib/fmt.e build"
    fi

    # uplncfmt.e: the source formatter. Its correctness bar is unique -- a
    # formatted source must compile to the SAME instructions, since lpp1
    # discards exactly the whitespace it rearranges. langc echoes each source
    # line as a `#:` assembler comment (reflecting the reindentation), so the
    # semantic-preservation check compares the emitted code with those echo
    # comments stripped.
    if FMT=$(buildutil uplncfmt); then
        # basic reindentation + idempotence, on a deliberately messy input
        printf 'func f()\n{\nvar int:x;\n    if(x){\n  x=1;\n      }\nreturn x;\n}\n' \
            > "$TMPD/uplnc_fmt_in.e"
        printf 'func f()\n{\n  var int:x;\n  if(x){\n    x=1;\n  }\n  return x;\n}\n' \
            > "$TMPD/uplnc_fmt_want.e"
        timeout 5 "$FMT" "$TMPD/uplnc_fmt_in.e" > "$TMPD/uplnc_fmt_out.e" 2>/dev/null
        cmp -s "$TMPD/uplnc_fmt_out.e" "$TMPD/uplnc_fmt_want.e" \
            && ok "uplncfmt reindents to canonical two-space depth" \
            || bad "uplncfmt reindentation"
        timeout 5 "$FMT" "$TMPD/uplnc_fmt_out.e" > "$TMPD/uplnc_fmt_out2.e" 2>/dev/null
        cmp -s "$TMPD/uplnc_fmt_out.e" "$TMPD/uplnc_fmt_out2.e" \
            && ok "uplncfmt is idempotent" || bad "uplncfmt idempotence"
        # braces inside strings/char-literals/comments must not move indentation
        printf 'func g(t:*char)\n{\nif(t[0]=='"'"'{'"'"'){\nt="a{b}c";   /* } { */\nreturn 0;\n}\nreturn 1;\n}\n' \
            > "$TMPD/uplnc_fmt_tricky.e"
        timeout 5 "$FMT" "$TMPD/uplnc_fmt_tricky.e" > "$TMPD/uplnc_fmt_tricky.out" 2>/dev/null
        "$LPP" "$TMPD/uplnc_fmt_tricky.e" 2>/dev/null | "$LANGC" -march=x86_64 2>/dev/null \
            | grep -v '^#' > "$TMPD/uplnc_fmt_orig.s"
        "$LPP" "$TMPD/uplnc_fmt_tricky.out" 2>/dev/null | "$LANGC" -march=x86_64 2>/dev/null \
            | grep -v '^#' > "$TMPD/uplnc_fmt_fmtd.s"
        cmp -s "$TMPD/uplnc_fmt_orig.s" "$TMPD/uplnc_fmt_fmtd.s" \
            && ok "uplncfmt preserves semantics with braces in strings/comments" \
            || bad "uplncfmt string/comment brace handling"
        # replacement-text braces on directives do not belong to the current
        # source location and must not shift the following top-level code
        printf '#define OPEN {\nfunc h()\n{\nreturn 0;\n}\n' > "$TMPD/uplnc_fmt_directive.e"
        printf '#define OPEN {\nfunc h()\n{\n  return 0;\n}\n' > "$TMPD/uplnc_fmt_directive.want"
        timeout 5 "$FMT" "$TMPD/uplnc_fmt_directive.e" \
            > "$TMPD/uplnc_fmt_directive.out" 2>/dev/null
        cmp -s "$TMPD/uplnc_fmt_directive.out" "$TMPD/uplnc_fmt_directive.want" \
            && ok "uplncfmt ignores braces in directive replacement text" \
            || bad "uplncfmt directive brace handling"
        # the flagship: formatting real sources compiles to byte-identical
        # instructions. -w rewrites a copy beside the original so any relative
        # #include (grep_match.he) still resolves; the compiler's own units and
        # a macro-using multi-unit example are the sharpest cases.
        fmt_bad=0
        fmtdir="$TMPD/uplnc_fmt_src"
        mkdir -p "$fmtdir"
        cp ../examples/*.e ../examples/*.he ../lib/*.e ../lib/*.he ../src/*.e ../src/*.he "$fmtdir/" 2>/dev/null
        for u in wc.e cat.e grep_match.e grep_match.he sort_lines.e fmt.e langc.e codegen.e lpp1.e; do
            [ -f "$fmtdir/$u" ] && timeout 15 "$FMT" -w "$fmtdir/$u" 2>/dev/null
        done
        for u in wc.e cat.e grep_match.e sort_lines.e fmt.e langc.e codegen.e lpp1.e; do
            case "$u" in wc.e|cat.e|grep_match.e) o="../examples/$u";;
                         sort_lines.e) o="../examples/$u";;
                         fmt.e) o="../lib/$u";; *) o="../src/$u";; esac
            "$LPP" "$o" 2>/dev/null | "$LANGC" -march=x86_64 2>/dev/null \
                | grep -v '^#' > "$TMPD/uplnc_fmt_ua.s"
            "$LPP" "$fmtdir/$u" 2>/dev/null | "$LANGC" -march=x86_64 2>/dev/null \
                | grep -v '^#' > "$TMPD/uplnc_fmt_ub.s"
            cmp -s "$TMPD/uplnc_fmt_ua.s" "$TMPD/uplnc_fmt_ub.s" || { fmt_bad=1; echo "         $u differs"; }
        done
        [ "$fmt_bad" = 0 ] \
            && ok "uplncfmt formats examples, lib, and the compiler without changing code" \
            || bad "uplncfmt semantic preservation on real sources"
        # a line that overflows 158 bytes after formatting warns and exits 1
        printf 'func f()\n{\n  var int:%s;\n}\n' "$(python3 -c 'print("x"*155)')" \
            > "$TMPD/uplnc_fmt_long.e"
        timeout 5 "$FMT" "$TMPD/uplnc_fmt_long.e" >/dev/null 2>"$TMPD/uplnc_fmt_long.err"
        [ "$?" = 1 ] && grep -q 'exceeds 158 bytes' "$TMPD/uplnc_fmt_long.err" \
            && ok "uplncfmt warns and exits 1 on an over-long formatted line" \
            || bad "uplncfmt overlong-line warning"
        # Physical lines are not capped by an internal scratch buffer. The
        # warning is expected, but every byte must survive, especially with -w.
        python3 -c 'print("x"*5000)' > "$TMPD/uplnc_fmt_verylong.e"
        cp "$TMPD/uplnc_fmt_verylong.e" "$TMPD/uplnc_fmt_verylong.want"
        timeout 5 "$FMT" -w "$TMPD/uplnc_fmt_verylong.e" 2>/dev/null
        [ "$?" = 1 ] && cmp -s "$TMPD/uplnc_fmt_verylong.e" "$TMPD/uplnc_fmt_verylong.want" \
            && ok "uplncfmt -w preserves physical lines beyond 4095 bytes" \
            || bad "uplncfmt physical-line preservation"
        # Atomic replacement retains mode bits and follows a symlink rather
        # than replacing the link itself.
        printf 'func z()\n{\nreturn 0;\n}\n' > "$TMPD/uplnc_fmt_mode.e"
        chmod 755 "$TMPD/uplnc_fmt_mode.e"
        ln -s "$TMPD/uplnc_fmt_mode.e" "$TMPD/uplnc_fmt_link.e"
        timeout 5 "$FMT" -w "$TMPD/uplnc_fmt_link.e" 2>/dev/null
        fmt_rc=$?
        mode=$(stat -c %a "$TMPD/uplnc_fmt_mode.e")
        [ "$fmt_rc" = 0 ] && [ -L "$TMPD/uplnc_fmt_link.e" ] && [ "$mode" = 755 ] \
            && grep -q '^  return 0;$' "$TMPD/uplnc_fmt_mode.e" \
            && ok "uplncfmt -w preserves modes and symlink identity" \
            || bad "uplncfmt atomic replacement metadata"
        # A failed temp-file creation must be diagnosed as such (mkstemp's C
        # `int` -1 is unextended on 64-bit-word targets; cint() recovers the
        # sign so the fd<0 check fires and the message is accurate) and the
        # original file left byte-for-byte intact.
        mkdir -p "$TMPD/uplnc_fmt_rodir"
        printf 'func q()\n{\nreturn 1;\n}\n' > "$TMPD/uplnc_fmt_rodir/f.e"
        cp "$TMPD/uplnc_fmt_rodir/f.e" "$TMPD/uplnc_fmt_rodir_orig"
        chmod 555 "$TMPD/uplnc_fmt_rodir"
        timeout 5 "$FMT" -w "$TMPD/uplnc_fmt_rodir/f.e" 2>"$TMPD/uplnc_fmt_rodir.err"
        fmt_rc=$?
        chmod 755 "$TMPD/uplnc_fmt_rodir"
        [ "$fmt_rc" = 2 ] \
            && grep -q 'cannot create temporary file' "$TMPD/uplnc_fmt_rodir.err" \
            && cmp -s "$TMPD/uplnc_fmt_rodir/f.e" "$TMPD/uplnc_fmt_rodir_orig" \
            && ok "uplncfmt diagnoses a failed temp file and keeps the original" \
            || bad "uplncfmt temp-file failure handling"
        # Buffered output failures must be visible to scripts.
        if [ -e /dev/full ]; then
            timeout 5 "$FMT" "$TMPD/uplnc_fmt_want.e" > /dev/full 2>"$TMPD/uplnc_fmt_full.err"
            [ "$?" = 2 ] && grep -q 'write error' "$TMPD/uplnc_fmt_full.err" \
                && ok "uplncfmt reports output write failures" \
                || bad "uplncfmt output failure status"
        fi
        # usage/error statuses
        timeout 5 "$FMT" -z </dev/null >/dev/null 2>&1; [ "$?" = 2 ] \
            && ok "uplncfmt rejects unknown options (status 2)" || bad "uplncfmt usage"
        timeout 5 "$FMT" "$TMPD/uplnc_fmt_absent.e" >/dev/null 2>&1; [ "$?" = 2 ] \
            && ok "uplncfmt reports a missing file (status 2)" || bad "uplncfmt missing file"
    else
        bad "uplncfmt.e build"
    fi
fi

echo "[12] -g debug info: .file/.loc line tables, with machine code unchanged"
cat > "$TMPD/uplnc_dbg.e" <<'DBGEOF'
func addone(x:int)
{
  return x+1;
}
func main()
{
  var int:i;
  i=addone(41);
  i=i+1;
  return i-1;
}
DBGEOF
./build/lpp1 "$TMPD/uplnc_dbg.e" > "$TMPD/uplnc_dbg.i" 2>/dev/null

# line accuracy: the statements on lines 3 and 8..10 must appear verbatim
./build/langc -march=x86_64 -g < "$TMPD/uplnc_dbg.i" > "$TMPD/uplnc_dbg_g.s" 2>/dev/null
if grep -q '\.file 1 ' "$TMPD/uplnc_dbg_g.s" \
        && grep -q '^	\.loc 1 3$' "$TMPD/uplnc_dbg_g.s" \
        && grep -q '^	\.loc 1 8$' "$TMPD/uplnc_dbg_g.s" \
        && grep -q '^	\.loc 1 9$' "$TMPD/uplnc_dbg_g.s" \
        && grep -q '^	\.loc 1 10$' "$TMPD/uplnc_dbg_g.s"; then
    ok "-g emits .file and statement-accurate .loc directives"
else
    bad "-g .loc line accuracy"
fi

# default output stays free of debug directives
./build/langc -march=x86_64 < "$TMPD/uplnc_dbg.i" > "$TMPD/uplnc_dbg_ng.s" 2>/dev/null
if grep -q '\.loc\|\.file' "$TMPD/uplnc_dbg_ng.s"; then
    bad "no .loc/.file without -g"
else
    ok "no .loc/.file without -g"
fi

# -g must not change the generated instructions on any backend. Strip the
# debug-only output (whole .debug_* sections, CFI/line directives, debug
# labels) from the -g assembly and normalize redundant .text directives on
# both sides; what remains must be byte-identical.
cat > "$TMPD/uplnc_stripdbg.awk" <<'DBGEOF'
/^\t\.section \.debug_/ { indbg=1; next }
/^\t\.section / { indbg=0 }
/^\t\.text/ { indbg=0; next }
/^\t\.data/ { indbg=0 }
indbg { next }
/^\t\.cfi_/ { next }
/^\t\.loc / { next }
/^\t\.file / { next }
/^\.LFB[0-9]+:$/ { next }
/^\.LFE[0-9]+:$/ { next }
/^\.Ltext0:$/ { next }
/^\.Letext0:$/ { next }
{ print }
DBGEOF
for a in i386 x86_64 arm64 riscv64 mips64; do
    ./build/langc "-march=$a"    < "$TMPD/uplnc_dbg.i" > "$TMPD/uplnc_dbg_$a.s"  2>/dev/null
    ./build/langc "-march=$a" -g < "$TMPD/uplnc_dbg.i" > "$TMPD/uplnc_dbg_${a}_g.s" 2>/dev/null
    if awk -f "$TMPD/uplnc_stripdbg.awk" "$TMPD/uplnc_dbg_${a}_g.s" \
            | cmp -s - <(grep -v '^	\.text$' "$TMPD/uplnc_dbg_$a.s"); then
        ok "-g leaves $a code unchanged (directives only)"
    else
        bad "-g perturbs $a code"
    fi
done

# a second file via #include gets its own .file number
cat > "$TMPD/uplnc_dbg_inc.he" <<'DBGEOF'
func triple(x:int)
{
  return x*3;
}
DBGEOF
printf '#include "uplnc_dbg_inc.he"\nfunc main()\n{\n  return triple(14);\n}\n' \
    > "$TMPD/uplnc_dbg_multi.e"
./build/lpp1 "$TMPD/uplnc_dbg_multi.e" 2>/dev/null \
    | ./build/langc -march=x86_64 -g > "$TMPD/uplnc_dbg_multi.s" 2>/dev/null
if grep -q '\.file 1 .*uplnc_dbg_inc\.he' "$TMPD/uplnc_dbg_multi.s" \
        && grep -q '\.file 2 .*uplnc_dbg_multi\.e' "$TMPD/uplnc_dbg_multi.s" \
        && grep -q '^	\.loc 2 4$' "$TMPD/uplnc_dbg_multi.s"; then
    ok "-g assigns per-file numbers across #include"
else
    bad "-g multi-file .file numbering"
fi

# preserve lpp1's full filename instead of truncating it at the old 79-byte limit
DBGLONG="$TMPD/uplnc_dbg_abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmnop.e"
cp "$TMPD/uplnc_dbg.e" "$DBGLONG"
./build/lpp1 "$DBGLONG" > "$TMPD/uplnc_dbg_long.i" 2>/dev/null
./build/langc -march=x86_64 -g < "$TMPD/uplnc_dbg_long.i" \
    > "$TMPD/uplnc_dbg_long.s" 2>/dev/null
if grep -Fq "$DBGLONG" "$TMPD/uplnc_dbg_long.s"; then
    ok "-g preserves long source filenames"
else
    bad "-g long source filename"
fi

# gas quoted strings treat backslash as an escape, so .file must double it
DBGBSL="$TMPD/uplnc_dbg_back\\name.e"
cp "$TMPD/uplnc_dbg.e" "$DBGBSL"
./build/lpp1 "$DBGBSL" > "$TMPD/uplnc_dbg_bslash.i" 2>/dev/null
./build/langc -march=x86_64 -g < "$TMPD/uplnc_dbg_bslash.i" \
    > "$TMPD/uplnc_dbg_bslash.s" 2>/dev/null
if grep -Fq 'uplnc_dbg_back\\name.e"' "$TMPD/uplnc_dbg_bslash.s"; then
    ok "-g escapes backslashes in assembler filenames"
else
    bad "-g assembler filename escaping"
fi

# comp_dir is also a quoted GAS string. A newline in the working directory
# must remain data rather than terminating the directive and injecting syntax.
DBGCTRL="$TMPD/uplnc_dbg_ctrl"$'\n'"dir"
mkdir "$DBGCTRL"
cp "$TMPD/uplnc_dbg.e" "$DBGCTRL/main.e"
if (cd "$DBGCTRL" \
        && "$TDIR/build/lpp1" main.e 2>/dev/null \
           | "$TDIR/build/langc" -march="$DRVARCH" -g \
             > "$TMPD/uplnc_dbg_ctrl.s" 2>"$TMPD/uplnc_dbg_ctrl.err") \
        && grep -Fq '\012' "$TMPD/uplnc_dbg_ctrl.s" \
        && cc -c -o "$TMPD/uplnc_dbg_ctrl.o" "$TMPD/uplnc_dbg_ctrl.s" \
              2>>"$TMPD/uplnc_dbg_ctrl.err" \
        && ! grep -q 'unterminated string' "$TMPD/uplnc_dbg_ctrl.err"; then
    ok "-g escapes control bytes in comp_dir assembler strings"
else
    bad "-g comp_dir control-byte escaping"
fi

# sequential includes may reference more files than the nesting depth; every
# distinct file must retain its own DWARF number.
i=0
while [ "$i" -le 100 ]; do
    printf '# 1 "uplnc_dbg_file_%03d.e"\nfunc dbg%03d(){return %d;}\n' \
        "$i" "$i" "$i"
    i=$((i+1))
done > "$TMPD/uplnc_dbg_many.i"
./build/langc -march=x86_64 -g < "$TMPD/uplnc_dbg_many.i" \
    > "$TMPD/uplnc_dbg_many.s" 2>/dev/null
if [ "$(grep -c '^	\.file ' "$TMPD/uplnc_dbg_many.s")" = 101 ] \
        && grep -q '^	\.file 101 "uplnc_dbg_file_100\.e"$' "$TMPD/uplnc_dbg_many.s" \
        && grep -q '^	\.loc 101 1$' "$TMPD/uplnc_dbg_many.s"; then
    ok "-g assigns distinct numbers beyond 100 source files"
else
    bad "-g dynamic source file table"
fi

# driver -g end-to-end on the host: binary runs and carries a .debug_line table
case "$(uname -m)" in
x86_64)
    if perl "$DRIVER" -march=x86_64 -g -o "$TMPD/uplnc_dbg_bin" "$TMPD/uplnc_dbg.e" \
            >/dev/null 2>&1 && "$TMPD/uplnc_dbg_bin"; [ $? = 42 ]; then
        ok "driver -g binary builds and runs (42)"
    else
        bad "driver -g build/run"
    fi
    if command -v objdump >/dev/null \
            && objdump --dwarf=decodedline "$TMPD/uplnc_dbg_bin" 2>/dev/null \
               | grep -q 'uplnc_dbg\.e'; then
        ok "driver -g binary has a DWARF line table"
    else
        bad "driver -g DWARF line table"
    fi
    if command -v gdb >/dev/null; then
        if gdb -batch -q -ex 'break uplnc_dbg.e:9' -ex run -ex 'info line' \
                "$TMPD/uplnc_dbg_bin" 2>/dev/null \
                | grep -q 'Line 9 of .*uplnc_dbg\.e'; then
            ok "gdb stops at a source line set by file:line"
        else
            bad "gdb file:line breakpoint"
        fi
    else
        echo "  skip - no gdb on host"
    fi

    # debug part 2: CFI unwinding + variable/type DIEs (print, locals, bt)
    cat > "$TMPD/uplnc_dbg2.e" <<'DBGEOF'
struct point{int x;int y;};
func dist2(p:*point)
{
  var int:dx,dy;
  dx=p->x;
  dy=p->y;
  return dx*dx+dy*dy;
}
func main()
{
  var p:point;
  var int:r;
  var double:scale;
  scale=2.5;
  p.x=3;
  p.y=4;
  r=dist2(&p);
  if(r==25)return 42;
  return 1;
}
DBGEOF
    if perl "$DRIVER" -march=x86_64 -g -o "$TMPD/uplnc_dbg2_bin" "$TMPD/uplnc_dbg2.e" \
            >/dev/null 2>&1 && "$TMPD/uplnc_dbg2_bin"; [ $? = 42 ]; then
        ok "debug-part2 test binary builds and runs (42)"
    else
        bad "debug-part2 build/run"
    fi
    if command -v readelf >/dev/null; then
        readelf --debug-dump=info "$TMPD/uplnc_dbg2_bin" > "$TMPD/uplnc_dbg2.info" 2>/dev/null
        if grep -q 'DW_TAG_structure_type' "$TMPD/uplnc_dbg2.info" \
                && grep -q 'DW_TAG_member' "$TMPD/uplnc_dbg2.info" \
                && grep -q 'DW_TAG_formal_parameter' "$TMPD/uplnc_dbg2.info" \
                && grep -q 'DW_OP_fbreg' "$TMPD/uplnc_dbg2.info"; then
            ok "-g emits struct/member/parameter DIEs with frame locations"
        else
            bad "-g DIE structure"
        fi
        if readelf --debug-dump=frames "$TMPD/uplnc_dbg2_bin" 2>/dev/null \
                | grep -q 'FDE'; then
            ok "-g emits .debug_frame FDEs (CFI)"
        else
            bad "-g CFI frames"
        fi
    else
        echo "  skip - no readelf on host"
    fi
    if command -v gdb >/dev/null; then
        gdb -batch -q -ex 'break uplnc_dbg2.e:17' -ex run \
            -ex 'print p' -ex 'print scale' -ex 'ptype p' \
            "$TMPD/uplnc_dbg2_bin" > "$TMPD/uplnc_dbg2.gdb" 2>/dev/null
        if grep -q '{x = 3, y = 4}' "$TMPD/uplnc_dbg2.gdb" \
                && grep -q '= 2\.5' "$TMPD/uplnc_dbg2.gdb" \
                && grep -q 'int x;' "$TMPD/uplnc_dbg2.gdb"; then
            ok "gdb prints struct locals, doubles, and member types"
        else
            bad "gdb variable DIEs (print/ptype)"
        fi
        gdb -batch -q -ex 'break uplnc_dbg2.e:5' -ex run -ex bt \
            "$TMPD/uplnc_dbg2_bin" > "$TMPD/uplnc_dbg2.bt" 2>/dev/null
        if grep -q '#0 .*dist2' "$TMPD/uplnc_dbg2.bt" \
                && grep -q '#1 .*main.*uplnc_dbg2\.e' "$TMPD/uplnc_dbg2.bt"; then
            ok "gdb backtraces through CFI with parameter values"
        else
            bad "gdb CFI backtrace"
        fi
    fi

    # Metadata edges: stack-passed args stay formal parameters, globals retain
    # their type/location, and variadic signatures retain the ellipsis.
    cat > "$TMPD/uplnc_dbgmeta.e" <<'DBGEOF'
var int:dbg_global = 99;
func sum7(a:int,b:int,c:int,d:int,e:int,f:int,g:int)
{
  return a+b+c+d+e+f+g;
}
func vari(fmt:*char,...)
{
  return 0;
}
func main()
{
  if((sum7(1,2,3,4,5,6,7)==28)&&(dbg_global==99))return 42;
  return 1;
}
DBGEOF
    if perl "$DRIVER" -march=x86_64 -g -o "$TMPD/uplnc_dbgmeta_bin" \
            "$TMPD/uplnc_dbgmeta.e" >/dev/null 2>&1 \
            && "$TMPD/uplnc_dbgmeta_bin"; [ $? = 42 ]; then
        ok "debug metadata edge test binary builds and runs (42)"
    else
        bad "debug metadata edge build/run"
    fi
    if command -v readelf >/dev/null; then
        readelf --debug-dump=info "$TMPD/uplnc_dbgmeta_bin" \
            > "$TMPD/uplnc_dbgmeta.info" 2>/dev/null
        if [ "$(grep -c 'DW_TAG_formal_parameter' "$TMPD/uplnc_dbgmeta.info")" = 8 ] \
                && grep -q 'DW_TAG_unspecified_parameters' "$TMPD/uplnc_dbgmeta.info" \
                && grep -q 'DW_AT_name.*dbg_global' "$TMPD/uplnc_dbgmeta.info" \
                && grep -q 'DW_OP_addr' "$TMPD/uplnc_dbgmeta.info"; then
            ok "-g preserves stack parameters, varargs, and global locations"
        else
            bad "-g parameter/global DIE edges"
        fi

        printf 'var int:only_global = 7;\n' > "$TMPD/uplnc_dbgglobal.e"
        if perl "$DRIVER" -march=x86_64 -g -c -o "$TMPD/uplnc_dbgglobal.o" \
                "$TMPD/uplnc_dbgglobal.e" >/dev/null 2>&1 \
                && readelf --debug-dump=info "$TMPD/uplnc_dbgglobal.o" \
                   > "$TMPD/uplnc_dbgglobal.info" 2>/dev/null \
                && grep -q 'DW_AT_name.*only_global' "$TMPD/uplnc_dbgglobal.info" \
                && grep -q 'DW_OP_addr' "$TMPD/uplnc_dbgglobal.info"; then
            ok "-g emits globals for a function-free translation unit"
        else
            bad "-g global-only compile unit"
        fi
    fi
    if command -v gdb >/dev/null; then
        gdb -batch -q -ex 'ptype sum7' -ex 'ptype vari' -ex 'ptype dbg_global' \
            "$TMPD/uplnc_dbgmeta_bin" > "$TMPD/uplnc_dbgmeta.gdb" 2>/dev/null
        if grep -q 'int (int, int, int, int, int, int, int)' "$TMPD/uplnc_dbgmeta.gdb" \
                && grep -q 'int (char \*, \.\.\.)' "$TMPD/uplnc_dbgmeta.gdb" \
                && grep -q '^type = int$' "$TMPD/uplnc_dbgmeta.gdb"; then
            ok "gdb sees complete signatures and the global type"
        else
            bad "gdb parameter/global metadata"
        fi
    fi

    # debug part 3: register-promoted locals carry DW_OP_reg locations (they
    # used to be "optimized out"), and the CU carries DW_AT_comp_dir. leafsum's
    # s/i live in caller-saved leaf registers; outersum's acc/i live in the
    # callee-saved non-leaf registers, which inner reuses for its own k/t -- so
    # reading outersum's values from inside inner forces the debugger through
    # the prologue's .cfi_offset save slots.
    cat > "$TMPD/uplnc_dbg3.e" <<'DBGEOF'
func leafsum(n:int)
{
  var int:i,s;
  s=0;
  i=1;
  while(i<=n)
  {
    s=s+i;
    i=i+1;
  }
  return s;
}
func inner(v:int)
{
  var int:k,t;
  t=0;
  k=0;
  while(k<v)
  {
    t=t+leafsum(k);
    k=k+1;
  }
  return t+v;
}
func outersum(n:int)
{
  var int:i,acc;
  acc=0;
  i=0;
  while(i<n)
  {
    acc=acc+inner(i);
    i=i+1;
  }
  return acc;
}
func main()
{
  var int:r;
  r=leafsum(10)+outersum(4);
  if(r==66)return 42;
  return 1;
}
DBGEOF
    if perl "$DRIVER" -march=x86_64 -g -o "$TMPD/uplnc_dbg3_bin" \
            "$TMPD/uplnc_dbg3.e" >/dev/null 2>&1 \
            && "$TMPD/uplnc_dbg3_bin"; [ $? = 42 ]; then
        ok "debug-part3 test binary builds and runs (42)"
    else
        bad "debug-part3 build/run"
    fi
    if command -v readelf >/dev/null; then
        readelf --debug-dump=info "$TMPD/uplnc_dbg3_bin" \
            > "$TMPD/uplnc_dbg3.info" 2>/dev/null
        if grep -q 'DW_OP_reg10' "$TMPD/uplnc_dbg3.info" \
                && grep -q 'DW_OP_reg14' "$TMPD/uplnc_dbg3.info" \
                && grep -q 'DW_AT_comp_dir' "$TMPD/uplnc_dbg3.info"; then
            ok "-g promoted locals get DW_OP_reg locations; CU gets comp_dir"
        else
            bad "-g register-location/comp_dir DIEs"
        fi

        # Sequential block scopes reuse frame slots. The later double is not a
        # promotion candidate and must not inherit the earlier int's register.
        cat > "$TMPD/uplnc_dbg_alias.e" <<'DBGEOF'
func main()
{
  if(1)
  {
    var int:a;
    a=7;
    if(a!=7)return 1;
  }
  if(1)
  {
    var double:d;
    d=2.5;
    if(d==2.5)return 42;
  }
  return 1;
}
DBGEOF
        if perl "$DRIVER" -march=x86_64 -g -o "$TMPD/uplnc_dbg_alias_bin" \
                "$TMPD/uplnc_dbg_alias.e" >/dev/null 2>&1 \
                && "$TMPD/uplnc_dbg_alias_bin"; [ $? = 42 ]; then
            readelf --debug-dump=info "$TMPD/uplnc_dbg_alias_bin" \
                > "$TMPD/uplnc_dbg_alias.info" 2>/dev/null
            if grep -A3 'DW_AT_name.*: a$' "$TMPD/uplnc_dbg_alias.info" \
                    | grep -q 'DW_OP_reg10' \
                    && grep -A3 'DW_AT_name.*: d$' "$TMPD/uplnc_dbg_alias.info" \
                       | grep -q 'DW_OP_fbreg'; then
                ok "-g keeps reused frame slots tied to the correct source local"
            else
                bad "-g reused-slot variable location"
            fi
        else
            bad "-g reused-slot debug test build/run"
        fi
    fi
    if command -v gdb >/dev/null; then
        # Stop 1: leafsum(10) from main (its first call): s=55, i=11 from the
        # live leaf registers. Stop 2: the 4th arrival at inner's return is
        # inner(3): t=4, k=3 from inner's own registers, then outersum's
        # acc=4, i=3 recovered from the CFI save slots under them.
        gdb -batch -q \
            -ex 'break uplnc_dbg3.e:11' -ex run -ex 'print s' -ex 'print i' \
            -ex 'delete' \
            -ex 'break uplnc_dbg3.e:23' -ex 'ignore 2 3' -ex continue \
            -ex 'print t' -ex 'print k' \
            -ex 'frame 1' -ex 'print acc' -ex 'print i' \
            "$TMPD/uplnc_dbg3_bin" > "$TMPD/uplnc_dbg3.gdb" 2>/dev/null
        if grep -q '^\$1 = 55$' "$TMPD/uplnc_dbg3.gdb" \
                && grep -q '^\$2 = 11$' "$TMPD/uplnc_dbg3.gdb" \
                && grep -q '^\$3 = 4$' "$TMPD/uplnc_dbg3.gdb" \
                && grep -q '^\$4 = 3$' "$TMPD/uplnc_dbg3.gdb" \
                && grep -q '^\$5 = 4$' "$TMPD/uplnc_dbg3.gdb" \
                && grep -q '^\$6 = 3$' "$TMPD/uplnc_dbg3.gdb" \
                && ! grep -q 'optimized out' "$TMPD/uplnc_dbg3.gdb"; then
            ok "gdb prints promoted locals, including an outer frame's via CFI"
        else
            bad "gdb promoted-local register locations"
        fi
        # comp_dir end to end: compile with a relative source path, then make
        # gdb resolve the source from an unrelated working directory.
        ( cd "$TMPD" && perl "$DRIVER" -march=x86_64 -g -o uplnc_dbg3_rel \
            uplnc_dbg3.e ) >/dev/null 2>&1
        ( cd / && gdb -batch -q -ex 'break uplnc_dbg3.e:11' -ex run \
            -ex 'info source' "$TMPD/uplnc_dbg3_rel" ) \
            > "$TMPD/uplnc_dbg3_rel.gdb" 2>/dev/null
        if grep -q 'Located in.*/uplnc_dbg3\.e' "$TMPD/uplnc_dbg3_rel.gdb"; then
            ok "comp_dir resolves a relative-path build from another directory"
        else
            bad "comp_dir source resolution"
        fi
    fi
    # The same DIEs on the cross backends, checked in the emitted assembly
    # (toolchain-free): each variable location is a 1-byte exprloc whose
    # operand is DW_OP_reg0+n = 80+n for that target's leaf/non-leaf registers.
    while read -r xarch leafb nonleafb; do
        "$TDIR/build/lpp1" "$TMPD/uplnc_dbg3.e" 2>/dev/null \
            | "$TDIR/build/langc" -march="$xarch" -g \
            > "$TMPD/uplnc_dbg3_$xarch.s" 2>/dev/null
        if grep -A1 '\.uleb128 1$' "$TMPD/uplnc_dbg3_$xarch.s" \
                | grep -q "\.byte $leafb\$" \
                && grep -A1 '\.uleb128 1$' "$TMPD/uplnc_dbg3_$xarch.s" \
                | grep -q "\.byte $nonleafb\$"; then
            ok "$xarch -g promoted locals get DW_OP_reg (bytes $leafb/$nonleafb)"
        else
            bad "$xarch -g register-location DIEs"
        fi
    done <<'XREGEOF'
arm64 91 99
riscv64 109 89
mips64 88 96
XREGEOF
    ;;
*)
    echo "  skip - host is not x86_64"
    ;;
esac

echo "[13] benchmark harness + peephole assembly-shape regressions"
if bash bench/bench.sh --time-runs 0 >"$TMPD/uplnc_bench_bad.out" \
        2>"$TMPD/uplnc_bench_bad.err"; then
    bad "benchmark harness rejects an invalid timing count"
elif grep -q 'positive integer' "$TMPD/uplnc_bench_bad.err"; then
    ok "benchmark harness rejects an invalid timing count"
else
    bad "benchmark harness invalid timing diagnostic"
fi

# Exercise the IR pass directly, including the arm64 case that valid source
# currently avoids by allocating locals in full stack slots. Link the same four
# generated units as stage-0, renaming langc's entry point so the harness owns
# main while still using the compiler's real target global and peephole code.
cat > "$TMPD/uplnc_peephole_unit.c" <<'PCEOF'
#include "codegen.h"
#ifdef main
#undef main
#endif
extern int peephole();
static void op(scode *c,int code,int arg,int reg)
{
  c->code=code;c->arg=arg;c->reg=reg;c->promid=0;c->str=0;
}
int main(void)
{
  scode c[3];scodegen cg;
  target.wordsize=8;target.stackslot=16;
  cg.ncodeitems=3;cg.codeptr=3;cg.codes=c;

  op(c+0,CD_MODSTK,-8,RG_A);op(c+1,CD_LOC,1,RG_A);
  op(c+2,CD_MODSTK,-8,RG_A);peephole(&cg);
  if((c[0].code!=CD_MODSTK)||(c[2].code!=CD_MODSTK)||(c[2].arg!=-8))return 1;

  op(c+0,CD_MODSTK,-16,RG_A);op(c+1,CD_LOC,1,RG_A);
  op(c+2,CD_MODSTK,-16,RG_A);peephole(&cg);
  if((c[0].code!=CD_IGNORE)||(c[2].code!=CD_MODSTK)||(c[2].arg!=-32))return 2;

  op(c+0,CD_STLW,-8,RG_A);op(c+1,CD_LOC,1,RG_A);
  op(c+2,CD_LDLW,-8,RG_A);peephole(&cg);
  if(c[2].code!=CD_IGNORE)return 3;

  op(c+0,CD_STLW,-8,RG_A);op(c+1,CD_LOC,1,RG_A);
  op(c+2,CD_LDLW,-8,RG_D);peephole(&cg);
  if((c[2].code!=CD_MOVR)||(c[2].reg!=RG_D)||(c[2].arg!=RG_A))return 4;

  op(c+0,CD_STLW,-8,RG_A);op(c+1,CD_LOC,1,RG_A);
  op(c+2,CD_LDLW,-8,RG_A);c[0].promid=1;c[2].promid=2;peephole(&cg);
  if(c[2].code!=CD_LDLW)return 5;
  return 0;
}
PCEOF
if gcc -std=gnu89 -fsigned-char -w -Dmain=uplnc_langc_main -I build \
        "$TMPD/uplnc_peephole_unit.c" build/langc.c build/codegen.c \
        build/autodyn.c build/grph.c \
        -o "$TMPD/uplnc_peephole_unit" \
        && "$TMPD/uplnc_peephole_unit"; then
    ok "peephole IR rules merge only safe stack pairs and forward same-slot loads"
else
    bad "peephole IR rule unit coverage"
fi

# The two declarations produce adjacent CD_MODSTK operations separated only by
# -g markers. They must coalesce to one physical adjustment on both x86_64 and
# arm64; these exact sizes also exercise arm64's physical-delta calculation.
"$LPP" tests/progs/arith.e 2>/dev/null \
    | "$LANGC" -march=x86_64 -g > "$TMPD/uplnc_peephole_x64.s" 2>/dev/null
if [ "$(grep -c $'^\tsubq \$16, %rsp$' "$TMPD/uplnc_peephole_x64.s")" = 1 ] \
        && ! grep -q $'^\tsubq \$8, %rsp$' "$TMPD/uplnc_peephole_x64.s"; then
    ok "x86_64 coalesces adjacent frame adjustments across debug markers"
else
    bad "x86_64 modstk coalescing shape"
fi
"$LPP" tests/progs/arith.e 2>/dev/null \
    | "$LANGC" -march=arm64 -g > "$TMPD/uplnc_peephole_arm64.s" 2>/dev/null
if [ "$(grep -c $'^\tsub sp, sp, #32$' "$TMPD/uplnc_peephole_arm64.s")" = 1 ] \
        && ! grep -q $'^\tsub sp, sp, #16$' "$TMPD/uplnc_peephole_arm64.s"; then
    ok "arm64 coalesces only physically equivalent frame adjustments"
else
    bad "arm64 modstk coalescing shape"
fi

# Taking a's address prevents local promotion. The store in `a=40` and load in
# the next statement are separated only by a CD_LOC under -g; forwarding should
# preserve the store and eliminate the frame reload into the accumulator.
cat > "$TMPD/uplnc_storeload.e" <<'PEEOF'
func touch(p:*int){return 0;}
func main()
{
  var int:a;
  touch(&a);
  a=40;
  return a+2;
}
PEEOF
"$LPP" "$TMPD/uplnc_storeload.e" 2>/dev/null \
    | "$LANGC" -march=x86_64 -g > "$TMPD/uplnc_storeload.s" 2>/dev/null
if grep -qE $'^\tmovq %rax, -[0-9]+\(%rbp\)$' "$TMPD/uplnc_storeload.s" \
        && ! grep -qE $'^\tmovq -[0-9]+\(%rbp\), %rax$' "$TMPD/uplnc_storeload.s"; then
    ok "same-slot store/load forwarding crosses debug markers safely"
else
    bad "store/load forwarding shape"
fi

echo
echo "==== $pass passed, $fail failed ===="
[ "$fail" -eq 0 ]

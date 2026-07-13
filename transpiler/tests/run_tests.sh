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
        && "$DRVSPACE/fmtdemo" >"$DRVSPACE/fmtdemo.out" \
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

    # x86_64/arm64 pass FP varargs in FP registers, but this vastart() model
    # exposes the integer register tail; reject the unsupported shape cleanly.
    printf 'func first(...){var p:*int;p=vastart();return p[0];}\nfunc main(){return first(1.0);}\n' > "$TMPD/uplnc_varargs_fp.e"
    if "$LPP" "$TMPD/uplnc_varargs_fp.e" 2>/dev/null \
            | "$LANGC" -march=x86_64 > "$TMPD/uplnc_varargs_fp.s" 2>"$TMPD/uplnc_varargs_fp.err"; then
        bad "floating-point variadic arg exits nonzero"
    elif grep -q 'floating-point variadic arguments' "$TMPD/uplnc_varargs_fp.s"; then
        ok "floating-point variadic arg diagnosed"
    else
        bad "floating-point variadic arg diagnostic"
    fi
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
        "$FD" > "$TMPD/uplnc_fmtdemo.out" 2>&1
        printf 'int: 42 -7 0\npad: [    42] [000042] [   -42]\nunsigned: 4294967295\nhex: ff [0000beef] [    beef]\nstr: abc, char: xyz, pct: 100%%\nmix: val=1000 (03e8)\n' > "$TMPD/uplnc_fmtdemo.want"
        cmp -s "$TMPD/uplnc_fmtdemo.out" "$TMPD/uplnc_fmtdemo.want" \
            && ok "fmtdemo.e matches the lib/fmt.e output contract" || bad "fmtdemo.e output"
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
fi

echo
echo "==== $pass passed, $fail failed ===="
[ "$fail" -eq 0 ]

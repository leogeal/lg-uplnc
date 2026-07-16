#!/usr/bin/env bash
# UPLNC benchmark harness: static + dynamic numbers for the code generator.
#
#   ./bench/bench.sh                 # all benchmarks, all buildable targets
#   ./bench/bench.sh --time-runs 5   # more timing samples (default 3)
#   ./bench/bench.sh --no-time       # static metrics only (fast, deterministic)
#
# For every benchmark and target this reports:
#   insns  - instruction count of the generated .s (directives/labels excluded);
#            deterministic, toolchain-free, comparable across compiler versions
#   time   - best-of-N wall seconds, native x86_64 host only (qemu timing says
#            more about qemu than about the generated code)
# Every binary self-checks its result and the harness fails loudly on any
# wrong checksum, so the suite doubles as a correctness gate.
set -uo pipefail
cd "$(dirname "$0")/.."

DRIVER=../src/langdrv.pl
BENCHES=(sieve fib matmul strops mandel)
TARGETS=(i386 x86_64 arm64 riscv64 mips64)
TIMERUNS=3
DOTIME=1
while [ $# -gt 0 ]; do
    case "$1" in
    --no-time) DOTIME=0 ;;
    --time-runs) shift; TIMERUNS=$1 ;;
    *) echo "usage: bench.sh [--no-time] [--time-runs N]" >&2; exit 2 ;;
    esac
    shift
done

# per-target assembler/runner, mirroring tests/run_tests.sh gating
tool_for() {
    case "$1" in
    i386)    command -v gcc-9 >/dev/null && echo "gcc-9 -m32 -no-pie" ;;
    x86_64)  echo "gcc -no-pie" ;;
    arm64)   command -v aarch64-linux-gnu-gcc >/dev/null && echo "aarch64-linux-gnu-gcc -static" ;;
    riscv64) command -v riscv64-linux-gnu-gcc >/dev/null && echo "riscv64-linux-gnu-gcc -static" ;;
    mips64)  command -v mips64-linux-gnuabi64-gcc >/dev/null \
                 && echo "mips64-linux-gnuabi64-gcc -static -mno-abicalls -fno-pic -G 0" ;;
    esac
}
runner_for() {
    case "$1" in
    i386|x86_64) echo "" ;;
    arm64)   command -v qemu-aarch64-static >/dev/null && echo "qemu-aarch64-static" ;;
    riscv64) command -v qemu-riscv64-static >/dev/null && echo "qemu-riscv64-static" ;;
    mips64)  echo "${QEMU_MIPS:-qemu-mips64-static}" ;;
    esac
}

TMPB=$(mktemp -d "${TMPDIR:-/tmp}/uplnc-bench.XXXXXX")
trap 'rm -rf "$TMPB"' EXIT
fail=0

printf '%-8s %-8s %8s %10s\n' benchmark target insns time
for b in "${BENCHES[@]}"; do
    for t in "${TARGETS[@]}"; do
        s="$TMPB/$b-$t.s"
        if ! perl "$DRIVER" "-march=$t" -S -o "$s" "bench/$b.e" >/dev/null 2>&1; then
            echo "FAIL: $b does not compile for $t" >&2; fail=1; continue
        fi
        insns=$(grep -c $'^\t[a-z]' "$s" || true)
        secs=-
        cc=$(tool_for "$t")
        if [ -n "$cc" ]; then
            bin="$TMPB/$b-$t"
            if $cc -o "$bin" "$s" 2>/dev/null; then
                run=$(runner_for "$t")
                if [ "$t" = x86_64 ] && [ "$(uname -m)" = x86_64 ]; then
                    if ! "$bin" >/dev/null; then
                        echo "FAIL: $b wrong checksum on $t" >&2; fail=1
                    elif [ "$DOTIME" = 1 ]; then
                        secs=$(python3 - "$bin" "$TIMERUNS" <<'PYEOF'
import subprocess,sys,time
best=None
for _ in range(int(sys.argv[2])):
    t0=time.monotonic()
    subprocess.run([sys.argv[1]],stdout=subprocess.DEVNULL,check=True)
    dt=time.monotonic()-t0
    best=dt if best is None or dt<best else best
print("%.3f"%best)
PYEOF
)
                    fi
                elif [ -n "$run" ] && command -v ${run%% *} >/dev/null 2>&1; then
                    if ! $run "$bin" >/dev/null; then
                        echo "FAIL: $b wrong checksum on $t" >&2; fail=1
                    fi
                fi
            else
                echo "FAIL: $b does not assemble for $t" >&2; fail=1
            fi
        fi
        printf '%-8s %-8s %8s %10s\n' "$b" "$t" "$insns" "$secs"
    done
done
exit $fail

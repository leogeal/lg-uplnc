#!/usr/bin/env bash
# UPLNC benchmark harness: static + dynamic numbers for the code generator.
#
#   ./bench/bench.sh                         # all benchmarks, all targets
#   ./bench/bench.sh --target arm64          # one target (repeatable)
#   ./bench/bench.sh --time-runs 5           # timing samples (default 3)
#   ./bench/bench.sh --no-time               # correctness + static metrics
#   ./bench/bench.sh --target i386 --require-run --no-time
#
# For every benchmark and target this reports:
#   insns  - instruction count of the generated .s (directives/labels excluded)
#   time   - best-of-N native wall seconds; emulated targets are not timed
#   status - checked, assembled, static, or a failure reason
# Missing optional cross-toolchains leave an honest static/assembled row. CI
# uses --require-run for each backend it provisions, turning such skips into
# failures. Every executed binary self-checks its checksum.
set -uo pipefail
cd "$(dirname "$0")/.."

DRIVER=../src/langdrv.pl
BENCHES=(sieve fib matmul strops mandel)
ALL_TARGETS=(i386 x86_64 arm64 riscv64 mips64)
TARGETS=()
TIMERUNS=3
DOTIME=1
REQUIRE_RUN=0

usage() {
    echo "usage: bench.sh [--target ARCH] [--no-time] [--time-runs N] [--require-run]" >&2
    exit 2
}

while [ $# -gt 0 ]; do
    case "$1" in
    --no-time) DOTIME=0 ;;
    --require-run) REQUIRE_RUN=1 ;;
    --target)
        shift
        [ $# -gt 0 ] || usage
        case "$1" in
        i386|x86_64|arm64|riscv64|mips64) TARGETS+=("$1") ;;
        *) echo "bench.sh: unsupported target '$1'" >&2; usage ;;
        esac
        ;;
    --time-runs)
        shift
        [ $# -gt 0 ] || usage
        TIMERUNS=$1
        ;;
    *) usage ;;
    esac
    shift
done

if [ ${#TARGETS[@]} -eq 0 ]; then TARGETS=("${ALL_TARGETS[@]}"); fi
if ! [[ "$TIMERUNS" =~ ^[1-9][0-9]*$ ]]; then
    echo "bench.sh: --time-runs must be a positive integer" >&2
    exit 2
fi

TMPB=$(mktemp -d "${TMPDIR:-/tmp}/uplnc-bench.XXXXXX")
trap 'rm -rf "$TMPB"' EXIT
fail=0

host_arch() {
    case "$(uname -m)" in
    x86_64) echo x86_64 ;;
    i?86) echo i386 ;;
    aarch64) echo arm64 ;;
    riscv64) echo riscv64 ;;
    mips64) echo mips64 ;;
    *) echo unknown ;;
    esac
}
HOSTARCH=$(host_arch)

# Print a working assembler/linker command, or nothing when only static metrics
# are available. Keep this in sync with langdrv.pl's supported toolchains.
tool_for() {
    local t="$1" cc
    case "$t" in
    i386)
        for cc in gcc gcc-14 gcc-13 gcc-12 gcc-11 gcc-10 gcc-9; do
            command -v "$cc" >/dev/null 2>&1 || continue
            if printf 'int main(void){return 0;}\n' \
                    | "$cc" -m32 -x c - -o "$TMPB/m32-probe" 2>/dev/null; then
                echo "$cc -m32 -no-pie"
                return
            fi
        done
        ;;
    x86_64)
        if [ "$HOSTARCH" = x86_64 ] && command -v gcc >/dev/null; then
            echo "gcc -no-pie"
        elif command -v x86_64-linux-gnu-gcc >/dev/null; then
            echo "x86_64-linux-gnu-gcc -static"
        fi
        ;;
    arm64)
        if command -v aarch64-linux-gnu-gcc >/dev/null; then
            echo "aarch64-linux-gnu-gcc -static"
        elif [ "$HOSTARCH" = arm64 ] && command -v gcc >/dev/null; then
            echo "gcc -no-pie"
        fi
        ;;
    riscv64)
        if command -v riscv64-linux-gnu-gcc >/dev/null; then
            echo "riscv64-linux-gnu-gcc -static"
        elif command -v riscv64-linux-gnu-gcc-10 >/dev/null; then
            echo "riscv64-linux-gnu-gcc-10 -static"
        elif [ "$HOSTARCH" = riscv64 ] && command -v gcc >/dev/null; then
            echo "gcc -no-pie"
        fi
        ;;
    mips64)
        if command -v mips64-linux-gnuabi64-gcc >/dev/null; then
            echo "mips64-linux-gnuabi64-gcc -static -mno-abicalls -fno-pic -G 0"
        elif [ "$HOSTARCH" = mips64 ] && command -v gcc >/dev/null; then
            echo "gcc -no-pie -mno-abicalls -fno-pic -G 0"
        fi
        ;;
    esac
}

# Print an explicit emulator fallback. Direct execution is attempted first so
# native hosts and configured binfmt handlers need no special case.
runner_for() {
    case "$1" in
    i386) command -v qemu-i386-static >/dev/null && echo "qemu-i386-static -L /" ;;
    x86_64) command -v qemu-x86_64-static >/dev/null && echo "qemu-x86_64-static" ;;
    arm64) command -v qemu-aarch64-static >/dev/null && echo "qemu-aarch64-static" ;;
    riscv64) command -v qemu-riscv64-static >/dev/null && echo "qemu-riscv64-static" ;;
    mips64)
        if [ -n "${QEMU_MIPS:-}" ]; then echo "$QEMU_MIPS"
        elif command -v qemu-mips64-static >/dev/null; then echo "qemu-mips64-static"
        fi
        ;;
    esac
}

direct_compatible() {
    case "$HOSTARCH:$1" in
    x86_64:x86_64|x86_64:i386|i386:i386|arm64:arm64|riscv64:riscv64|mips64:mips64)
        return 0 ;;
    *) return 1 ;;
    esac
}

# Return 0 for a valid checksum, 1 for a runnable binary with a bad result, and
# 125 when no execution route is available. EXECMODE records whether native
# timing is meaningful.
execute_binary() {
    local t="$1" bin="$2" run
    EXECMODE=none
    run=$(runner_for "$t")
    # Prefer an explicit emulator for a non-native target. Besides avoiding
    # dependence on binfmt, this handles hosts whose sandbox rejects the i386
    # syscall ABI even though their kernel and linker support 32-bit binaries.
    if [ "$t" != "$HOSTARCH" ] && [ -n "$run" ] \
            && command -v ${run%% *} >/dev/null 2>&1; then
        if $run "$bin" >/dev/null 2>&1; then EXECMODE=emulated; return 0; fi
        return 1
    fi
    if ( "$bin" >/dev/null 2>&1 ) 2>/dev/null; then EXECMODE=direct; return 0; fi
    if [ -n "$run" ] && command -v ${run%% *} >/dev/null 2>&1; then
        if $run "$bin" >/dev/null 2>&1; then EXECMODE=emulated; return 0; fi
        return 1
    fi
    if direct_compatible "$t"; then return 1; fi
    return 125
}

printf '%-8s %-8s %8s %10s %-10s\n' benchmark target insns time status
for b in "${BENCHES[@]}"; do
    for t in "${TARGETS[@]}"; do
        s="$TMPB/$b-$t.s"
        insns=-
        secs=-
        status=static
        if ! perl "$DRIVER" "-march=$t" -S -o "$s" "bench/$b.e" >/dev/null 2>&1; then
            echo "FAIL: $b does not compile for $t" >&2
            fail=1
            status=compile-fail
        else
            insns=$(grep -c $'^\t[a-z]' "$s" || true)
            cc=$(tool_for "$t")
            if [ -z "$cc" ]; then
                if [ "$REQUIRE_RUN" = 1 ]; then
                    echo "FAIL: no assembler/linker available for $t" >&2
                    fail=1
                    status=no-tool
                fi
            else
                bin="$TMPB/$b-$t"
                if ! $cc -o "$bin" "$s" 2>/dev/null; then
                    echo "FAIL: $b does not assemble for $t" >&2
                    fail=1
                    status=assemble-fail
                else
                    status=assembled
                    execute_binary "$t" "$bin"
                    rc=$?
                    if [ "$rc" = 0 ]; then
                        status=checked
                        if [ "$DOTIME" = 1 ] && [ "$EXECMODE" = direct ] \
                                && [ "$t" = "$HOSTARCH" ]; then
                            if ! secs=$(python3 - "$bin" "$TIMERUNS" <<'PYEOF'
import subprocess,sys,time
best=None
for _ in range(int(sys.argv[2])):
    t0=time.monotonic()
    subprocess.run([sys.argv[1]],stdout=subprocess.DEVNULL,check=True)
    dt=time.monotonic()-t0
    best=dt if best is None or dt<best else best
print("%.3f"%best)
PYEOF
); then
                                echo "FAIL: timing $b on $t failed" >&2
                                fail=1
                                secs=error
                                status=timer-fail
                            fi
                        fi
                    elif [ "$rc" = 125 ]; then
                        if [ "$REQUIRE_RUN" = 1 ]; then
                            echo "FAIL: no runner available for $t" >&2
                            fail=1
                            status=no-runner
                        fi
                    else
                        echo "FAIL: $b wrong checksum on $t" >&2
                        fail=1
                        status=check-fail
                    fi
                fi
            fi
        fi
        printf '%-8s %-8s %8s %10s %-10s\n' "$b" "$t" "$insns" "$secs" "$status"
    done
done
exit $fail

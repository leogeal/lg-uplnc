#!/usr/bin/env python3
"""Deterministic, process-isolated malformed-input fuzzer for lpp1 and langc."""

import argparse
import hashlib
import os
from pathlib import Path
import random
import subprocess
import sys
import tempfile


MAX_INPUT = 64 * 1024
INTERESTING = b"\x00\x01\x7f\x80\xff\n\r\t {}[]();,:*'\"#/\\+-="
TOKENS = (
    b"func main(){return 0;}\n",
    b"var int:x;",
    b"struct s{int x;};",
    b"if(1){",
    b"else",
    b"switch(0){case 0:",
    b"#define A A\n",
    b"#include \"missing.he\"\n",
    b"/*",
    b"*/",
    b"\"unterminated",
    b"'unterminated",
    b"012345678901234567890123456789012345678901234567890123456789",
)
SANITIZER_MARKERS = (
    b"AddressSanitizer",
    b"LeakSanitizer",
    b"UndefinedBehaviorSanitizer",
    b"runtime error:",
    b"Sanitizer:DEADLYSIGNAL",
)


def parse_args():
    parser = argparse.ArgumentParser(
        description="mutate UPLNC inputs under sanitizer-instrumented front ends"
    )
    parser.add_argument("--lpp", required=True, type=Path)
    parser.add_argument("--langc", required=True, type=Path)
    parser.add_argument(
        "--target", choices=("all", "lpp", "langc"), default="all"
    )
    parser.add_argument("--iterations", type=int, default=1000)
    parser.add_argument("--seed", type=int, default=0)
    parser.add_argument("--timeout", type=float, default=1.0)
    parser.add_argument("--artifacts", type=Path, default=Path("build/fuzz-artifacts"))
    args = parser.parse_args()
    if args.iterations < 0:
        parser.error("--iterations must be non-negative")
    if args.timeout <= 0:
        parser.error("--timeout must be positive")
    return args


def load_corpus(root):
    paths = sorted((root / "fuzz" / "corpus").glob("*.e"))
    paths += sorted((root / "tests" / "progs").glob("*.e"))
    corpus = []
    for path in paths:
        data = path.read_bytes()[:MAX_INPUT]
        if data not in corpus:
            corpus.append(data)
    corpus.extend((b"", b"\n", b"func main(){return 0;}\n"))
    return corpus


def bounded(data):
    return bytes(data[:MAX_INPUT])


def mutate(rng, original, corpus):
    data = bytearray(original)
    for _ in range(rng.randint(1, 8)):
        operation = rng.randrange(9)
        if operation == 0 and data:
            pos = rng.randrange(len(data))
            data[pos] ^= 1 << rng.randrange(8)
        elif operation == 1:
            pos = rng.randrange(len(data) + 1)
            data[pos:pos] = bytes((INTERESTING[rng.randrange(len(INTERESTING))],))
        elif operation == 2:
            pos = rng.randrange(len(data) + 1)
            data[pos:pos] = TOKENS[rng.randrange(len(TOKENS))]
        elif operation == 3 and data:
            start = rng.randrange(len(data))
            end = min(len(data), start + rng.randint(1, 128))
            del data[start:end]
        elif operation == 4 and data:
            start = rng.randrange(len(data))
            end = min(len(data), start + rng.randint(1, 128))
            pos = rng.randrange(len(data) + 1)
            data[pos:pos] = data[start:end]
        elif operation == 5:
            other = corpus[rng.randrange(len(corpus))]
            if other:
                start = rng.randrange(len(other))
                chunk = other[start : start + rng.randint(1, 256)]
                pos = rng.randrange(len(data) + 1)
                data[pos:pos] = chunk
        elif operation == 6:
            token = TOKENS[rng.randrange(len(TOKENS))]
            pos = rng.randrange(len(data) + 1)
            data[pos:pos] = token * rng.randint(2, 32)
        elif operation == 7 and data:
            del data[rng.randrange(len(data) + 1) :]
        else:
            data = bytearray(b"func fuzz(){\n" + data + b"\n}\n")
        if len(data) > MAX_INPUT:
            del data[MAX_INPUT:]
    return bounded(data)


def classify(result):
    for marker in SANITIZER_MARKERS:
        if marker in result.stderr:
            return "sanitizer"
    if result.returncode < 0:
        return "signal-%d" % -result.returncode
    if result.returncode not in (0, 1, 2):
        return "exit-%d" % result.returncode
    return None


def save_artifact(directory, target, data, stderr, reason, command):
    digest = hashlib.sha256(data).hexdigest()[:16]
    stem = directory / (target + "-" + reason + "-" + digest)
    directory.mkdir(parents=True, exist_ok=True)
    stem.with_suffix(".input").write_bytes(data)
    stem.with_suffix(".stderr").write_bytes(stderr)
    stem.with_suffix(".txt").write_text(
        "reason: %s\ncommand: %s\n" % (reason, " ".join(command)),
        encoding="ascii",
    )
    return stem.with_suffix(".input")


def run_case(target, command, data, timeout, cwd, artifacts):
    try:
        result = subprocess.run(
            command,
            input=data,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            cwd=cwd,
            timeout=timeout,
            check=False,
        )
    except subprocess.TimeoutExpired as exc:
        stderr = exc.stderr or b""
        path = save_artifact(
            artifacts, target, data, stderr, "timeout", command
        )
        return "timeout (%s)" % path
    reason = classify(result)
    if reason:
        path = save_artifact(
            artifacts, target, data, result.stderr, reason, command
        )
        return "%s (%s)" % (reason, path)
    return None


def fuzz_target(target, command, corpus, iterations, seed, timeout, artifacts):
    rng = random.Random(seed)
    cases = list(corpus)
    cases.extend(
        mutate(rng, corpus[rng.randrange(len(corpus))], corpus)
        for _ in range(iterations)
    )
    print("[fuzz] %s: %d corpus + %d mutated cases" % (
        target, len(corpus), iterations
    ))
    with tempfile.TemporaryDirectory(prefix="uplnc-fuzz-") as work:
        for number, data in enumerate(cases):
            finding = run_case(
                target, command, data, timeout, work, artifacts
            )
            if finding:
                print("[fuzz] %s case %d: %s" % (target, number, finding), file=sys.stderr)
                return False
    return True


def main():
    args = parse_args()
    root = Path(__file__).resolve().parent.parent
    lpp = args.lpp.resolve()
    langc = args.langc.resolve()
    for tool in (lpp, langc):
        if not tool.is_file() or not os.access(tool, os.X_OK):
            print("fuzz: cannot execute %s" % tool, file=sys.stderr)
            return 2

    corpus = load_corpus(root)
    targets = []
    if args.target in ("all", "lpp"):
        targets.append(("lpp", [str(lpp)]))
    if args.target in ("all", "langc"):
        targets.append(("langc", [str(langc), "-march=x86_64"]))

    good = True
    for index, (target, command) in enumerate(targets):
        good = fuzz_target(
            target,
            command,
            corpus,
            args.iterations,
            args.seed + index,
            args.timeout,
            (root / args.artifacts).resolve(),
        ) and good
    if good:
        print("[fuzz] no sanitizer failures, crashes, or timeouts")
        return 0
    return 1


if __name__ == "__main__":
    sys.exit(main())

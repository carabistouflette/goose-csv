#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Independent Python csv differential oracle for the supported byte dialect."""
from __future__ import annotations
import argparse
import csv
import hashlib
import io
import json
import platform
import random
import subprocess
import sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
DEFAULT = (1048576, 4194304, 67108864, 4096)
SEED = 712901

def token(data: bytes):
    return data.hex() or "-"

def encoded_row(row, ending="\r\n"):
    # Latin-1 is a reversible byte/str bridge, not encoding validation.
    sink = io.StringIO(newline="")
    csv.writer(sink, lineterminator="\r\n").writerow([x.decode("latin1") for x in row])
    return sink.getvalue().encode("latin1")[:-2] + ending.encode("ascii")

def decoded_rows(data):
    return [[x.encode("latin1") for x in row] for row in
            csv.reader(io.StringIO(data.decode("latin1"), newline=""), strict=True)]

def rows_response(rows):
    return "".join("R " + str(len(row)) + "".join(" " + token(x) for x in row) + ";" for row in rows) + "OK"

def corpus():
    rng = random.Random(SEED)
    cases = []
    samples = [b"", b"\r\n", b"\n", b'""', b'""\r\n', b",", b"a,", b"a,b\r\n",
               b'"a""b",c\r\n', b'"a\r\nb",c', b" first , second \n", b'"\x00\xff\x80",\xfe\r\n',
               b"\xef\xbb\xbfx,y\n", b"=1+1,+2,@name,-3\r\n"]
    rows = [[], [b""], [b"", b""], [b"a", b""], [b'a,b', b'a"b', b'a\r\nb'],
            [bytes(range(256))], [b"=1+1", b"@SUM(A1)", b"-3", b"+4"]]
    for _ in range(700):
        rows.append([rng.randbytes(rng.randrange(41)) for _ in range(rng.randrange(9))])
    for n in (15, 16, 17, 31, 32, 33, 63, 64, 65, 255, 256, 257):
        run = b"x" * n
        rows.extend([[run], [run + b'"' + run, b"tail"], [run + b"\r\n" + run],
                     [b'"' * n], [b"," + run], [b'""' + run],
                     [b"," + b'"a' * n], [run + b'"' * 8 + run]])
        samples.extend([run + b",tail\r\n", b'"' + run + b'""' + run + b'"\r\n',
                        b'"' + run + b"\r\n" + run + b'"\r\n'])
    for gap in (15, 16, 17):
        rows.append([b"," + (b"x" * gap + b'"') * 8])
    for n in (31, 32, 33):
        rows.append([b'"' + b"x" * (n - 2) + b'"'])
    for i, row in enumerate(rows):
        command = "W " + " ".join(map(str, DEFAULT)) + " " + str(len(row))
        if row: command += " " + " ".join(token(x) for x in row)
        cases.append((f"writer-{i}", command, "W " + token(encoded_row(row))))
        if i >= 707:
            size = len(encoded_row(row))
            for kind in ("row", "total"):
                for delta in (0, -1):
                    limits = (DEFAULT[0], size + delta if kind == "row" else DEFAULT[1],
                              size + delta if kind == "total" else DEFAULT[2], DEFAULT[3])
                    probe = "W " + " ".join(map(str, limits)) + " " + str(len(row)) + " " + " ".join(token(x) for x in row)
                    expected = "W " + token(encoded_row(row)) if delta == 0 else f"E {kind.title()}Limit 0 1 {len(row)}"
                    cases.append((f"writer-{i}-{kind}-budget-{delta}", probe, expected))
    for _ in range(500):
        records = [rows[rng.randrange(len(rows))] for _ in range(rng.randrange(6))]
        ending = "\r\n" if rng.randrange(2) else "\n"
        wire = b"".join(encoded_row(row, ending) for row in records)
        if wire and rng.randrange(2): wire = wire[:-len(ending)]
        samples.append(wire)
    for i, wire in enumerate(samples):
        expected = rows_response(decoded_rows(wire))
        for chunk in sorted({1, 2, 3, 7, 17, max(1, len(wire))}):
            command = f"P {chunk} 1 " + " ".join(map(str, DEFAULT)) + " " + token(wire)
            cases.append((f"parser-{i}-chunk-{chunk}", command, expected))
    invalid = [
        (b'a"b', DEFAULT, True, "UnexpectedQuote", 1, 1, 1),
        (b'"a"x', DEFAULT, True, "AfterQuote", 3, 1, 1),
        (b"a\rx", DEFAULT, True, "ExpectedLf", 2, 1, 1),
        (b"a\r", DEFAULT, True, "ExpectedLf", 2, 1, 1),
        (b'"abc', DEFAULT, True, "UnclosedQuote", 4, 1, 1),
        (b'a,b\n"x"!', DEFAULT, True, "AfterQuote", 7, 2, 1),
        (b"a\n", DEFAULT, False, "UnexpectedLf", 1, 1, 1),
        (b"ab", (1, *DEFAULT[1:]), True, "FieldLimit", 1, 1, 1),
        (b'"a""b"', (1, *DEFAULT[1:]), True, "FieldLimit", 3, 1, 1),
        (b"a,b\n", (DEFAULT[0], 3, DEFAULT[2], DEFAULT[3]), True, "RowLimit", 3, 1, 2),
        (b"a\nb\n", (DEFAULT[0], DEFAULT[1], 3, DEFAULT[3]), True, "TotalLimit", 3, 2, 1),
        (b"a,b", (*DEFAULT[:3], 1), True, "FieldCountLimit", 1, 1, 2),
    ]
    # Runs must stop before the same first syntax/budget error as scalar reading.
    for n in (15, 16, 17, 31, 32, 33, 63, 64, 65, 255, 256, 257):
        run = b"x" * n
        invalid.extend([
            (run + b'"', DEFAULT, True, "UnexpectedQuote", n, 1, 1),
            (b'"' + run + b'"!', DEFAULT, True, "AfterQuote", n + 2, 1, 1),
            (b'"' + run, DEFAULT, True, "UnclosedQuote", n + 1, 1, 1),
            (run + b"\rx", DEFAULT, True, "ExpectedLf", n + 1, 1, 1),
            (run, (n - 1, *DEFAULT[1:]), True, "FieldLimit", n - 1, 1, 1),
            (b'"' + run + b'"', (n - 1, *DEFAULT[1:]), True, "FieldLimit", n, 1, 1),
            (run, (DEFAULT[0], n - 1, DEFAULT[2], DEFAULT[3]), True, "RowLimit", n - 1, 1, 1),
            (run, (DEFAULT[0], DEFAULT[1], n - 1, DEFAULT[3]), True, "TotalLimit", n - 1, 1, 1),
            (run, (n - 1, n - 1, n - 1, DEFAULT[3]), True, "TotalLimit", n - 1, 1, 1),
            (run, (*DEFAULT[:3], 0), True, "FieldCountLimit", 0, 1, 1),
        ])
    for i, (wire, limits, allow, error, offset, record, field) in enumerate(invalid):
        # Deliberately stricter quote/error expectations than Python recovery.
        prefix = "R 2 61 62;" if i == 5 else "R 1 61;" if i == 10 else ""
        expected = prefix + f"E {error} {offset} {record} {field}"
        for chunk in sorted({1, 2, 3, max(1, len(wire))}):
            command = f"P {chunk} {int(allow)} " + " ".join(map(str, limits)) + " " + token(wire)
            cases.append((f"contract-error-{i}-chunk-{chunk}", command, expected))
    return cases, {"writer_cases": len(rows), "parser_inputs": len(samples), "contract_errors": len(invalid)}

def source_identity():
    files = [ROOT / "csv.goose", *sorted((ROOT / "tests").glob("*.goose")), Path(__file__).resolve()]
    return {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in files}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--goose", type=Path, help="Run oracle.goose through the pinned interpreter")
    group.add_argument("--binary", type=Path, help="Use an already built/instrumented driver")
    parser.add_argument("--debug", action="store_true", help="Debug interpreter with --goose")
    parser.add_argument("--output", type=Path, default=ROOT / ".build/oracle-results.json")
    args = parser.parse_args()
    if args.debug and not args.goose: parser.error("--debug requires --goose")
    cases, counts = corpus()
    before = source_identity()
    program = (args.binary or args.goose).resolve()
    program_hash = hashlib.sha256(program.read_bytes()).hexdigest()
    command = [str(program)] if args.binary else [str(program), "run", "tests/oracle.goose", *(["--debug"] if args.debug else [])]
    payload = "".join(line + "\n" for _, line, _ in cases)
    expected = [value for _, _, value in cases]
    result = subprocess.run(command, input=payload, capture_output=True, text=True, cwd=ROOT, timeout=180)
    if result.returncode or result.stderr:
        raise AssertionError(f"oracle driver exit {result.returncode}: stdout={result.stdout[-1500:]!r} stderr={result.stderr[-3000:]!r}")
    actual = result.stdout.splitlines()
    if actual != expected:
        i = next((i for i, (a, b) in enumerate(zip(actual, expected)) if a != b), min(len(actual), len(expected)))
        label = cases[i][0] if i < len(cases) else "extra-output"
        raise AssertionError(f"{label} at {i}: actual={actual[i:i+1]!r}, expected={expected[i:i+1]!r}; outputs={len(actual)}/{len(expected)}")
    if source_identity() != before or hashlib.sha256(program.read_bytes()).hexdigest() != program_hash:
        raise RuntimeError("Source or executable changed during oracle execution; result rejected")
    record = {"seed": SEED, "cases": len(cases), **counts,
              "corpus_sha256": hashlib.sha256(payload.encode()).hexdigest(),
              "expected_sha256": hashlib.sha256(("\n".join(expected) + "\n").encode()).hexdigest(),
              "stdout_sha256": hashlib.sha256(result.stdout.encode()).hexdigest(),
              "python": sys.version, "python_csv_version": csv.__version__, "platform": platform.platform(),
              "command": command, "executable_sha256": program_hash, "source_sha256": before,
              "source_head": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
              "source_status": subprocess.check_output(["git", "status", "--short"], cwd=ROOT, text=True),
              "notes": ["Latin-1 is a reversible byte/str bridge, not encoding validation",
                        "Malformed expectations follow the explicit contract; Python csv is more permissive for some forms",
                        "Finite seeded differential corpus, not coverage-guided fuzzing or certification"]}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(record, indent=2) + "\n")
    print(f"csv Python oracle: {len(cases)} differential/contract cases passed; corpus {record['corpus_sha256']}")

if __name__ == "__main__":
    main()

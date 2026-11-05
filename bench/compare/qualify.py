#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Compare every emitted byte/field, EOF status and summary before permitting timing."""
from __future__ import annotations
import argparse
import datetime
import json
from pathlib import Path
import subprocess
from fixtures import MOD, bundle, canonical, feature_cases, identity, signature, summary, wire_signature, workloads
from build import artifact, inputs, sha256

ROOT = Path(__file__).resolve().parents[2]
ENGINES = ("goose", "rust-csv", "csv-core", "simd-csv", "libcsv")


def binaries(folder):
    return {engine: folder / ("rust" if engine in ("rust-csv", "csv-core", "simd-csv") else engine)
            for engine in ENGINES}


def execute(binary, engine, operation, path, chunk, repeats=1, dump=True):
    command = [str(binary), engine, operation, str(path), str(chunk), str(repeats), str(int(dump))]
    proc = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=120)
    if proc.returncode or proc.stderr:
        raise RuntimeError(f"adapter failed {command}: exit={proc.returncode} {proc.stderr[-2000:]}")
    lines = proc.stdout.splitlines()
    if not lines or not lines[-1].startswith("S "):
        raise ValueError(f"missing summary: {command}: {proc.stdout[-2000:]}")
    parts = lines.pop().split()
    if len(parts) != 6 or parts[5] not in ("ok", "error"):
        raise ValueError(f"invalid summary: {parts}")
    records, size, checksum, elapsed = map(int, parts[1:5])
    if min(records, size, checksum, elapsed) < 0:
        raise ValueError("negative adapter summary")
    output, errors = [], []
    for line in lines:
        fields = line.split()
        if fields[0] == "E":
            errors.append(line)
        elif operation == "parse" and fields[0] == "R":
            row = [b"" if value == "-" else bytes.fromhex(value) for value in fields[2:]]
            if len(row) != int(fields[1]):
                raise ValueError("bad field count")
            output.append(row)
        elif operation == "write" and fields[0] == "W" and len(fields) == 2:
            output.append(b"" if fields[1] == "-" else bytes.fromhex(fields[1]))
        else:
            raise ValueError(f"unexpected output {line[:200]}")
    if bool(errors) != (parts[5] == "error") and dump:
        raise ValueError("error status and diagnostics disagree")
    if dump:
        expected_sum = sum((signature(item) if operation == "parse" else wire_signature(item)) for item in output) % MOD
        if records != len(output) or checksum != expected_sum:
            raise ValueError("emitted output and summary disagree")
        if operation == "write" and size != sum(map(len, output)):
            raise ValueError("emitted wire byte count disagrees")
    return {"counts": [records, size, checksum], "elapsed_ns": elapsed, "ok": parts[5] == "ok",
            "output": output, "errors": errors}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build-record", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=ROOT / ".build/comparison/qualification.json")
    args = parser.parse_args()
    receipt_bytes = args.build_record.read_bytes()
    receipt = json.loads(receipt_bytes)
    frozen = receipt["inputs"]
    goose_tool, cc_tool = (Path(frozen["tools"][name]["path"]) for name in ("goose", "cc"))
    if inputs(goose_tool, cc_tool) != frozen:
        raise RuntimeError("qualification source/tools differ from build receipt")
    expected_binaries = {"goose": receipt["goose"]["binary"], **receipt["alternatives"]["binaries"]}
    commands = {engine: Path(expected_binaries["rust" if engine in ("rust-csv", "csv-core", "simd-csv") else engine]["path"])
                for engine in ENGINES}
    for name, expected in expected_binaries.items():
        if artifact(Path(expected["path"])) != expected:
            raise RuntimeError(f"qualification executable differs from build receipt: {name}")
    folder = ROOT / ".build/comparison-fixtures"
    folder.mkdir(parents=True, exist_ok=True)
    records = []
    for name, rows in workloads().items():
        wire = canonical(rows)
        for operation, data in (("parse", wire), ("write", bundle(rows))):
            path = folder / f"{name}.{operation}"
            path.write_bytes(data)
            chunks = (1, 64, 4096, 65536) if name == "simple" and operation == "parse" else (4096,)
            for chunk in chunks:
                expected_output = rows if operation == "parse" else [canonical([row]) for row in rows]
                for engine, binary in commands.items():
                    # Repetition checks persistent state; all shared wire fixtures are terminated.
                    result = execute(binary, engine, operation, path, chunk, repeats=2)
                    same = (result["ok"] and result["output"] == expected_output * 2
                            and result["counts"] == list(summary(rows, operation, 2)))
                    if not same:
                        raise ValueError(f"shared workload parity failed: {name}/{operation}/{chunk}/{engine}: "
                                         f"counts={result['counts']} errors={result['errors']}")
                    records.append({"tier": "shared-valid", "fixture": name, "operation": operation,
                                    "engine": engine, "chunk": chunk, "repeats": 2,
                                    "input": identity(data), "counts": result["counts"], "equal": True})
    for name, (wire, rows, error) in feature_cases().items():
        path = folder / f"feature-{name}.parse"
        path.write_bytes(wire)
        for chunk in (1, 3, 4096):
            for engine, binary in commands.items():
                result = execute(binary, engine, "parse", path, chunk)
                read_all = result["counts"][1] == len(wire)
                same = (result["output"] == rows and result["ok"] == (error is None)
                        and (not result["ok"] or read_all))
                if engine == "goose" and (not same or error is not None and not result["errors"][0].startswith(f"E {error} ")):
                    raise ValueError(f"Goose feature expectation failed: {name}/{chunk}: {result}")
                records.append({"tier": "feature", "fixture": name, "operation": "parse", "engine": engine,
                                "chunk": chunk, "input": identity(wire), "equal_rows_acceptance_and_eof": same, "read_all_input": read_all,
                                "ok": result["ok"], "counts": result["counts"], "errors": result["errors"],
                                "decoded_rows_sha256": identity(bundle(result["output"]))["sha256"],
                                "expected_rows_sha256": identity(bundle(rows))["sha256"], "expected_error": error})
    for name, rows in {"zero-fields": [[]], "one-empty": [[b""]], "trailing-empty": [[b"a", b""]]}.items():
        path = folder / f"feature-{name}.write"
        path.write_bytes(bundle(rows))
        for engine, binary in commands.items():
            result = execute(binary, engine, "write", path, 4096)
            same = result["ok"] and result["output"] == [canonical([row]) for row in rows]
            if engine == "goose" and not same:
                raise ValueError(f"Goose writer feature expectation failed: {name}")
            records.append({"tier": "feature", "fixture": name, "operation": "write", "engine": engine,
                            "equal_wire": same, "output_hex": [b.hex() for b in result["output"]]})
    if args.build_record.read_bytes() != receipt_bytes or inputs(goose_tool, cc_tool) != frozen:
        raise RuntimeError("qualification source/tools/receipt changed")
    for name, expected in expected_binaries.items():
        if artifact(Path(expected["path"])) != expected:
            raise RuntimeError(f"qualification executable changed: {name}")
    result = {"build_record_sha256": identity(receipt_bytes)["sha256"], "binaries": expected_binaries,
              "recorded_at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
              "notes": ["Full output/EOF qualification; dump-mode elapsed times are NOT benchmark samples",
                        "Feature gaps remain recorded; equality does not establish budget/error/lifecycle equivalence"],
              "records": records}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(f"qualification: {len(records)} records; shared workload outputs match all five drivers")


if __name__ == "__main__":
    main()

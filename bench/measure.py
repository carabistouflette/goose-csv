#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Record a bounded public-CSV baseline with frozen inputs and raw ordered samples."""
from __future__ import annotations
import argparse
import csv
import datetime
import hashlib
import io
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
MODULUS = 2147483647
sys.path.insert(0, str(ROOT / "scripts"))
from provenance import inputs, sha256


def run(command, *, timeout=600):
    result = subprocess.run(command, cwd=ROOT, text=True, capture_output=True, timeout=timeout, check=True)
    if result.stderr:
        print(result.stderr, file=sys.stderr, end="")
    return result.stdout


def mix(value, part):
    return (value * 257 + part + 1) % MODULUS


def row_signature(fields):
    value = len(fields)
    for field in fields:
        value = mix(value, len(field))
        if field:
            for byte in (field[0], field[len(field) // 2], field[-1]):
                value = mix(value, byte)
    return value


def wire_signature(wire):
    value = len(wire)
    for byte in (wire[0], wire[len(wire) // 2], wire[-1]):
        value = mix(value, byte)
    return value


def fixture_rows():
    return {
        "simple": [b"alpha", b"beta", b"gamma", b"delta", b"epsilon", b"zeta", b"eta", b"theta"],
        "quoted": [b"alpha,beta", b'say "hello"', b"line1\r\nline2", b"tail"],
        "empty256": [b""] * 256,
        "utf8": ["café".encode(), "東京".encode(), "🙂".encode(), b""],
        "binary": [bytes(range(256)), b"x\0y"],
        "long256k": [b"x" * 262144],
    }


def manifest(text):
    expected = fixture_rows()
    found = {}
    for line in text.splitlines():
        marker, name, wire_bytes, block_rows, count, row_sig, wire_sig, encoded = line.split()
        if marker != "M" or name not in expected or name in found:
            raise ValueError("unexpected or duplicate fixture manifest")
        wire = bytes.fromhex(encoded)
        fields = expected[name]
        buffer = io.StringIO(newline="")
        csv.writer(buffer, lineterminator="\r\n").writerow([field.decode("latin1") for field in fields])
        if wire != buffer.getvalue().encode("latin1"):
            raise ValueError(f"fixture {name} differs from independent Python csv encoding")
        expected_values = (len(wire), max(1, 65536 // len(wire)), len(fields), row_signature(fields), wire_signature(wire))
        if tuple(map(int, (wire_bytes, block_rows, count, row_sig, wire_sig))) != expected_values:
            raise ValueError(f"fixture {name} metadata/checksum mismatch")
        found[name] = {"wire_bytes": len(wire), "wire_sha256": hashlib.sha256(wire).hexdigest(),
                       "rows_per_block": expected_values[1], "block_bytes": len(wire) * expected_values[1],
                       "decoded_field_bytes": [len(field) for field in fields],
                       "field_sha256": [hashlib.sha256(field).hexdigest() for field in fields],
                       "row_signature": expected_values[3], "wire_signature": expected_values[4]}
    if list(found) != list(expected):
        raise ValueError("incomplete or reordered fixture manifest")
    return found


def parse_sample(text, fixtures, iterations):
    expected = []
    for name in fixtures:
        if name == "simple":
            expected.extend(("parse", name, chunk) for chunk in (1, 64, 65536))
        expected.extend((("parse", name, 4096), ("write", name, 0)))
    rows = []
    for ordinal, line in enumerate(text.splitlines()):
        marker, mode, name, chunk, count, size, records, elapsed, checksum = line.split()
        chunk, count, size, records, elapsed, checksum = map(int, (chunk, count, size, records, elapsed, checksum))
        if marker != "S" or ordinal >= len(expected) or (mode, name, chunk) != expected[ordinal]:
            raise ValueError(f"unexpected benchmark case: {line}")
        fixture = fixtures[name]
        expected_records = fixture["rows_per_block"] * iterations
        signature = fixture["row_signature"] if mode == "parse" else fixture["wire_signature"]
        if (count != iterations or records != expected_records or size != fixture["wire_bytes"] * records
                or checksum != signature * records or elapsed <= 0):
            raise ValueError(f"benchmark accounting/checksum mismatch: {line}")
        rows.append({"ordinal": ordinal, "operation": mode, "fixture": name, "chunk_bytes": chunk,
                     "iterations": count, "wire_bytes": size, "records": records,
                     "elapsed_ns": elapsed, "checksum": checksum})
    if len(rows) != len(expected):
        raise ValueError("missing benchmark cases")
    return rows


def host():
    cpuinfo = Path("/proc/cpuinfo")
    model = next((line.split(":", 1)[1].strip() for line in cpuinfo.read_text().splitlines()
                  if line.startswith("model name")), None) if cpuinfo.exists() else platform.processor()
    return {"platform": platform.platform(), "machine": platform.machine(), "cpu_model": model,
            "libc": platform.libc_ver(), "parent_affinity": sorted(os.sched_getaffinity(0)),
            "logical_cpus": os.cpu_count(), "load_average": os.getloadavg()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--goose", type=Path, required=True)
    parser.add_argument("--cc", default="gcc")
    parser.add_argument("--iterations", type=int, default=16, help="bounded input-block repetitions per case")
    parser.add_argument("--samples", type=int, default=5)
    parser.add_argument("--cpu", type=int, help="optional Linux CPU affinity for benchmark child only")
    parser.add_argument("--output", type=Path, default=ROOT / ".build/csv-bench.json")
    args = parser.parse_args()
    if not 1 <= args.iterations <= 1000 or not 1 <= args.samples <= 100:
        parser.error("iterations must be 1..1000 and samples 1..100")
    if args.cpu is not None and args.cpu not in os.sched_getaffinity(0):
        parser.error("requested CPU is outside current allowed affinity")
    found = shutil.which(args.cc)
    if found is None:
        parser.error("C compiler not found")
    goose, compiler = args.goose.resolve(strict=True), Path(found).resolve(strict=True)
    frozen = inputs(goose, compiler)
    if frozen["source"]["status"]:
        raise RuntimeError("Commit the benchmark inputs before recording attributed samples")
    advertised = re.search(r"\bgoose ([0-9a-f]{7,40})\b", frozen["tools"]["goose"]["version"])
    if advertised is None or not frozen["goose_revision"].startswith(advertised.group(1)):
        raise RuntimeError("Goose binary does not advertise the pinned source revision")
    build = ROOT / ".build/csv-bench"
    build.mkdir(parents=True, exist_ok=True)
    invocation = Path(tempfile.mkdtemp(prefix="run-", dir=build))
    wrapper, transcript, binary = invocation / "cc", invocation / "compiler-commands.jsonl", invocation / "benchmark"
    wrapper.write_text("#!/usr/bin/env python3\nimport json,os,sys\n"
                       f"compiler={str(compiler)!r}\nlog={str(transcript)!r}\n"
                       "args=sys.argv[1:]\n"
                       "probe=any(a in args for a in ('-v','--version','-dumpversion','-dumpmachine'))\n"
                       "effective=[compiler,*args,*([] if probe else ['-O2','-UNDEBUG'])]\n"
                       "with open(log,'a') as f:f.write(json.dumps(effective)+'\\n')\n"
                       "os.execv(compiler,effective)\n")
    wrapper.chmod(0o755)
    build_command = [str(goose), "build", "bench/bench.goose", "--standalone", "--cc", str(wrapper), "-O2", "-o", str(binary)]
    build_stdout = run(build_command)
    binary_sha = sha256(binary)
    prefix = [] if args.cpu is None else ["taskset", "-c", str(args.cpu)]
    command = [*prefix, str(binary)]
    fixtures = manifest(run([*command, "--manifest"]))
    warm_stdout = run([*command, "1"])
    warmup = {"iterations": 1, "stdout": warm_stdout, "results": parse_sample(warm_stdout, fixtures, 1)}
    before_host = host()
    samples = []
    for sample in range(args.samples):
        start = time.perf_counter_ns()
        stdout = run([*command, str(args.iterations)])
        wall_ns = time.perf_counter_ns() - start
        samples.append({"sample": sample, "process_wall_ns": wall_ns, "stdout": stdout,
                        "results": parse_sample(stdout, fixtures, args.iterations)})
    if inputs(goose, compiler) != frozen:
        raise RuntimeError("Source/tool inputs changed during benchmark; all observations rejected")
    if sha256(binary) != binary_sha:
        raise RuntimeError("Benchmark binary changed during execution; observations rejected")
    commands = [json.loads(line) for line in transcript.read_text().splitlines()]
    program_links = [entry for entry in commands if "-o" in entry and entry.index("-o") + 1 < len(entry)
                     and entry[entry.index("-o") + 1] == str(binary)]
    if not program_links or any(entry[-2:] != ["-O2", "-UNDEBUG"] for entry in program_links):
        raise RuntimeError("Actual program compiler transcript lacks trailing -O2 -UNDEBUG")
    result = {"recorded_at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
              "inputs": frozen, "host_before": before_host, "host_after": host(),
              "benchmark_affinity": sorted(os.sched_getaffinity(0)) if args.cpu is None else [args.cpu],
              "build_command": build_command, "build_stdout": build_stdout,
              "compiler_commands": commands, "compiler_commands_sha256": sha256(transcript),
              "binary_sha256": binary_sha, "fixtures": fixtures, "warmup": warmup, "samples": samples,
              "notes": ["Single pure-Goose baseline; no comparator or universal performance ranking",
                        "Shared host, optional best-effort CPU affinity, no exclusive core/isolation claim",
                        "Native monotonic case timings include codec calls, assertions and sampled data checksums; setup is outside case timing",
                        "Process wall time additionally includes fixture generation, validation, startup and reporting",
                        "Fixed roughly 64 KiB batches repeat; long fixture has one 256 KiB row, never a whole 64 MiB input buffer",
                        "Row/encoded-byte counts derive from consumed/emitted data; sampled signatures resist elision but are not cryptographic hashes",
                        "Full fixture bytes match independent Python csv encoding; parsed fields/final encoded output are checked outside case timing",
                        "All samples and fixed within-process case order retained; no timing thresholds, outlier removal or backend instrumented claims"]}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(f"csv benchmark: {len(fixtures)} fixtures, {len(samples)} samples, {len(samples[0]['results'])} cases/sample")
    print(f"csv benchmark results: {args.output}")


if __name__ == "__main__":
    main()

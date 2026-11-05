#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Canonical-path A/A controls and paired CSV comparison with complete accounting."""
from __future__ import annotations
import argparse
import datetime
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import shutil
import statistics
import sys
from build import FLAGS, ROOT, artifact, build_goose, inputs, sha256
from fixtures import bundle, canonical, identity, summary, workloads
from qualify import binaries, execute

BASELINE = "4ec59cf17685f85e537cac264527d28af8ab9f2f"


def harness_identity():
    return {str(p.relative_to(ROOT)): sha256(p) for p in sorted((ROOT / "bench/compare").rglob("*"))
            if p.is_file() and "__pycache__" not in p.parts and "target" not in p.parts}


def quantiles(values):
    return {"min": min(values), "median": statistics.median(values), "max": max(values),
            "p10": sorted(values)[math.floor((len(values) - 1) * .1)],
            "p90": sorted(values)[math.ceil((len(values) - 1) * .9)]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--goose", type=Path, required=True)
    parser.add_argument("--cc", default="gcc")
    parser.add_argument("--phase", choices=("control", "compare"), required=True)
    parser.add_argument("--controls", type=Path)
    parser.add_argument("--build-record", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--samples", type=int, default=7)
    parser.add_argument("--target-ms", type=int, default=100)
    parser.add_argument("--cpu", type=int, default=4)
    args = parser.parse_args()
    if not 3 <= args.samples <= 100 or not 20 <= args.target_ms <= 1000:
        parser.error("samples must be 3..100 and target-ms 20..1000")
    if args.cpu not in os.sched_getaffinity(0):
        parser.error("requested CPU unavailable")
    goose, cc = args.goose.resolve(strict=True), Path(shutil.which(args.cc)).resolve(strict=True)
    frozen = inputs(goose, cc)
    if frozen["source"]["status"]:
        raise RuntimeError("commit all source before recording attributed measurements")
    build_receipt_bytes = args.build_record.read_bytes()
    build_record = json.loads(build_receipt_bytes)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    journal_path = args.output.with_suffix(args.output.suffix + ".jsonl")
    if args.output.exists() or journal_path.exists():
        raise RuntimeError("retain old runs: choose a fresh output/journal path")
    if build_record["inputs"] != frozen:
        raise RuntimeError("build record does not match frozen current source/tools")
    for name, expected in build_record["alternatives"]["binaries"].items():
        if artifact(Path(expected["path"])) != expected:
            raise RuntimeError(f"alternative executable does not match build record: {name}")
    folder = ROOT / ".build/comparison"
    archives = folder / "archives"
    archives.mkdir(exist_ok=True)
    harness = harness_identity()
    control_bytes = None
    if args.phase == "compare":
        if args.controls is None:
            parser.error("--controls is required for comparison")
        control_bytes = args.controls.read_bytes()
        control = json.loads(control_bytes)
        if control["phase"] != "control" or not control["identical_builds"] or control["harness"] != harness:
            raise RuntimeError("matching canonical-path identical-code controls required")
        if control["inputs"]["tools"] != frozen["tools"] or control["flags"] != FLAGS:
            raise RuntimeError("control tools/flags differ")
    builds, variants = {}, {}
    for label, revision in (("A", BASELINE), ("B", BASELINE if args.phase == "control" else "WORKTREE")):
        builds[label] = build_goose(goose, cc, revision, folder)
        variants[label] = archives / label
        shutil.copyfile(folder / "goose", variants[label])
        variants[label].chmod(0o755)
    identical = all(builds["A"][key] == builds["B"][key] for key in ("csv_sha256", "source_snapshot", "generated_c_sha256"))
    identical = identical and builds["A"]["binary"]["sha256"] == builds["B"]["binary"]["sha256"]
    if args.phase == "control" and not identical:
        raise RuntimeError("identical-code canonical-path builds differ; investigate before timing")
    tools = binaries(folder)
    if args.phase == "control":
        engines = ("A", "B")
    else:
        engines = ("A", "B", "rust-csv", "csv-core", "simd-csv", "libcsv")
    # Validate complete output for both CSV source versions using the same adapters.
    fixture_dir = ROOT / ".build/comparison-fixtures"
    fixture_dir.mkdir(exist_ok=True)
    fixtures = workloads()
    cases = []
    for name, rows in fixtures.items():
        for operation, data in (("parse", canonical(rows)), ("write", bundle(rows))):
            path = fixture_dir / f"{name}.{operation}"
            path.write_bytes(data)
            chunks = (1, 64, 4096, 65536) if name == "simple" and operation == "parse" else (4096,)
            for chunk in chunks:
                cases.append((name, operation, chunk, path, rows))
                expected_output = rows if operation == "parse" else [canonical([row]) for row in rows]
                for engine in engines:
                    if engine in variants:
                        shutil.copyfile(variants[engine], folder / "goose")
                        binary, native = folder / "goose", "goose"
                    else:
                        binary, native = tools[engine], engine
                    checked = execute(binary, native, operation, path, chunk, 2)
                    if not checked["ok"] or checked["output"] != expected_output * 2 or checked["counts"] != list(summary(rows, operation, 2)):
                        raise RuntimeError(f"full output qualification failed: {name}/{operation}/{chunk}/{engine}")
    frozen_fixtures = {str(case[3]): sha256(case[3]) for case in cases}
    frozen_binaries = {name: artifact(path) for name, path in {**variants, **{e: tools[e] for e in engines if e not in variants}}.items()}
    os.sched_setaffinity(0, {args.cpu})
    calibration, samples = [], []
    repeats = {}
    expected_cache = {}
    def sample(case, engine, count):
        name, operation, chunk, path, rows = case
        if engine in variants:
            shutil.copyfile(variants[engine], folder / "goose")
            binary, native = folder / "goose", "goose"
        else:
            binary, native = tools[engine], engine
        result = execute(binary, native, operation, path, chunk, count, dump=False)
        key = (name, operation, count)
        if key not in expected_cache:
            expected_cache[key] = list(summary(rows, operation, count))
        if not result["ok"] or result["counts"] != expected_cache[key] or result["output"] or result["elapsed_ns"] <= 0:
            raise RuntimeError(f"timed accounting/EOF failed: {name}/{operation}/{chunk}/{engine}")
        return {"fixture": name, "operation": operation, "chunk": chunk, "engine": engine,
                "repeats": count, "counts": result["counts"], "elapsed_ns": result["elapsed_ns"]}
    with journal_path.open("x") as journal:
        journal.write(json.dumps({"kind": "start", "phase": args.phase, "inputs": frozen,
                                  "build_record_sha256": hashlib.sha256(build_receipt_bytes).hexdigest(),
                                  "fixtures": frozen_fixtures, "binaries": frozen_binaries}) + "\n")
        journal.flush()
        try:
            # Per-engine calibration keeps time comparable without making the fastest engine a short sample.
            for case in cases:
                for engine in engines:
                    count = 1
                    while True:
                        observed = sample(case, engine, count)
                        calibration.append(observed)
                        journal.write(json.dumps({"kind": "calibration", **observed}) + "\n"); journal.flush()
                        if observed["elapsed_ns"] >= args.target_ms * 1000000 or count == 1000000:
                            break
                        count = min(1000000, max(count + 1, math.ceil(count * args.target_ms * 1000000 / max(observed["elapsed_ns"], 1000))))
                    repeats[(case[0], case[1], case[2], engine)] = count
            # Alternating engine order and fixture order; every raw sample is retained.
            for iteration in range(args.samples):
                ordered_cases = cases if iteration % 2 == 0 else list(reversed(cases))
                for case in ordered_cases:
                    order = engines if iteration % 2 == 0 else tuple(reversed(engines))
                    for engine in order:
                        row = sample(case, engine, repeats[(case[0], case[1], case[2], engine)])
                        row.update(sample=iteration, ordinal=len(samples))
                        samples.append(row)
                        journal.write(json.dumps({"kind": "sample", **row}) + "\n"); journal.flush()
            if inputs(goose, cc) != frozen or harness_identity() != harness:
                raise RuntimeError("source/tools changed during recording")
            for name, expected in frozen_binaries.items():
                path = variants[name] if name in variants else tools[name]
                if artifact(path) != expected:
                    raise RuntimeError(f"binary changed during recording: {name}")
            if args.build_record.read_bytes() != build_receipt_bytes or control_bytes is not None and args.controls.read_bytes() != control_bytes:
                raise RuntimeError("build/control receipt changed during recording")
            if any(sha256(path) != digest for path, digest in frozen_fixtures.items()):
                raise RuntimeError("fixture file changed during recording")
        except BaseException as error:
            journal.write(json.dumps({"kind": "rejected-or-incomplete", "reason": repr(error)}) + "\n")
            journal.flush()
            raise
        journal.write(json.dumps({"kind": "complete", "samples": len(samples)}) + "\n")
    groups = {}
    for row in samples:
        key = (row["fixture"], row["operation"], row["chunk"], row["engine"])
        groups.setdefault(key, []).append(row["elapsed_ns"] / row["counts"][1])
    result = {"recorded_at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
              "phase": args.phase, "inputs": frozen, "harness": harness, "flags": FLAGS,
              "controls_sha256": hashlib.sha256(control_bytes).hexdigest() if control_bytes else None,
              "build_record_sha256": hashlib.sha256(build_receipt_bytes).hexdigest(), "builds": builds,
              "journal_sha256": sha256(journal_path),
              "identical_builds": identical, "binaries": frozen_binaries,
              "host": {"platform": platform.platform(), "cpuinfo": Path("/proc/cpuinfo").read_text(),
                       "affinity": sorted(os.sched_getaffinity(0)), "load_average": os.getloadavg(),
                       "notes": "Shared host; affinity is not isolation. No host settings changed."},
              "fixtures": {name: {"wire": identity(canonical(rows)), "bundle": identity(bundle(rows))} for name, rows in fixtures.items()},
              "calibration": calibration, "samples": samples,
              "summaries": [dict(fixture=k[0], operation=k[1], chunk=k[2], engine=k[3], ns_per_byte=quantiles(v)) for k, v in groups.items()],
              "notes": ["File I/O/dataset setup/initialization excluded; row materialization and complete per-row writer flush included",
                        "Elapsed time is in-process native monotonic time; process startup excluded",
                        "Calibrations are retained separately; full byte/field validation precedes all timed cases",
                        "Native valid-data tier does not equal the complete Goose strictness/budget/error/atomicity contract"]}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("x") as output:
        output.write(json.dumps(result, indent=2) + "\n")
    print(f"{args.phase}: {len(samples)} retained samples; identical builds={identical}; {args.output}")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Pinned benchmark-only dependency acquisition and canonical-path native builds."""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tomllib
import tarfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
from provenance import inputs, sha256, tool
LIBCSV = "b1d5212831842ee5869d99bc208a21837e4037d5"
ARCHIVES = {"csv-1.4.0": "52cd9d68cf7efc6ddfaaee42e7288d3a99d613d4b50f76ce9827ae0c6e14f938",
            "csv-core-0.1.13": "704a3c26996a80471189265814dbc2c257598b96b8a7feae2d31ace646bb9782",
            "simd-csv-0.14.0": "131b52919dd05c58d395a06cd09bfb55d25a06ca3c1acec7ec2a22696bff4cdb"}
FLAGS = ["-O3", "-g", "-march=native", "-fno-omit-frame-pointer", "-flto", "-UNDEBUG"]


def run(command, **kwargs):
    result = subprocess.run(list(map(str, command)), cwd=ROOT, capture_output=True, text=True, timeout=600, **kwargs)
    if result.returncode:
        raise RuntimeError(f"{command}: {result.stdout[-2000:]} {result.stderr[-4000:]}")
    return result.stdout


def sections(binary):
    result = {}
    for section in (".text", ".rodata", ".data", ".eh_frame"):
        # stdout contains only the requested section, not objcopy diagnostics.
        data = subprocess.check_output(["objcopy", "--dump-section", f"{section}=/dev/stdout", str(binary), "/dev/null"])
        result[section] = hashlib.sha256(data).hexdigest()
    return result


def artifact(binary):
    return {"path": str(binary), "sha256": sha256(binary), "sections": sections(binary)}


def build_goose(goose, compiler, revision, folder):
    # Baseline and candidates use this SAME source/generated-C/output path.
    # Only our ignored build snapshot changes; no release checkout/index is touched.
    source = folder / "source"
    (source / "bench/compare").mkdir(parents=True, exist_ok=True)
    (source / "tests").mkdir(exist_ok=True)
    csv_bytes = ((ROOT / "csv.goose").read_bytes() if revision == "WORKTREE" else
                 subprocess.check_output(["git", "show", f"{revision}:csv.goose"], cwd=ROOT))
    (source / "csv.goose").write_bytes(csv_bytes)
    shutil.copyfile(ROOT / "bench/compare/driver.goose", source / "bench/compare/driver.goose")
    shutil.copyfile(ROOT / "tests/support.goose", source / "tests/support.goose")
    wrapper, transcript = folder / "cc", folder / "compiler-commands.jsonl"
    generated = folder / "generated.c"
    transcript.write_text("")
    wrapper.write_text('#!/usr/bin/env python3\nimport hashlib,json,os,pathlib,shutil,sys\n'
                      f'compiler={str(compiler)!r}\nlog={str(transcript)!r}\nflags={FLAGS!r}\ncanonical={str(generated)!r}\n'
                      'args=sys.argv[1:]\n'
                      "probe=any(a in args for a in ('-v','--version','-dumpversion','-dumpmachine'))\n"
                      'sources=[]\n'
                      'for i,arg in enumerate(args):\n'
                      ' if arg.endswith(".c") and pathlib.Path(arg).is_file():\n'
                      '  sources.append({"original":arg,"sha256":hashlib.sha256(pathlib.Path(arg).read_bytes()).hexdigest()})\n'
                      '  assert len(sources)==1,"unexpected multiple C sources"\n'
                      '  shutil.copyfile(arg,canonical);args[i]=canonical\n'
                      'effective=[compiler,*args,*([] if probe else flags)]\n'
                      'with open(log,"a") as f:f.write(json.dumps({"argv":effective,"sources":sources})+"\\n")\n'
                      'os.execv(compiler,effective)\n')
    wrapper.chmod(0o755)
    output = folder / "goose"
    run([goose, "build", source / "bench/compare/driver.goose", "--standalone", "--cc", wrapper, "-o", output])
    commands = [json.loads(line) for line in transcript.read_text().splitlines()]
    links = [row for row in commands if "-o" in row["argv"] and str(output) in row["argv"]]
    if len(links) != 1 or links[0]["argv"][-len(FLAGS):] != FLAGS or not links[0]["sources"]:
        raise RuntimeError("canonical generated-C compiler attribution failed")
    return {"csv_revision": revision, "csv_sha256": hashlib.sha256(csv_bytes).hexdigest(),
            "source_snapshot": {str(p.relative_to(source)): sha256(p) for p in source.rglob("*.goose")},
            "generated_c_sha256": sha256(generated), "compiler_commands": commands,
            "binary": artifact(output)}


def alternatives(compiler, folder):
    dep = ROOT / ".build/comparison-deps/libcsv"
    if not dep.exists():
        dep.parent.mkdir(parents=True, exist_ok=True)
        run(["git", "clone", "--no-checkout", "https://github.com/rgamble/libcsv.git", dep])
        run(["git", "-C", dep, "checkout", "--detach", LIBCSV])
    if run(["git", "-C", dep, "rev-parse", "HEAD"]).strip() != LIBCSV or run(["git", "-C", dep, "status", "--porcelain"]):
        raise RuntimeError("libcsv dependency changed")
    hashes = {str(p.relative_to(dep)): sha256(p) for p in dep.rglob("*") if p.is_file() and ".git" not in p.relative_to(dep).parts}
    command = [str(compiler), "-std=c11", *FLAGS, "-Wall", "-Wextra", "-Werror", "-I", str(dep),
               str(ROOT / "bench/compare/libcsv_driver.c"), str(dep / "libcsv.c"), "-o", str(folder / "libcsv")]
    run(command)
    actual_tools = {name: Path(run(["rustup", "which", name]).strip()).resolve(strict=True) for name in ("cargo", "rustc")}
    manifest = ROOT / "bench/compare/rust/Cargo.toml"
    target = ROOT / ".build/comparison-rust-target"
    env = {k: v for k, v in os.environ.items() if not k.startswith(("CARGO_", "RUST", "SCCACHE_"))}
    for name in ("CARGO_HOME", "RUSTUP_HOME"):
        if name in os.environ:
            env[name] = os.environ[name]
    env.update(CARGO_TARGET_DIR=str(target), RUSTFLAGS=f"-C target-cpu=native -C force-frame-pointers=yes -C linker={compiler}",
               RUSTC=str(actual_tools["rustc"]), RUSTC_WRAPPER="", RUSTC_WORKSPACE_WRAPPER="", CARGO_INCREMENTAL="0")
    cargo = [str(actual_tools["cargo"])]
    config = ["build.rustc-wrapper=\"\"", "build.incremental=false", "profile.release.opt-level=3",
              "profile.release.codegen-units=1", "profile.release.lto=\"thin\"", "profile.release.overflow-checks=true",
              "profile.release.debug=false", "profile.release.strip=\"none\"", "profile.release.panic=\"unwind\"",
              "profile.release.debug-assertions=false", "profile.release.incremental=false"]
    for setting in config:
        cargo.extend(["--config", setting])
    run([*cargo, "fetch", "--locked", "--manifest-path", manifest], env=env)
    metadata = json.loads(run([*cargo, "metadata", "--locked", "--format-version", "1", "--manifest-path", manifest], env=env))
    packages = []
    lock = tomllib.loads((manifest.parent / "Cargo.lock").read_text())
    lock_packages = {(p["name"], p["version"]): p for p in lock["package"]}
    cargo_home = Path(os.environ.get("CARGO_HOME", str(Path.home() / ".cargo")))
    for package in metadata["packages"]:
        if package["source"] is None:
            continue
        key = f'{package["name"]}-{package["version"]}'
        source = Path(package["manifest_path"]).parent
        archives = [cargo_home / "registry/cache" / source.parent.name / f"{key}.crate"]
        expected = lock_packages[(package["name"], package["version"])]["checksum"]
        if len(archives) != 1 or sha256(archives[0]) != expected or key in ARCHIVES and expected != ARCHIVES[key]:
            raise RuntimeError(f"registry archive identity mismatch: {key}")
        # Verify the extracted source against every regular file in the pinned archive.
        files = {}
        with tarfile.open(archives[0], "r:gz") as archive:
            for member in archive.getmembers():
                if member.isdir():
                    continue
                relative = Path(member.name).relative_to(key)
                if not member.isfile() or relative.is_absolute() or ".." in relative.parts:
                    raise RuntimeError(f"unexpected crate archive entry: {member.name}")
                digest = hashlib.sha256(archive.extractfile(member).read()).hexdigest()
                if sha256(source / relative) != digest:
                    raise RuntimeError(f"registry source changed: {key}/{relative}")
                files[str(relative)] = digest
        packages.append({"name": package["name"], "version": package["version"], "license": package["license"],
                         "archive_sha256": expected, "files": files})
    # A private target clean forces real compiler invocations into the retained log.
    run([*cargo, "clean", "--manifest-path", manifest], env=env)
    rust_command = [*cargo, "build", "--release", "--locked", "--verbose", "--verbose", "--manifest-path", str(manifest)]
    compiled = subprocess.run(rust_command, cwd=ROOT, env=env, capture_output=True, text=True, timeout=600)
    if compiled.returncode:
        raise RuntimeError(f"Rust compilation failed: {compiled.stderr[-4000:]}")
    if str(actual_tools["rustc"]) not in compiled.stderr or "-C codegen-units=1" not in compiled.stderr:
        raise RuntimeError("effective Rust compiler invocation/profile was not captured")
    configs = {}
    for parent in [*ROOT.parents, ROOT]:
        for name in ("config", "config.toml"):
            path = parent / ".cargo" / name
            if path.is_file():
                configs[str(path)] = sha256(path)
    for name in ("config", "config.toml"):
        path = cargo_home / name
        if path.is_file():
            configs[str(path)] = sha256(path)
    shutil.copyfile(target / "release/goose-csv-compare", folder / "rust")
    (folder / "rust").chmod(0o755)
    return {"libcsv": {"revision": LIBCSV, "files": hashes, "compiler_command": command,
                       "license": "LGPL-2.1-or-later; benchmark-only, no library source/binary vendored"},
            "rust": {"tools": {name: tool(path) for name, path in actual_tools.items()},
                     "cargo_config_overrides": config, "loaded_config_files": configs,
                     "command": rust_command, "stdout": compiled.stdout, "stderr": compiled.stderr,
                     "flags": env["RUSTFLAGS"], "manifest_sha256": sha256(manifest),
                     "lock_sha256": sha256(manifest.parent / "Cargo.lock"), "packages": packages},
            "binaries": {name: artifact(folder / name) for name in ("libcsv", "rust")}}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--goose", type=Path, required=True)
    parser.add_argument("--cc", default="gcc")
    parser.add_argument("--revision", default="WORKTREE")
    parser.add_argument("--goose-only", action="store_true")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    goose, compiler = args.goose.resolve(strict=True), Path(shutil.which(args.cc)).resolve(strict=True)
    frozen = inputs(goose, compiler)
    folder = ROOT / ".build/comparison"
    folder.mkdir(parents=True, exist_ok=True)
    result = {"inputs": frozen, "goose": build_goose(goose, compiler, args.revision, folder)}
    if not args.goose_only:
        result["alternatives"] = alternatives(compiler, folder)
    if inputs(goose, compiler) != frozen:
        raise RuntimeError("source/tools changed while building")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(f"comparison builds: {args.output}")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Exercise actual public generated C with frozen sanitizer provenance."""
from pathlib import Path
import argparse, datetime, json, os, platform, shutil, subprocess, sys, tempfile
from provenance import ROOT, inputs, sha256

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--goose', type=Path, required=True)
    p.add_argument('--cc', default='gcc')
    p.add_argument('--fuzz-runs', type=int, default=10000)
    p.add_argument('--output', type=Path, default=ROOT / '.build/sanitize.json')
    args = p.parse_args()
    if not 1 <= args.fuzz_runs <= 1000000: p.error('fuzz-runs must be 1..1000000')
    found = shutil.which(args.cc)
    if found is None: p.error('C compiler not found')
    goose, compiler = args.goose.resolve(strict=True), Path(found).resolve(strict=True)
    frozen = inputs(goose, compiler)
    if frozen['source']['status']: raise RuntimeError('Commit source before recording attributed sanitizer results')
    folder = ROOT / '.build/sanitize'; folder.mkdir(parents=True, exist_ok=True)
    invocation = Path(tempfile.mkdtemp(prefix=compiler.name+'-', dir=folder))
    wrapper, transcript = invocation / 'cc', invocation / 'compiler-commands.jsonl'
    flags = ['-O1','-g','-fno-omit-frame-pointer','-fsanitize=address,undefined','-UNDEBUG']
    wrapper.write_text('#!/usr/bin/env python3\nimport json,os,sys\n'
                       f'compiler={str(compiler)!r}\nlog={str(transcript)!r}\nflags={flags!r}\n'
                       'args=sys.argv[1:]\n'
                       "probe=any(a in args for a in ('-v','--version','-dumpversion','-dumpmachine'))\n"
                       "link=not probe and not any(a in args for a in ('-c','-E','-S'))\n"
                       "effective=[compiler,*args,*([] if probe else flags),*(['-no-pie'] if link else [])]\n"
                       "with open(log,'a') as f: f.write(json.dumps(effective)+'\\n')\n"
                       'os.execv(compiler,effective)\n')
    wrapper.chmod(0o755)
    env = dict(os.environ, ASAN_OPTIONS='detect_leaks=1:abort_on_error=1', UBSAN_OPTIONS='halt_on_error=1:print_stacktrace=1')
    records, binaries = [], {}
    def execute(command):
        proc = subprocess.run(list(map(str,command)), cwd=ROOT, env=env, capture_output=True, text=True, timeout=300)
        records.append({'command':list(map(str,command)), 'returncode':proc.returncode,'stdout':proc.stdout,'stderr':proc.stderr})
        if proc.returncode or proc.stderr:
            raise RuntimeError(f'Validation failed: {command!r}: exit={proc.returncode}, stdout={proc.stdout[-2000:]!r}, stderr={proc.stderr[-4000:]!r}')
        return proc.stdout
    for name, source, debug in [('api','api',False),('api-debug','api',True),('oracle','oracle',False),('fuzz','fuzz',False)]:
        binary = invocation / name
        execute([goose,'build',f'tests/{source}.goose','--standalone',*(['--debug'] if debug else []),'--cc',wrapper, '-o',binary])
        binaries[name] = {'path':str(binary),'sha256':sha256(binary)}
    execute([binaries['api']['path']])
    execute([binaries['api-debug']['path']])
    execute([binaries['fuzz']['path'],args.fuzz_runs])
    oracle = invocation / 'oracle-results.json'
    execute([sys.executable,'tests/oracle.py','--binary',binaries['oracle']['path'],'--output',oracle])
    if inputs(goose, compiler) != frozen: raise RuntimeError('Source/tools changed during execution; results rejected')
    if any(sha256(v['path']) != v['sha256'] for v in binaries.values()): raise RuntimeError('Executable changed; results rejected')
    commands = [json.loads(line) for line in transcript.read_text().splitlines()]
    # Pure-Goose programs compile/link a generated C file directly.
    targets = {v['path'] for v in binaries.values()}
    links = [c for c in commands if '-o' in c and c.index('-o') + 1 < len(c)
             and c[c.index('-o') + 1] in targets]
    if {c[c.index('-o') + 1] for c in links} != targets or any(c[-len(flags)-1:-1] != flags for c in links):
        raise RuntimeError('Actual generated C compiler commands lack sanitizer/assertion flags')
    result = {'recorded_at_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'inputs':frozen,'platform':platform.platform(),'affinity':sorted(os.sched_getaffinity(0)),
              'compiler_commands':commands,'compiler_commands_sha256':sha256(transcript),
              'binaries':binaries,'executions':records,'oracle':json.loads(oracle.read_text()),
              'fuzz_seed':81297,'fuzz_runs':args.fuzz_runs,
              'notes':['Instrumented actual generated Goose/runtime C; installed system libraries not rebuilt',
                       'Finite seeded mutation/roundtrip fuzzing, not coverage-guided fuzzing or certification']}
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(result,indent=2)+'\n')
    print(f'csv sanitizer: public API, {result["oracle"]["cases"]} oracle cases, {args.fuzz_runs} seeded fuzz cases passed ({args.cc})')
    print(f'csv sanitizer results: {args.output}')

if __name__ == '__main__': main()

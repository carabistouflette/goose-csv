# CSV baseline measurements

This records the current pure-Goose implementation. It does not compare libraries
or establish universal performance superiority. Profile a concrete workload before
adding an optimization or private native accelerator.

```sh
python3 bench/measure.py --goose /absolute/path/to/matching/goose --cc gcc
# CI execution-only smoke, with no timing threshold:
python3 bench/measure.py --goose /absolute/path/to/matching/goose --samples 1 --iterations 1
# Optional best-effort child affinity; coordinate shared-host timing first:
python3 bench/measure.py --goose /absolute/path/to/matching/goose --cpu 4
```

The recorder requires a clean committed working tree and the exact compiler pin
in `GOOSE_REVISION`. It snapshots all repository source files, commit/status,
compiler/Goose/Python binary hashes and versions. A fresh wrapper path records
actual program compiler calls and appends `-O2 -UNDEBUG`; generated Goose/runtime
C is compiled with those trailing flags. Inputs and the benchmark binary must
remain unchanged through completion or the observations are rejected.

The six fixtures exercise eight unquoted fields, quoted commas/escaped quotes/
embedded CRLF, 256 empty fields, UTF-8 bytes, all byte values including NUL, and a
256 KiB field. The basic row runs with 1/64/4096/65536-byte read chunks, while the
other fixtures use 4096-byte chunks. A multirow batch contains as many complete
rows as fit within roughly 64 KiB; the long row forms its own 256 KiB batch.
Each case repeats that bounded batch (`--iterations`, default 16). There is no
whole large-input buffer or growing output-row queue. Writer cases repeat the
same actual row count and replace one reusable output buffer each call.

Before measurement, fixture bytes are checked against independent Python `csv`
encoding through a full hex manifest, whose byte/field hashes are recorded. The
Goose driver checks every decoded setup field against the originals. Monotonic
`clock_ns` case timings include public codec calls, assertions, byte/row counting
and sampled data signatures. Parser signatures use field count, decoded lengths
and first/middle/last bytes; writer signatures use actual output length and those
sampled bytes. Full final fields/output are checked outside case timing. These
signatures resist dead-code elimination but are not cryptographic integrity proofs.

Initialization, fixture/block construction, full setup checks and reporting are
outside the native case timer. Separate process wall times include all of them
plus startup and are retained separately; they must not be substituted for codec
case timings. Six fixture records generate 15 parse/write cases per sample in
fixed order. One one-iteration warmup precedes the default five samples. Every
sample, order, raw stdout, actual byte/row count and checksum is retained.

The JSON output records CPU model/platform/libc, allowed affinity, optional
benchmark-child affinity, shared-host load before/after, compiler transcript and
binary hash. Affinity does not imply an exclusive core or isolated host. No
outlier removal, timing-based CI gate, algorithmic coverage claim, hard RSS bound
or claim that setup/system libraries were sanitizer-instrumented is made here.

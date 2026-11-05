# Native CSV comparison tooling

This optional tooling compares the released Goose byte codec with exact Rust
`csv=1.4.0`, `csv-core=0.1.13`, `simd-csv=0.14.0` and libcsv source
`b1d5212831842ee5869d99bc208a21837e4037d5`. See the
[contract](CONTRACT.md) and [research/feature matrix](../../docs/ALTERNATIVES.md).
No throughput or SOTA conclusion follows from adding tooling.

The library keeps its standard-library-only build. Cargo and downloaded libcsv
are benchmark dependencies only, stored in ignored directories. Their licenses
are recorded in build reports; no upstream source or executable is vendored.
`Cargo.lock` freezes transitive packages. Verification checks registry archive
SHA-256 and every extracted archive file before compilation, plus the exact clean
libcsv Git object. This is reproducibility evidence, not a security attestation.

## Build and qualify

Run from the repository root with the pinned Goose executable:

```sh
python3 bench/compare/build.py --goose /path/to/goose --output .build/comparison/build.json
python3 bench/compare/qualify.py --build-record .build/comparison/build.json \
  --output .build/comparison/qualification.json
```

The build uses GCC `-O3 -g -march=native -fno-omit-frame-pointer -flto -UNDEBUG`
for both actual generated Goose C and libcsv. Goose's own inlining level is its
normal `-O2`. Rust uses release optimization level 3, thin LTO, one codegen unit,
`target-cpu=native`, frame pointers and enabled overflow checks. Actual toolchain
binaries are resolved through rustup; effective compiler commands and Cargo
configuration hashes are retained. Relevant profile/environment overrides disable
wrappers/incremental builds and make these settings explicit. Compiler backends
and optimization strategies differ and must be disclosed. Recorded binaries are
host specific. Production portable builds remain unchanged.

Qualification compares **every emitted decoded field and encoded byte**, final
accept/reject state and row/byte/signature accounting. It exercises output-buffer
and field-end growth, split CRLF/quotes, all byte values, long plain/escaped fields,
mixed widths, EOF-only fields and malformed syntax. Feature differences are
retained rather than repaired. Shared timing inputs are all CRLF terminated;
repetitions concatenate one stream and EOF occurs once. Unterminated/error probes
run once. Physical bytes read by buffered Rust readers are not consumed-byte
error coordinates. Successful premature native EOF is recorded as incomplete
input even when a parser accepts the prefix.

The corpus preserves the original six fixture contents and adds a long escaped
field, clustered quotes and deterministic variable mixed records, 1024-column records and
escape-heavy data (seed 712911). Python `csv` independently encodes and completely
decodes every shared fixture before any native timer. This bounded corpus does
not establish results on arbitrary production datasets.

## Timing gates

Commit source before recording attributed results. Announce actual timing
START/RELEASE to the coordinator as a shared-host courtesy; affinity is not
isolation. No host settings are changed.

```sh
python3 bench/compare/measure.py --goose /path/to/goose --phase control \
  --build-record .build/comparison/build.json --output .build/comparison/control.json
python3 bench/compare/measure.py --goose /path/to/goose --phase compare \
  --build-record .build/comparison/build.json --controls .build/comparison/control.json \
  --output .build/comparison/comparison.json
```

A/A builds use identical released CSV source at the same source, generated-C and
executable paths. Source snapshot, generated C, entire executable and executable
section hashes must match before timing. Control timings are labeled A/B even
though code is identical; they describe noise, not an optimization. A changed
harness/toolchain requires new controls. Later candidates use those same paths;
only our ignored snapshot is written, never a release checkout or parent index.
Every run freezes source/tool, fixture, receipt and executable identities and
checks them after execution. Append-only raw JSONL journals retain calibrations,
samples and incomplete/rejected-run reasons; old output paths are refused.

The recorder calibrates each case/engine to at least 100 ms, retains every
calibration separately, then takes seven samples with alternating engine and
fixture order. Native monotonic timers exclude process startup, fixture reads and
initial setup. Timing includes row materialization, buffer growth on first use,
signatures and complete per-record writer output. Libcsv preallocates the corpus
worst-case row output before timing; the other adapters begin with their default
or 4 KiB storage and grow as needed. Cold allocation latency is not measured.
Rust buffered writers flush
every record into an owned reusable sink without shared-mutation adapter overhead.
csv-core uses reusable caller buffers; libcsv callbacks copy fields into an owned
reusable row. Goose keeps strict grammar and limit checks, with its supported
total-byte budget set to the public maximum for repeated streams; other default
limits stay active.

libcsv supplies a field writer. Its labeled row adapter adds minimal-quoting
preflight, delimiters and CRLF, and is not a native full-row API. Rust and SIMD
readers use 64 KiB internal buffers behind physically chunk-limited input. These
layers differ from direct caller chunks and are reported, not hidden. No extra
compatibility validation is charged to alternatives.

Raw samples, per-case dispersion, controls, source/binary/compiler identities and
feature gaps must accompany results. The valid-data throughput tier does not
establish equivalent exact budgets, strict malformed rejection, lifecycle/error
coordinates, retry atomicity, allocation/RSS behavior or a universal fastest CSV
implementation. Accepted source changes additionally require the existing public
API/oracle/fuzz and GCC/Clang sanitizer gates.

## Caller context

The optimized native caller tier explicitly inlines the Goose benchmark's
`parse` and `encode` entry wrappers for both released baseline and candidate.
This keeps Root dataset provenance visible to the compiler despite changes in
the opposite mode. Other adapters retain their existing legal optimizations;
no extra copies, validation or forced non-inlining are imposed on them.

The original caller records remain real results for their original harness.
In particular, a larger reader caused the compiler to stop inlining the writer
wrapper, changing quote-count vectorization and dense-writer throughput. The
optimized caller tier is a harness change, not another library speedup. It uses
fresh matching A/A controls and separate comparison records. Neither tier proves
that every application context or compiler will make the same decisions.

Builds select one CPU (`build.py --cpu`, default first allowed CPU), recorded in
the build receipt. The recorder rebuilds baseline and candidate with that same
build affinity, then selects its separate runtime CPU. This stabilizes native
CPU detection and distinguishes build placement from measured affinity. Local
comparison builds use CPU 2 and measured programs use CPU 4; these are placement
choices on a shared host, with no isolation claim.

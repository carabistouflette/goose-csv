# CSV native comparison and optimization

Measured implementation and optimized-caller harness source: `0376fece8625827d6ef2754d48d40df8204ec24f`.
CSV source SHA-256: `40d10abdd89761f3fb7b24a74160b14a090ad1e851201df8df33a1be4ce7efc1`. Frozen released baseline:
`4ec59cf17685f85e537cac264527d28af8ab9f2f` (`v0.1.0-alpha.1`).
The released tag and parent registration remain unchanged.

The result is a scoped native-API comparison, not an established universal SOTA
ranking. Goose retains its bounded strict byte contract. Other libraries keep
their native behavior; no compatibility checks or extra copies are added to slow
them down. Some alternatives share algorithms: Rust csv uses csv-core.

## What changed

Ordinary reader runs use the pinned standard runtime's prepared byte sets and
search primitives, capped by field, raw-row and cumulative budgets. Syntax and
budget boundary bytes use the same scalar state transition as the release.
A bounded initial-prefix dispatcher keeps short fields on the canonical scalar
loop. It selects bulk only after finding 32 ordinary initial bytes in a chunk
with sufficient budgets. Short quoted remainders return to scalar processing.
A short leading field can keep a later long field scalar until another caller
chunk arrives; long-first-field results do not establish the same improvement
for long later fields or arbitrary layouts. The writer scans a
short scalar prefix before searching longer tails, reuses quote/escape plans,
skips empty copies and combines successful budget checks while preserving the
release's RowLimit-before-TotalLimit error classification. Output remains staged
until the complete row succeeds.

No private native accelerator or new runtime dependency was added. Compiler
inlining is deliberate for the reader; an attempt to force all writer call sites
inline was rejected when GCC sanitizer compilation exceeded the unchanged
300-second gate. All trials and raw observations are retained.

## Contracts and features

The complete source-backed matrix and exact alternative pins/licenses are in
[ALTERNATIVES.md](ALTERNATIVES.md). The executable feature records are separate
from shared-valid-data throughput qualification.

| Native API property | Goose CSV | Rust csv / csv-core | medialab/simd-csv | libcsv |
| --- | --- | --- | --- | --- |
| Reader and writer | Both | Both | Both | Reader + field writer; row adapter disclosed |
| Byte output / input | Opaque bytes | Byte APIs; initial BOM behavior differs | Byte APIs; chunk-dependent BOM trimming | Length-delimited bytes |
| Blank physical record | Zero fields retained | Skipped | Skipped | Skipped by default |
| Strict malformed quoting | Built in | Permissive | Permissive | Strict + strict-fini configured |
| Outside newline policy | CRLF/LF, optional strict CRLF | Different terminator semantics | Different | Different |
| Four exact budgets and offending-byte positions | Built in | No equivalent combined API | No equivalent combined API | No equivalent combined API |
| Failed-write state/output preservation and retry | Built in | Caller staging | Caller staging | Caller staging |
| Dialect configuration, headers, typed conveniences | Fixed comma/double-quote byte codec | Richer interfaces | Configurable interfaces | Configurable delimiter/quote |

The 380 qualification records contain 125 complete shared-valid-data matches and
255 feature probes that deliberately retain native differences. At a three-byte
initial BOM boundary, the pinned Rust reader/core accept only the BOM prefix as
EOF; this is recorded as incomplete input, not described merely as BOM removal.
All fields and output bytes are checked outside timed loops. Timed samples also
require successful EOF, exact byte/row totals and identical signatures.

## Measurement scope

3 full comparison passes, 3150 retained samples, 25 cases,
21 samples per engine/case. Eleven fixtures preserve the six original
contents and add deterministic mixed/wide/escape-heavy records, long escaped
fields and clustered quotes. Seed 712911. The shared corpus uses terminated
records; repetitions form one stream and EOF occurs once.

The optimized native caller tier explicitly inlines the Goose benchmark entry
wrappers for BOTH baseline and candidate. This keeps Root dataset provenance
visible to the compiler and avoids the observed opposite-mode wrapper-inlining
interaction. It is a harness change, not an extra library speedup. Original
caller records remain real results for that caller/compiler arrangement, including
dense-writer regressions. They are not relabeled as noise or replaced.

Build placement is recorded CPU 2; native timed children use CPU 4. This is a
shared host, with no exclusive reservation, frequency/isolation claim or host
setting change. All A/A controls, calibrations and ordered samples are retained.
Fresh matching A/A source/generated-C/executable identities precede this tier.
Small differences must be assessed against control variation and sample ranges.

Goose and libcsv use GCC `-O3 -g -march=native -fno-omit-frame-pointer -flto
-UNDEBUG`; Goose's language inlining level is its default `-O2`. Rust uses
optimization level 3, thin LTO, one codegen unit, native CPU and overflow checks.
Actual tool binaries, configuration overrides, compiler commands, dependency
archive/source hashes and executable section hashes are recorded. This is not a
hermetic toolchain claim. See [tooling](../bench/compare/README.md).

Timers exclude process startup, file reads and dataset setup; they include owned
row materialization, signatures and complete per-row writer output/flush. Libcsv's
canonical row adapter preallocates worst-case output outside timing; other
adapters start with their documented/default storage and grow as needed. Cold
allocation, peak RSS, retained capacity, I/O throughput, parallel parsing and
application-level tail latency are outside this measurement. Arrow/DuckDB and
optional zsv were researched as distinct tiers, not measured here.

## Interpretation and tradeoffs

Across the three passes, pooled median throughput improves 16.20× for the
256 KiB ordinary-field reader and 8.55× for its writer versus the frozen release.
The writer reaches 5,557.7 decimal wire MB/s on that fixture, versus 2,520.4 for
the fastest selected external writer. This is a lead on this specific valid-data
fixture/API tier, not a general SOTA claim. The candidate reader reaches 5,329.1
MB/s there while simd-csv reaches 7,446.0 MB/s. Binary and quote-cluster fixtures
also show large gains; many other external APIs remain faster on other cases.

The tradeoff is visible: several short-field reader cases have pooled median
throughput about 4–10% below the release; mixed-record writer throughput is about
4% lower. These observations are retained as regressions, not normalized away.
Fresh identical-code A/A per-case median throughput ratios range from 0.917 to
1.097, so small differences do not establish isolated causal effects or a reliable
win. The older optimized-caller A/A record shows wider variation and is retained.
Full sample ranges and all per-case observations remain available. No outliers,
controls or failed candidates are removed, and no correction is applied.

This implementation chooses bounded long-run throughput while keeping syntax,
limits, output ownership and retry semantics. It is not an unconditional speedup
for short-row workloads. Applications should compare their own distributions
before changing an immutable dependency pin. This work advances no released tag,
parent pin or application adoption.

## All measured cases

Decimal wire MB/s; higher is better. Values are medians across all retained
samples. The interactive chart exposes full sample ranges. Differences in native
contracts remain visible above; these are shared-valid-data API timings.

| Fixture | Operation / chunk | Goose release | Goose candidate | Rust csv | csv-core | simd-csv | libcsv adapter | Candidate / release |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| simple | parse / 1 | 89.4 | 83.7 | 38.3 | 53.8 | 36.7 | 110.1 | 0.94× |
| simple | parse / 64 | 116.0 | 107.4 | 144.4 | 141.3 | 146.9 | 127.1 | 0.93× |
| simple | parse / 4096 | 125.6 | 120.3 | 148.5 | 161.2 | 167.3 | 130.5 | 0.96× |
| simple | parse / 65536 | 120.1 | 111.9 | 158.7 | 163.1 | 176.4 | 131.5 | 0.93× |
| simple | write / complete row | 406.4 | 405.5 | 521.0 | 341.6 | 570.1 | 677.4 | 1.00× |
| quoted | parse / 4096 | 197.0 | 180.1 | 276.9 | 280.5 | 249.8 | 200.5 | 0.91× |
| quoted | write / complete row | 474.1 | 516.0 | 526.8 | 403.9 | 585.8 | 911.9 | 1.09× |
| empty256 | parse / 4096 | 88.6 | 82.8 | 87.6 | 85.8 | 81.9 | 75.9 | 0.93× |
| empty256 | write / complete row | 144.2 | 229.1 | 87.9 | 78.9 | 208.1 | 605.4 | 1.59× |
| utf8 | parse / 4096 | 119.7 | 107.8 | 158.8 | 162.0 | 159.3 | 145.2 | 0.90× |
| utf8 | write / complete row | 317.4 | 313.2 | 394.6 | 280.9 | 373.1 | 644.8 | 0.99× |
| binary | parse / 4096 | 312.1 | 1577.8 | 912.5 | 990.3 | 2331.3 | 476.8 | 5.05× |
| binary | write / complete row | 479.4 | 2125.3 | 3452.1 | 3403.8 | 3826.6 | 1197.5 | 4.43× |
| long256k | parse / 4096 | 329.0 | 5329.1 | 1457.2 | 1623.0 | 7446.0 | 515.6 | 16.20× |
| long256k | write / complete row | 649.7 | 5557.7 | 2250.3 | 2387.1 | 2520.4 | 1004.2 | 8.55× |
| long-escaped | parse / 4096 | 363.3 | 347.4 | 410.7 | 483.7 | 356.3 | 324.3 | 0.96× |
| long-escaped | write / complete row | 518.2 | 687.1 | 349.6 | 378.6 | 405.1 | 1088.2 | 1.33× |
| quote-cluster | parse / 4096 | 338.9 | 3244.4 | 1438.8 | 1426.2 | 5061.7 | 504.4 | 9.57× |
| quote-cluster | write / complete row | 493.4 | 2466.6 | 2521.1 | 2897.3 | 2694.5 | 881.5 | 5.00× |
| mixed-records | parse / 4096 | 171.1 | 155.4 | 257.7 | 267.0 | 299.0 | 191.3 | 0.91× |
| mixed-records | write / complete row | 423.3 | 405.4 | 595.6 | 446.7 | 656.2 | 541.9 | 0.96× |
| wide-variable | parse / 4096 | 179.5 | 161.4 | 305.7 | 314.7 | 391.6 | 196.1 | 0.90× |
| wide-variable | write / complete row | 540.3 | 579.1 | 1136.1 | 709.9 | 1085.0 | 836.3 | 1.07× |
| escape-heavy | parse / 4096 | 165.3 | 187.9 | 123.1 | 119.7 | 211.8 | 75.4 | 1.14× |
| escape-heavy | write / complete row | 151.5 | 161.4 | 251.3 | 215.9 | 273.1 | 323.7 | 1.07× |

## Validation and review

The production implementation passes 5,601 independent differential/contract
cases in JIT, debug, native and GCC/Clang ASan+UBSan modes, with 10,000 seeded
mutation/roundtrip cases per mode. Real 16 MiB field and 65,536-field hard ceilings,
output preservation, retry, lifecycle and chunk/syntax/limit boundaries are
covered. The expanded 5,601-case corpus also passes against the exact frozen
released scalar implementation. Finite tests and sanitizers are not a proof or
coverage-guided fuzzing claim.

Independent adapter fairness, adapter safety, methodology/attribution,
qualification and production security/quality reviews drove concrete corrections.
Original caller interactions, the rejected fully inlined compiler gate, all raw
samples/calibrations and instruction profiles remain available in the evidence
folder. Instrumented profile elapsed times are not native throughput samples.
A historical profile rebuild matched the four recorded execution/data/unwind
sections while its whole-file hash differed; that receipt makes the narrower
profiling equivalence explicit. No timing result was substituted.

Evidence: [manifest](../bench/results/comparison-2026-11-05/MANIFEST.json),
[raw records](../bench/results/comparison-2026-11-05/raw/),
[build/qualification receipts](../bench/results/comparison-2026-11-05/builds/),
[validation](../bench/results/comparison-2026-11-05/validation/),
[interactive chart](../bench/results/comparison-2026-11-05/comparison.html).

The source stays a byte codec: it does not add installer/trust policy, spreadsheet
formula policy, Unicode validation, header/type inference or sibling adoption.

## Reproduce the chart

From the repository root (Python standard library only):

```sh
python3 scripts/comparison-report.py \
  bench/results/comparison-2026-11-05/raw/candidate-0376fec.json \
  bench/results/comparison-2026-11-05/raw/candidate-0376fec-confirm-1.json \
  bench/results/comparison-2026-11-05/raw/candidate-0376fec-confirm-2.json \
  --output .build/reproduced-comparison
```

The renderer rejects differing source/tools/build receipts/controls, differing
Goose generated C/executable sections, differing alternative executables, and
missing or duplicate case/engine/sample cells before pooling. Whole Goose
executable hashes remain recorded even though cross-pass executable-section
identity is the renderer's check. The manifest covers every committed evidence
file; no binaries, generated compiler sources or downloaded upstream code are
included. Original local paths in receipts describe their actual invocation.

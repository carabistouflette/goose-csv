# CSV comparison alternatives

Research date: 2026-11-05. Scope: reader **and** writer comparison against frozen
`4ec59cf17685f85e537cac264527d28af8ab9f2f` (v0.1.0-alpha.1), following the
[comparison contract](../bench/compare/CONTRACT.md). This is source research, not
an executable conformance result or performance measurement. No candidate was
built or timed for this note. Recommendations below are research judgments;
behavioral descriptions cite the corresponding primary documentation/source.

## Recommended comparison set

Use Rust **csv 1.4.0**, **csv-core 0.1.13**, C **libcsv 3.0.3**, and Rust
**medialab/simd-csv 0.14.0** for the first native comparison. They provide,
respectively, a reusable owned-row interface, a caller-buffer codec, a streaming
callback baseline, and an actual SIMD reader/writer candidate. Keep **CPython
csv** as a separately labeled reference. Add **zsv fast** as a second SIMD parser
if adapter time permits; its writer needs a separate output-policy tier. API
support, rather than upstream throughput claims, motivates this selection.
[Rust reader][r-reader] [core reader][c-reader] [libcsv API][l-header]
[SIMD reader][s-reader] [SIMD writer][s-writer] [zsv API][z-api]

There is no demonstrated universal SOTA winner here. In particular, none of the
reviewed external native APIs directly supplies Goose's combined strict byte
syntax, zero-field blank records, four exact budgets, offending-byte coordinates,
reader lifecycle and atomic writer retry contract. Treat an absent capability as
a feature gap, not a reason to weaken Goose. This conclusion concerns the APIs
reviewed below, not every possible extension or application built around them.
[Goose design](DESIGN.md) [core reader][c-reader] [libcsv source][l-source]
[SIMD errors][s-error] [zsv options][z-common]

## Immutable inputs and acquisition

Versions were looked up, not inferred from memory. The crates.io APIs reported
`csv=1.4.0`, `csv-core=0.1.13`, `simd-csv=0.14.0` as their newest/stable versions
at lookup. The published archives were read in memory, including
`.cargo_vcs_info.json` and `Cargo.toml.orig`; the recorded Rust commit objects were
also resolved against GitHub. Registry release and repository head are different
identities: do not substitute a moving branch. [csv registry][r-reg]
[core registry][c-reg] [SIMD registry][s-reg]

| Candidate | Selected source identity | License evidence |
| --- | --- | --- |
| Rust csv | `1.4.0`; archive VCS `4a3997e91d668ea1d8595bdef15625a77cf2308a` | Unlicense OR MIT; [manifest][r-manifest] |
| Rust csv-core | `0.1.13`; archive VCS `a0a3c9e4b493c216fb6d8284c9ac918444ba67f3`, subdirectory `csv-core` | Unlicense OR MIT; [manifest][c-manifest] |
| medialab/simd-csv | `0.14.0`; archive VCS `df2cceb3bfe0427efc63fa213392f8c5b2713b47` | MIT; [manifest][s-manifest] |
| rgamble/libcsv | Header reports `3.0.3`; selected repository commit `b1d5212831842ee5869d99bc208a21837e4037d5` (not a claim about a release tarball) | LGPL-2.1-or-later; [header][l-header], [license][l-license] |
| liquidaty/zsv | Selected development snapshot `2e2181930f68b6b83da69eb19d24636393d15408`, not a release claim | MIT; [license][z-license], [commit lookup][z-pin] |
| CPython csv | `v3.14.10`, resolved commit `b703b2c5e704341d61e367b9b940b77ed11dded0` | PSF license and historical notices; [license][p-license], [commit lookup][p-pin] |
| Apache Arrow C++ | `apache-arrow-26.0.1`, recursively peeled commit `9e5d6978e9acf372cc989aaaf94e863fe8582c90` | Apache-2.0 and bundled notices; [license][a-license], [tag][a-tag] |
| DuckDB | `v2.0.0`, commit `d54cbbe3df17e8e5ce68312f483b4155836112aa` | MIT; [license][d-license], [release][d-release] |

The three registry archive SHA-256 values returned by the registry are:

| Archive | SHA-256 |
| --- | --- |
| csv 1.4.0 | `52cd9d68cf7efc6ddfaaee42e7288d3a99d613d4b50f76ce9827ae0c6e14f938` |
| csv-core 0.1.13 | `704a3c26996a80471189265814dbc2c257598b96b8a7feae2d31ace646bb9782` |
| simd-csv 0.14.0 | `131b52919dd05c58d395a06cd09bfb55d25a06ca3c1acec7ec2a22696bff4cdb` |

Sources: [csv registry][r-reg], [core registry][c-reg], [SIMD registry][s-reg].
Download using `https://crates.io/api/v1/crates/NAME/VERSION/download`, check the
archive hash, then inspect `.cargo_vcs_info.json`. Use exact Cargo dependency
requirements (`=1.4.0`, `=0.1.13`, `=0.14.0`) and retain the eventual adapter's
`Cargo.lock`: a top-level version alone does not pin transitive dependencies.
For git sources, fetch the selected commit, check `git rev-parse HEAD`, and retain
source/archive hashes. For annotated tags, recursively follow the API object's
`type=tag` until `type=commit`; Arrow's selected tag required two such steps.
The sources above identify the upstream lookup endpoints and manifests.

Build availability is **source/API availability**, not a successful-build claim.
This host has `cargo`, `rustc`, `cc`, `clang`, `cmake`, `make`, `python3` and
`pkg-config` on PATH; versions/dependencies were not qualified here. csv declares
Rust 1.73; simd-csv's checked-in toolchain selects 1.81.0. libcsv offers a small C
API/source; zsv documents a Unix configure/make library-only build with GCC 11+
recommended. A library-only zsv build must not be assumed to include its
`app/utils/writer.c` utility. Arrow/DuckDB are optional larger build/dependency
commitments. [csv manifest][r-manifest] [SIMD toolchain][s-toolchain]
[libcsv source][l-source] [zsv build][z-build] [zsv writer source][z-writer-source]

## Feature matrix

The matrix describes the pinned native APIs before compatibility wrappers.
“Gap” means Goose equivalence is absent or unestablished from the reviewed API,
not that the product cannot be used safely under its own contract.

| Property | Goose baseline | Rust csv / csv-core | libcsv | medialab/simd-csv | zsv fast | CPython csv |
| --- | --- | --- | --- | --- | --- | --- |
| Reader / writer | Both | Both / both | Both; writer is field encoder | Both | Parser plus utility writer | Both |
| Input model | Caller byte chunks, one row per result | `Read` / caller byte+output slices | Byte chunks, field/row callbacks | Buffered `Read`; core is private | Byte chunks/read callback; row callbacks or pull | Iterable of text lines |
| Decoded output | Owned Row, borrowed field views | Reused owned ByteRecord / caller decoded bytes+ends | Borrowed callback field; copy to retain | Reused owned ByteRecord; separate zero-copy API | Borrowed cell pointers; copy to retain | New list of strings |
| Opaque bytes | Yes; no BOM stripping | Byte API yes, but initial UTF-8 BOM stripped | Binary length API | Byte API yes, but initial BOM trimmed | Explicit malformed-UTF8 policy; byte parity needs qualification | Unicode; byte mapping is adapter work |
| Multiline / doubled quotes | Yes | Yes | Yes | Yes | Yes, standard-quote path | Yes |
| Blank physical record | Zero fields | Skipped by reader | Skipped by default; report-all option differs for CRLF | Skipped by reader | API reports at least one cell; leading blanks have separate option | Empty list |
| Sole quoted empty / trailing comma | One empty / final empty | Representable | Representable | Representable | Must qualify zero/one distinction | Representable |
| Strict malformed quoting | Reject bare quote, post-quote junk, unclosed quote | Permissive; core never returns syntax error | Strict + strict-fini needed | No malformed-quote error in reviewed enum/core | Some nonstandard quotes signaled; full Goose strictness unestablished | `strict=True` still allows quotes inside bare fields |
| Outside newline policy | CRLF or LF; bare CR rejected; CRLF-only option | Default CR, LF, CRLF; custom terminator is not strict CRLF validation | CR and LF independently; normalization needed | LF/CRLF-oriented permissive scanner; not Goose validator | `only_crlf_rowend` exists; rejection equivalence unestablished | Accepts CR or LF; reader ignores writer lineterminator |
| Four exact limits / byte error coordinates | Built in | Gap; record positions are not strict offending-byte positions | Parse count + error code; no four-budget API | Position/unequal-length error, no four-budget API | Row/column/buffer options and scan counts; different overflow contract | Field-character limit, physical line count; no byte offsets |
| Canonical zero-field writer | CRLF | Empty record becomes quoted empty field | Caller assembles record | Source emits empty CRLF with configured CRLF mode | Cell-oriented LF output; mismatch | Empty row emits configured terminator |
| Atomic row output / retry | Preflight; preserve state/output | Buffered incremental writer; no equivalent promise | May fill destination prefix; caller must stage | Buffered incremental writer; no equivalent promise | Incremental writer; no equivalent promise | Builds row before text sink call; no four-budget retry contract |

Evidence by column: [Goose contract](DESIGN.md); Rust [reader][r-reader],
[core reader][c-reader], [core source][c-reader-source], [writer source][r-writer-source],
[core writer][c-writer-source]; libcsv [manual][l-manual], [source][l-source],
[header][l-header]; SIMD [reader][s-reader], [core][s-core], [records][s-records],
[writer][s-writer], [errors][s-error]; zsv [API][z-api], [options][z-common],
[fast engine][z-fast], [writer][z-writer-source]; Python [manual][p-doc],
[C parser/writer][p-source]. Cells summarize these sources; executable parity
checks remain required before publishing a measured comparison.

## Native adapter recommendations

### Rust csv and csv-core

For csv use `ReaderBuilder::new().has_headers(false).flexible(true)` with no
trimming/comment handling, `read_byte_record(&mut reusable_record)`, and a custom
`Read` implementation that caps returned bytes to the requested chunk size. Use
`ByteRecord`, not UTF-8 `StringRecord`, Serde, or allocating iterator records.
The reader already owns its decoded record; do not force an extra clone merely
because Goose internally copies completed rows. [reader][r-reader]
[reader source][r-reader-source]

For csv-core drive `read_record(input, output, ends)` using reusable byte and end
buffers. Handle input exhaustion and both output-full cases, accumulate offsets,
and resume without losing the partial record. **Empty input means EOF**, whereas
Goose permits an empty nonterminal chunk: suppress empty source chunks and only
drain core with empty input at actual EOF. These are distinct APIs and should
have distinct rows in results rather than presenting csv-core as a second
independent parsing algorithm. [core API][c-reader] [csv manifest][r-manifest]

The default Rust parser deliberately accepts malformed CSV, skips blank lines,
and treats CR, LF and CRLF as terminators. `flexible(true)` only disables
unequal-column checks; it does not enable strict syntax. `Terminator::CRLF` is
not a CR-followed-by-LF validation switch. The core strips a complete leading
UTF-8 BOM on its first call, but its source explicitly notes that a partial BOM
in the initial buffer is not stripped. BOM input therefore needs its own
chunk-sensitive divergence case, not just a “raw bytes supported” tick.
[core API][c-reader] [BOM/source state machine][c-reader-source]

For writing use csv `WriterBuilder`, `flexible(true)`, `Terminator::CRLF`,
`QuoteStyle::Necessary`, byte records, and a reusable in-memory sink; include
flush in the chosen output-availability timing scope. For core use complete
fields with `field`, then `delimiter`/`terminator`, retrying output-full results
and finishing as documented. Necessary quoting cannot decide from an arbitrary
partial field. Both Rust writers distinguish a sole empty field from ordinary
nonempty records, but both encode a zero-field record as a quoted empty field.
An adapter may emit CRLF for zero fields, explicitly identifying this small
compatibility branch; it is not native zero-field equivalence. Neither writer
provides Goose's row-budget preflight/atomic replacement semantics.
[writer][r-writer-source] [core writer API][c-writer-api]
[core writer implementation][c-writer-source]

The selected Rust core uses a table-driven state machine with optimized searches;
libcsv's selected `csv_parse` implementation is a byte-state loop. These are
single-parser baselines, not a claim that every Rust dependency is scalar.
Neither API supplies a built-in parallel scan for the chosen path. Record target
flags/dependency features alongside the SIMD candidate; do not infer active SIMD
from the language name. [core implementation][c-reader-source]
[libcsv implementation][l-source]

### C libcsv

Use `csv_init(CSV_STRICT | CSV_STRICT_FINI)`, `csv_set_space_func` with a callback
that always returns false, and `csv_parse` on the same byte chunks; call
`csv_fini` at EOF and check both return values and `csv_error`. Disabling space
classification matters: default behavior strips leading/trailing spaces/tabs
and permits them after a closing quote. Copy field callback data by its supplied
length into a reusable contiguous owned-row buffer plus spans; callback storage
must not escape as a retained row. Sum processed counts for input positions;
`csv_parse` returns the prefix before a syntax error, but this does not supply
Goose's complete record/field/budget/lifecycle contract. [manual][l-manual]
[source][l-source]

Default libcsv suppresses empty rows. `CSV_REPALL_NL` reports each outside CR/LF,
including the two bytes of CRLF separately. A row assembler could coalesce CRLF
and preserve blank records, but a simple callback counter is wrong. No static
terminator callback establishes the strict CRLF-follow rule: a validator needs
quote/newline state. A post-callback field limit is too late to claim bounded
allocation; allocator hooks can cap storage but do not automatically implement
Goose's decoded-field and wire-row semantics. Keep these gaps visible.
[manual][l-manual] [source][l-source] [API][l-header]

`csv_write`/`csv_write2` encode **one always-quoted field**, returning the required
size and possibly writing a truncated prefix. They do not add commas or CRLF.
A fair native field-encoding tier can use quote-all for every participant. A
canonical-row tier needs a disclosed adapter that scans for required quoting,
copies safe fields, invokes libcsv for quoted fields, handles zero fields, and
assembles delimiters/CRLF into scratch. Use a non-null pointer for a zero-length
field: a null source returns zero rather than the quoted empty representation.
Capacity arithmetic must be checked before assembly. This wrapper is part of
what is measured; do not attribute its minimal-quoting policy to libcsv.
[writer implementation][l-source]

### SIMD contender: medialab/simd-csv

Use the pinned `ReaderBuilder` with `has_headers(false)`, `flexible(true)` and
`read_byte_record(&mut ByteRecord)`. Cap the input `Read` as above; disclose its
internal buffer capacity. Do not select `ZeroCopyReader`, line splitting,
raw-record passthrough, or projection for the owned decoded-row tier. The
implementation clears/reuses the supplied record, maintains partial input state,
skips bare newline records and trims the initial BOM. Error kinds include I/O,
UTF-8 and unequal lengths, not malformed quotes. The core's EOF branch finalizes
an unfinished record without a quoted-state rejection; quotes encountered within
unquoted text also enter its quoted path. This is a valid-data speed contender,
not a strict replacement. [reader][s-reader] [core][s-core] [errors][s-error]

A further source-derived concern needs executable qualification: EOF invokes
`finalize_record`, whose implementation strips a trailing CR from the last
decoded field. This appears capable of changing valid input `"\r"` at EOF
(a quoted field containing CR, with no row ending). Do not assume all valid
Goose inputs belong to the shared fast-path corpus, or repair decoded data
silently in the adapter. This is an inference from the pinned call path, not a
reproduced failure in this research. [core EOF][s-core] [record finalization][s-records]

Use `WriterBuilder::flexible(true).crlf_newlines(true)` and normal
`write_record`/`write_byte_record` over byte slices. Its source handles a sole
empty field by quoting and a zero-field row by emitting the ending. Avoid
`write_record_no_quoting` and zero-copy raw passthrough: those interfaces exploit
information/work excluded from ordinary encoding. Reuse the writer/sink and
include flushing for output that must be visible after each row. Budget and
atomic-output wrappers remain separate work. [writer][s-writer]

SIMD eligibility is backed by code, not a benchmark headline: `searcher.rs`
selects SSE2 on x86-64, NEON on aarch64, and a fallback elsewhere; quote searches
use `memchr`, also in writer quoting. The README discusses runtime AVX2 through
its search dependencies, but that is not evidence that every loop uses AVX2.
These selected reader/writer paths have no user thread-pool setting. Record CPU
features, compiler, target flags and locked dependencies before attributing a
measured gain to a particular instruction set. [searcher][s-searcher]
[core][s-core] [writer][s-writer] [README][s-readme]

### Second SIMD contender: zsv

Use `zsv_new`, explicit options selecting `scan_engine=3`, `zsv_parse_bytes`, row
callbacks retrieving pointer+length cells, and `zsv_finish`. Copy decoded cells
into the owned row inside the callback before advancing. Set
`keep_empty_header_rows=1` and explicitly select
`ZSV_MALFORMED_UTF8_DO_NOT_REPLACE` for byte-oriented experiments. Disable row
count-only/column selection/raw-output shortcuts. Its fast source implements
prefix-XOR quote-state scanning and selects architecture-specific NEON, AVX2 or
SSE2 code; it returns `zsv_status_nonstandard_csv` for detected nonstandard quote
patterns. Do not equate that detection with all Goose syntax/EOF guarantees or
silently retry a failed fast run using compat mode. [API][z-api]
[options/status][z-common] [fast source][z-fast]

The API reports at least one cell per parsed row; row/column settings are not
Goose's four budgets. Overflow callbacks can expose portions of an oversized row,
which is a different failure/materialization model. Capture overflow as failure
in comparison adapters rather than treating partial rows as complete. Full NUL,
BOM, bare-CR, unclosed-quote, empty-field and boundary behavior remains a
qualification gate. The documented parallel CLI is a separate workload tier;
use a single parser for the initial native comparison. [API][z-api]
[options][z-common] [README][z-readme]

The writer utility `zsv_writer_cell` accepts pointer+length and can check quoting,
but its pinned implementation emits LF, has no CRLF option in its options
structure, and writes empty cells without establishing Goose's zero-vs-one-empty
row distinction. Do not pass parser-derived quote flags or use
`zsv_writer_row_raw` for a generic encoder benchmark. Prefer zsv initially as an
additional parser result; if its writer is included, publish an LF/native-output
tier or an explicit canonicalizing adapter with its cost. Do not transform every
LF byte in the sink to CRLF: quoted LF bytes are field data.
[writer API][z-writer] [writer source][z-writer-source]

### CPython reference

Pin the actual interpreter, not just `csv.py`: the codec implementation is in
`Modules/_csv.c`. Use `csv.reader(..., strict=True, doublequote=True,
skipinitialspace=False)` over physical text lines with newline translation
disabled; use `csv.writer(..., lineterminator='\r\n', quoting=csv.QUOTE_MINIMAL)`.
Python returns owned lists/Unicode strings and distinguishes blank rows, sole
empty fields and trailing empties. Set and record `csv.field_size_limit`; this
is a character limit, not Goose's four byte budgets. `line_num` counts physical
input lines, not records or offending-byte offsets. [manual][p-doc]
[implementation][p-source]

Strict Python still accepts a quote inside an unquoted field (`IN_FIELD` treats
it as ordinary data); bare CR is a terminator. It is an oracle only for the
shared valid dialect. Arbitrary chunks cannot be passed as successive iterable
strings: the parser injects an end-of-line sentinel after each item. For an
opaque-byte reference, Latin-1 decode/encode is a possible reversible mapping,
but the line splitter must split only CSV physical CR/LF, not Unicode
`splitlines()`'s additional separators. Include conversion/framing cost or label
it explicitly; do not compare decoded Unicode throughput directly to byte
throughput. [C state machine and iterator][p-source] [manual][p-doc]

## Arrow and DuckDB: batch-tier context

Arrow C++ exposes `TableReader`, batch `StreamingReader`, `WriteCSV` and
`MakeCSVWriter`. Its pinned header says `StreamingReader` is single-threaded
regardless of `use_threads`, while `TableReader` supports the CPU thread pool.
Use explicit binary column types, `newlines_in_values=true`, no inferred header,
no null-string conversion, no dictionary encoding, and explicit writer
`include_header=false`, `eol="\r\n"`. Blank lines are ignored by default;
disabling that means one empty value, not a zero-field record. Fixed-schema
batches and conversion options make it a different output contract. Block size
is not Goose's wire-row budget. Keep schema setup/materialization, batch latency,
thread counts, and row-to-column conversion in the reported timing scope.
[reader header][a-reader] [options][a-options] [writer API][a-writer]

DuckDB's selected release has CSV read options for explicit schema/dialect,
`auto_detect`, `strict_mode`, `parallel`, `ignore_errors`, `nullstr`, newline and
maximum-line size, and CSV output via the engine. For an optional engine tier,
disable inference, headers, ignored errors, null padding and unintended NULL
conversion; supply VARCHAR columns, fix newline/quote/escape settings, and use
one thread before a separately labeled parallel run. Its default encoding is
UTF-8 and its maximum-line setting is documented in source as a guaranteed
successful length that may accept slightly longer lines, not an exact Goose
wire budget. Confirm byte/NULL/blank behavior before claiming shared semantics.
Time the whole engine operation with equivalent materialized output; a
`COUNT(*)` over selected columns is not an owned decoded-row benchmark.
[options header][d-options] [option parsing][d-options-source]
[CSV output source][d-writer]

These batch/engine APIs are useful context for large-file analytics, not
mandatory dependencies for a byte-stream library comparison. No throughput
number from an upstream README, paper or product benchmark is imported as a
result for this repository.

## Workload tiers and acceptance gates

1. **Native valid-data owned rows.** One thread, byte APIs, no headers/types,
   identical materialized row checksum and byte accounting. Feed all existing
   fixtures/chunk cases; report unsupported/divergent cases individually. A
   narrower shared-data subset may have its own ranking, but must disclose blank
   records/BOM/newline/encoding exclusions. Keep empty input and EOF completion.
2. **Native encoding.** Start from identical decoded byte fields. Separate
   canonical CRLF/minimal quoting from quote-all/native-output tiers. Include
   sink writes/flush and require output bytes/checksums, not just an estimated
   length. Report per-row output availability separately from amortized buffered
   output. Input record construction should have the same timing boundary.
3. **Contract compatibility.** Evaluate malformed quotes, CRLF-only/default
   newline behavior, every boundary split, zero/one/trailing-empty semantics,
   opaque bytes/BOM, exact/zero/hard limits, precise offsets, output preservation,
   EOF/repeated-finish and sticky errors. Unsupported native features stay
   unsupported. Any strict-validator, limit or atomic-output wrapper is named,
   checked and timed as its own implementation; no redundant validation is
   added solely to handicap a native valid-data baseline.
4. **Borrowed/scanning/parallel/batch.** Keep zero-copy views, line splitting,
   structural scans, projection/count-only paths, Arrow batches and DuckDB engine
   runs separate. Retaining output, UTF-8 checks, conversion, I/O, startup and
   parallelism must be stated; these runs cannot rank as equivalent owned-row
   codec implementations.

These are proposed adapters/gates under the [comparison contract](../bench/compare/CONTRACT.md),
not new tests or a timing campaign. Before conclusions, the implementing owner
must qualify API assumptions with executable checks, record exact lockfiles,
compiler/CPU/flags, check complete decoded/output parity and measure dispersion.
The source review gives credible candidates for both directions; it supplies no
basis for claiming universal SOTA or changing Goose's released semantics.

## Primary sources

All repository links below are pinned unless explicitly identified as registry
lookup, release metadata or versioned documentation.

[r-reg]: https://crates.io/api/v1/crates/csv
[c-reg]: https://crates.io/api/v1/crates/csv-core
[s-reg]: https://crates.io/api/v1/crates/simd-csv
[r-manifest]: https://github.com/BurntSushi/rust-csv/blob/4a3997e91d668ea1d8595bdef15625a77cf2308a/Cargo.toml
[c-manifest]: https://github.com/BurntSushi/rust-csv/blob/a0a3c9e4b493c216fb6d8284c9ac918444ba67f3/csv-core/Cargo.toml
[r-reader]: https://docs.rs/csv/1.4.0/csv/struct.Reader.html
[r-reader-source]: https://github.com/BurntSushi/rust-csv/blob/4a3997e91d668ea1d8595bdef15625a77cf2308a/src/reader.rs
[r-writer-source]: https://github.com/BurntSushi/rust-csv/blob/4a3997e91d668ea1d8595bdef15625a77cf2308a/src/writer.rs
[c-reader]: https://docs.rs/csv-core/0.1.13/csv_core/struct.Reader.html
[c-reader-source]: https://github.com/BurntSushi/rust-csv/blob/a0a3c9e4b493c216fb6d8284c9ac918444ba67f3/csv-core/src/reader.rs
[c-writer-api]: https://docs.rs/csv-core/0.1.13/csv_core/struct.Writer.html
[c-writer-source]: https://github.com/BurntSushi/rust-csv/blob/a0a3c9e4b493c216fb6d8284c9ac918444ba67f3/csv-core/src/writer.rs
[l-header]: https://github.com/rgamble/libcsv/blob/b1d5212831842ee5869d99bc208a21837e4037d5/csv.h
[l-manual]: https://github.com/rgamble/libcsv/blob/b1d5212831842ee5869d99bc208a21837e4037d5/csv.3
[l-source]: https://github.com/rgamble/libcsv/blob/b1d5212831842ee5869d99bc208a21837e4037d5/libcsv.c
[l-license]: https://github.com/rgamble/libcsv/blob/b1d5212831842ee5869d99bc208a21837e4037d5/COPYING
[s-manifest]: https://github.com/medialab/simd-csv/blob/df2cceb3bfe0427efc63fa213392f8c5b2713b47/Cargo.toml
[s-toolchain]: https://github.com/medialab/simd-csv/blob/df2cceb3bfe0427efc63fa213392f8c5b2713b47/rust-toolchain.toml
[s-reader]: https://github.com/medialab/simd-csv/blob/df2cceb3bfe0427efc63fa213392f8c5b2713b47/src/reader.rs
[s-core]: https://github.com/medialab/simd-csv/blob/df2cceb3bfe0427efc63fa213392f8c5b2713b47/src/core.rs
[s-records]: https://github.com/medialab/simd-csv/blob/df2cceb3bfe0427efc63fa213392f8c5b2713b47/src/records.rs
[s-writer]: https://github.com/medialab/simd-csv/blob/df2cceb3bfe0427efc63fa213392f8c5b2713b47/src/writer.rs
[s-error]: https://github.com/medialab/simd-csv/blob/df2cceb3bfe0427efc63fa213392f8c5b2713b47/src/error.rs
[s-searcher]: https://github.com/medialab/simd-csv/blob/df2cceb3bfe0427efc63fa213392f8c5b2713b47/src/searcher.rs
[s-readme]: https://github.com/medialab/simd-csv/blob/df2cceb3bfe0427efc63fa213392f8c5b2713b47/README.md
[z-pin]: https://api.github.com/repos/liquidaty/zsv/commits/2e2181930f68b6b83da69eb19d24636393d15408
[z-license]: https://github.com/liquidaty/zsv/blob/2e2181930f68b6b83da69eb19d24636393d15408/LICENSE
[z-build]: https://github.com/liquidaty/zsv/blob/2e2181930f68b6b83da69eb19d24636393d15408/BUILD.md
[z-api]: https://github.com/liquidaty/zsv/blob/2e2181930f68b6b83da69eb19d24636393d15408/include/zsv/api.h
[z-common]: https://github.com/liquidaty/zsv/blob/2e2181930f68b6b83da69eb19d24636393d15408/include/zsv/common.h
[z-fast]: https://github.com/liquidaty/zsv/blob/2e2181930f68b6b83da69eb19d24636393d15408/src/zsv_scan_delim_fast.c
[z-readme]: https://github.com/liquidaty/zsv/blob/2e2181930f68b6b83da69eb19d24636393d15408/README.md
[z-writer]: https://github.com/liquidaty/zsv/blob/2e2181930f68b6b83da69eb19d24636393d15408/include/zsv/utils/writer.h
[z-writer-source]: https://github.com/liquidaty/zsv/blob/2e2181930f68b6b83da69eb19d24636393d15408/app/utils/writer.c
[p-doc]: https://docs.python.org/3.14/library/csv.html
[p-source]: https://github.com/python/cpython/blob/b703b2c5e704341d61e367b9b940b77ed11dded0/Modules/_csv.c
[p-pin]: https://api.github.com/repos/python/cpython/commits/v3.14.10
[p-license]: https://github.com/python/cpython/blob/b703b2c5e704341d61e367b9b940b77ed11dded0/LICENSE
[a-tag]: https://api.github.com/repos/apache/arrow/git/ref/tags/apache-arrow-26.0.1
[a-license]: https://github.com/apache/arrow/blob/9e5d6978e9acf372cc989aaaf94e863fe8582c90/LICENSE.txt
[a-reader]: https://github.com/apache/arrow/blob/9e5d6978e9acf372cc989aaaf94e863fe8582c90/cpp/src/arrow/csv/reader.h
[a-options]: https://github.com/apache/arrow/blob/9e5d6978e9acf372cc989aaaf94e863fe8582c90/cpp/src/arrow/csv/options.h
[a-writer]: https://github.com/apache/arrow/blob/9e5d6978e9acf372cc989aaaf94e863fe8582c90/cpp/src/arrow/csv/writer.h
[d-release]: https://api.github.com/repos/duckdb/duckdb/releases/tags/v2.0.0
[d-license]: https://github.com/duckdb/duckdb/blob/d54cbbe3df17e8e5ce68312f483b4155836112aa/LICENSE
[d-options]: https://github.com/duckdb/duckdb/blob/d54cbbe3df17e8e5ce68312f483b4155836112aa/src/include/duckdb/execution/operator/csv_scanner/csv_reader_options.hpp
[d-options-source]: https://github.com/duckdb/duckdb/blob/d54cbbe3df17e8e5ce68312f483b4155836112aa/src/execution/operator/csv_scanner/util/csv_reader_options.cpp
[d-writer]: https://github.com/duckdb/duckdb/blob/d54cbbe3df17e8e5ce68312f483b4155836112aa/src/common/csv_writer.cpp

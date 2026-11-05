# CSV validation — 2026-11-05

Validated module, tests and measurement tooling:
`e17b37d6864c3f4cacc56108880e29a865907e42`, clean working tree. Raw evidence,
this record and publication links were added afterward without changing runtime
sources. Hosted CI independently repeats correctness and benchmark smoke.

The [public matrix log](../tests/results/2026-11-05/public.log) records passing
API regressions, 3,716 differential/contract oracle cases and 10,000 seeded
mutation/property cases in each of JIT, debug JIT and compiled native modes.
Independent [oracle records](../tests/results/2026-11-05/oracle-native.json)
retain seed, corpus/expected/output hashes, actual mode/executable identity and
Python version. Corpus SHA256:
`b4a7baf25fcac684e05810d10e55d57b2fe4cad929f780cb32c081a436136fb6`.

The differential corpus uses independent Python standard-library csv for shared
dialect parsing/encoding. Deliberately stricter malformed/limit expectations are
separate contract cases, not a claim that Python rejects every unsupported form.
Latin-1 is only a reversible byte/str bridge, not encoding validation.

Public API checks cover paired chunk split points (including CRLF/escaped quotes
and multibyte data), blank versus quoted-empty rows, EOF/terminal misuse, sticky
errors/positions, zero/exact/above-ceiling options, reset and retained output,
ordinary permitted writer aliases and atomic retry. Actual 16 MiB decoded fields
and 65,536-field rows succeed at their ceilings; one-byte/one-field excess fails
without replacing previous output. Whole-input validity requires finish/End.

The fuzz driver uses seed 81297 and generates bounded mutations with randomized
small limits. It compares full, one-byte and random-chunk parsing and roundtrips
accepted rows; output preservation and sticky status are checked. Final checksum
`1172115575` matches across the tested modes. This is finite seeded public-interface
fuzzing, not coverage-guided fuzzing or a percentage-coverage claim.

[GCC ASan/UBSan](../tests/results/2026-11-05/gcc-sanitize.json) and
[Clang ASan/UBSan](../tests/results/2026-11-05/clang-sanitize.json) each passed native
API and debug API, the 3,716-case oracle and 10,000-case fuzz driver. Fresh compiler
wrappers instrument actual generated Goose/runtime C with trailing
`-O1 -g -fno-omit-frame-pointer -fsanitize=address,undefined -UNDEBUG`. Program
output targets, flags and binary identities are checked. Oracle stderr is rejected
even on exit zero. Installed system libraries are not sanitizer-instrumented.

All source/tool identities are frozen before and checked after attributed runs;
binary hashes and exact per-invocation compiler commands are retained. All 24
recorded repository source hashes were independently compared with Git objects.
Initial direct-C compiler-attribution assumptions were corrected before final
records; rejected early records are not this evidence.

Environment: Linux x86-64/glibc, GCC 16.2.1 and Clang 23.1.4. Goose revision
`eadca409f68210893f366e60d0c2f0dc29a339be`; raw records include executable hashes,
versions and actual affinity. No external CSV/native source dependency is used.

## Initial performance baseline

[Raw observations](../bench/results/2026-11-05/raw.json) retain six fixture families,
15 ordered parse/write cases per sample, five full samples (75 observations) plus
warmup. Fixtures include 1/64/4096/65536-byte input chunks, quoted delimiters and
line breaks, many empty fields, UTF-8/high/NUL bytes and a 256 KiB field. Bounded
batches repeat; the benchmark does not allocate a whole large input file.

Actual `-O2 -UNDEBUG` compiler invocations, source/tool/binary/fixture hashes,
consumed/emitted byte/row counts and data-derived signatures are recorded. Native
case timings and process wall times are distinct. Full fixture bytes match Python
csv and full parsed setup/final fields/output are checked. See
[methodology](../bench/README.md). Child CPU4 affinity was best effort on a shared
host, with no exclusive/isolation claim. No samples were dropped. There is no
comparator, universal ranking, hard RSS promise or CI timing threshold.

## Review and limits

Independent interface and security reviews preceded implementation. Later code,
test-quality and performance-methodology reviews found no remaining blocker after
fixes. Reviews corrected root-owner/copy/swap assumptions, alias wording, terminal
misuse semantics, typed empty fields and diagnostic/provenance claims. This is
finite Linux validation, not certification. Root state must not be modified or
deserialized; caller encoding, I/O and spreadsheet policy remain explicit. Parent
and sibling pins/source are unchanged.

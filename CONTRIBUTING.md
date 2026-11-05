# Contributing

Keep the module pure, small, bounded and explicit. Applications own I/O, encoding,
headers, field types and spreadsheet policy. Preserve the documented dialect,
root ownership, raw/decoded accounting, error positions and failure atomicity.
No native accelerator without profiling and a reviewed portable Goose fallback.

Use focused branches and Conventional Commits with imperative subjects. Commit
one coherent change at a time. No compatibility promise before 1.0. Never commit
credentials, binaries, generated compiler output, toolchains or private notes.

Behavior changes require public-interface regressions for malformed input, every
relevant chunk split, limits, EOF/sticky lifecycle, row retention and writer retry.
Run `make format check test test-debug`, `make sanitize SANITIZER_CC=gcc` and
`make sanitize SANITIZER_CC=clang`. Oracle comparisons must distinguish intentional
CSV dialect differences; seeded mutation fuzzing is not coverage-guided fuzzing.
Request repeated independent correctness, security, performance and test-quality
reviews, fix findings and keep CI passing. CI checks formatting without repairing
source. Compiler changes require a reviewed full upstream pin and full validation.

Profile before optimizing. Preserve every benchmark fixture and raw sample with
exact source/compiler/binary/flags/platform/affinity provenance and limitations.
No timing thresholds in CI, exclusive-host claims or universal superiority from
microbenchmarks. Report vulnerabilities privately; see SECURITY.md.

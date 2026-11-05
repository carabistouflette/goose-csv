# CSV comparison review record

Historical review record. Current user documentation starts at the [README](../README.md).


Independent AI reviewers worked read-only on separate adapter fairness, safety,
measurement, qualification, production security/quality and final publication
reviews. The implementation owner made fixes and ran the gates. Reviews are
finite engineering checks, not certification or a proof of universal performance.

The initial adapter/tooling findings and closures are recorded in
[bench/compare/REVIEWS.md](../bench/compare/REVIEWS.md). Later review checkpoints:

- Production grammar/accounting: ordinary runs stop at syntax and every budget;
  error bytes remain excluded, row/field coordinates and sticky state are retained.
  Shared scalar transitions handle boundary bytes. Expanded public regressions
  cover exact limits, prior rows and writer retry. Writer combined budget checks
  retain the released RowLimit-before-TotalLimit classification.
- Ownership/cursor review: compute consumed counts before replacing the output
  Row. Keep the bulk tail local because passing its shrinking slice alongside
  mutable output loses the compiler's borrow proof. No alias checks were disabled.
- Performance/caller review: instruction profiles identified a benchmark wrapper
  inlining interaction. Both baseline/candidate entry wrappers are explicitly
  inlined in a separate optimized native caller tier. Earlier caller regressions
  remain real observations for that arrangement. Fresh matching A/A controls
  precede this tier; no competitor copies/checks were added to slow it down.
- Compiler gate: forcing all writer call sites inline exceeded the unchanged
  300-second GCC sanitizer compilation gate. That variant was rejected; its
  failure receipt remains published. The retained source passes both compilers.
- Initial-prefix dispatch review: no semantic/security blocker. A short leading
  field can keep a later long field scalar. This limitation is explicit rather
  than generalized from the long-first-field fixture. Independent chunk63/64/65,
  remaining field31/32/33 and raw/total63/64/65 probes were added, with quoted/plain
  input and prior rows. Existing escaped-quote cases cross the shifted quoted
  prefix boundary. The unused scalar base parameter was removed.
- Reporting review: bind all pooled passes to source, tool/build/control receipts,
  generated C/executable sections and alternative executable identities. Require
  each complete case/engine/sample matrix, reject duplicate records/journals, and
  bind validation prose to distinct GCC/Clang plus JIT/debug/native and frozen
  scalar evidence. SIMD BOM behavior is labeled chunk-dependent. Missing,
  duplicate and changed-alternative probes are rejected by the renderer.

Final publication reviews independently verified all 150 evidence-file hashes
and sizes, 48 measured Git source blobs, dependency/build/control/journal links,
validation receipts and all 150 pooled summary cells. Each summary contains21
samples from three distinct 1,050-observation passes. Both final reviewers found
no remaining blocker after the duplicate-pass fix. The standalone chart
reproduces byte-for-byte from the committed raw records.

Measured production/tests/harness source is
`0376fece8625827d6ef2754d48d40df8204ec24f`. Later publication changes add reports,
not a new runtime variant. The [report](COMPARISON.md) retains all cases, ranges,
regressions, rejected trials and the limits of the evidence. No benchmark-derived
release tag, parent pin or application adoption is performed here.

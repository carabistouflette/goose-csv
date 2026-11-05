# Comparison tooling reviews

Historical review record. Current user documentation starts at the [README](../../README.md).


2026-11-05, before any comparative performance claim or production optimization.
Independent reviewers read the controlled benchmark adapters and methodology;
none wrote production source, ran timing or changed release/parent pins.

- Adapter fairness: replaced artificial Rust `Rc<RefCell>` access with an owned
  reusable sink whose flush observes complete per-row output. Required terminated
  repeated streams; EOF-only/error probes stay single-repetition. Confirmed pinned
  csv-core cumulative ends and partial-output driving against native APIs.
- Adapter safety/ownership: no blocking controlled-input bounds issue. Required
  complete dumped output checks, buffer/field-end growth and byte accounting only
  at successful EOF. C field callback data is copied before return.
- Qualification: added >65 KiB escaped fields crossing output/internal buffers.
  Added independent emitted-row/checksum checks and explicit full-input markers
  so premature native EOF is visible instead of described merely as BOM removal.
- Measurement/provenance: resolved and invoked actual Cargo/rustc binaries rather
  than hashing rustup shims; made profile/wrapper/incremental settings explicit,
  retained effective compiler commands/config hashes, and verified source files
  against exact crate archives. Bound alternative executables to build receipts.
  Added immutable output paths, per-observation JSONL journaling with incomplete
  reasons, and before/after fixture/build/control receipt checks.

These reviews cover the harness, not an optimization acceptance or a universal
feature/performance ranking. Public API oracle/fuzz/sanitizer evidence remains
required for any later production change.

# Third-party notices

No third-party runtime source or native backend is vendored. The separately
fetched pinned Goose compiler and standard library retain their source licenses.

The dialect uses common comma/double-quote conventions described in
[RFC4180](https://www.rfc-editor.org/rfc/rfc4180), with explicit differences documented
in [DESIGN.md](docs/DESIGN.md). Tests use Python's standard-library csv as an independent oracle for
the shared dialect; Python source is not copied into this module.

See LICENSE for this repository's Apache-2.0 terms.

Optional comparison tooling downloads Rust csv 1.4.0 (Unlicense OR MIT),
csv-core 0.1.13 (Unlicense OR MIT), medialab/simd-csv 0.14.0 (MIT),
and libcsv 3.0.3 source b1d5212831842ee5869d99bc208a21837e4037d5
(LGPL-2.1-or-later). These are benchmark dependencies, not Goose library runtime
dependencies; no upstream source or linked executable is redistributed here.
The lockfile freezes transitive Rust dependencies. Exact source/archive hashes,
package licenses and compiler commands are in the
[build receipts](bench/results/comparison-2026-11-05/builds/); see the
[source-backed alternatives matrix](docs/ALTERNATIVES.md) for license links.

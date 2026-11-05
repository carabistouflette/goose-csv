# Documentation and benchmark source check

## Supported revisions

Alpha.2 is immutable at `60165e4053d4b2eaa01dc34b2fd3e7411558f0e1`.
This documentation update changes no production, example, test or timed adapter
code. Alpha.1 is the original scalar reader/writer; its baseline records are
historical. No release tag is moved by documentation changes.

## Examples checked

The README's exact public import was run with Goose
`eadca409f68210893f366e60d0c2f0dc29a339be`. The chunked reader/writer example
was run from the checkout, and `make check` passed. Reproduce with:

```sh
goose run main.goose  # save the README quickstart first
make check GOOSE=/path/to/the/pinned/goose
/path/to/the/pinned/goose run examples/stream.goose
```

The API/dialect/limits guide is [DESIGN.md](DESIGN.md). README, design, security,
contributing, notices, changelog, both benchmark guides, comparison/research and
validation pages were checked. Review logs and raw results remain historical
records, not setup instructions or new measurements.

## Why no timing rerun was needed

The final comparison measured `0376fece8625827d6ef2754d48d40df8204ec24f`.
The twelve files below match that commit, alpha.2 and this documentation checkout
byte for byte. This includes all timed adapters, fixture/protocol code, the
compiler pin and Rust dependency manifest/lockfile. Recorded Goose, GCC, Python,
Cargo and rustc executable SHA-256 values also match the available binaries.
The three final raw journals match their recorded hashes. The chart was rebuilt
from all 3,150 samples. No new timing was run or old sample relabeled.

| Checked file | SHA-256 |
| --- | --- |
| `GOOSE_REVISION` | `64e14b181dfe96743211738fb0f1b1f7798ea940da2ca50ff122e6f028c24e15` |
| `bench/compare/build.py` | `3fb4b73126d46a9e936b3451e3a9bd398cf8d870908da2c0a759e2f596d67b89` |
| `bench/compare/driver.goose` | `74a44304d6c65ac9059652ce91c7f1bd9172a09b523b758da71c67437ca8fb94` |
| `bench/compare/fixtures.py` | `c45a7bc7194cab0a388728f2d6acabf2adf7e18e5c194e2507b32214cb7b9c7f` |
| `bench/compare/libcsv_driver.c` | `890ae819ca50ec29bb5209f2c8768b2345a9c4f082522d591307ef7461f146fc` |
| `bench/compare/measure.py` | `0cddaa08a7f36c639fc2295b0b88e39f3093f87c673673723fbff355d98c6f2f` |
| `bench/compare/qualify.py` | `70c00192014f63203bba8da768119286c56edf6b8b12286a54c42ce239752aae` |
| `bench/compare/rust/Cargo.lock` | `aba4e9f1b0fbed3246fdf9b58175d1e34c575251b4fbbd28de9c805e7c1f196a` |
| `bench/compare/rust/Cargo.toml` | `50f94e83dcf7fad7c60fb697018c9f3083f7c441648c1e1e7786e8b4c519dc6a` |
| `bench/compare/rust/src/main.rs` | `8ed55eb200d143f90802fcd8c51dcf2d195096634029c3043e44d61625535281` |
| `csv.goose` | `40d10abdd89761f3fb7b24a74160b14a090ad1e851201df8df33a1be4ce7efc1` |
| `tests/support.goose` | `73feaaeeff180514d4bfe3144ed20132bcfe5d8456e44b3f381f080f0e5bcbbf` |

Check the code bridge from a full clone:

```sh
git diff --exit-code 0376fece8625827d6ef2754d48d40df8204ec24f HEAD -- \
  csv.goose GOOSE_REVISION tests/support.goose bench/compare/driver.goose \
  bench/compare/build.py bench/compare/fixtures.py bench/compare/measure.py \
  bench/compare/qualify.py bench/compare/libcsv_driver.c \
  bench/compare/rust/Cargo.toml bench/compare/rust/Cargo.lock \
  bench/compare/rust/src/main.rs
```

[COMPARISON.md](COMPARISON.md) retains machine/OS/toolchain, full workloads, units,
calibration/repeats, raw data and ranges. Its older caller tier stays separate.
The six-fixture alpha.1 baseline is explicitly historical. Small shared-host
changes, short-row regressions, native contract gaps and unmeasured allocator/RSS
behavior remain limitations. The results do not predict another compiler/host.

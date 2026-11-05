# CSV comparison and optimization contract

User target: goose-csv reader AND writer, feature coverage and performance against
credible alternatives, then maximize measured performance without weakening the
released public contract. Frozen baseline/release/parent pin:
4ec59cf17685f85e537cac264527d28af8ab9f2f (v0.1.0-alpha.1).
No source/pin/tag changes in sibling libraries or the parent checkout/index.

## Comparison gates

Publish an explicit feature matrix from primary sources and executable checks:
streaming/chunk boundaries, owned/borrowed output, opaque bytes/UTF-8, quoted
multiline/escaped quotes, blank rows/sole empty/trailing empty, strict malformed
quotes/CRLF+LF policy, limits/error coordinates, failure atomicity/lifecycle,
reader/writer support, memory/allocation behavior, native/platform/parallelism.
Do not add features merely to match unrelated dataframe/type-inference products.

Pin actual alternative source versions/commits, lockfiles and licenses. Include a
mature low-level streaming baseline and a credible optimized/SIMD contender where
its interface/build permits meaningful comparison. Keep ubiquitous reference
implementations separate from claims about the performance frontier.

Separate workload tiers and unavailable semantics explicitly. A valid-data core
throughput test is not equivalent to the complete bounded/strict public contract.
Do not silently remove goose-csv validation or make competitor adapters do redundant
work just to slow them down. Comparable owned-row tests include decoded materialization,
complete byte/row accounting, identical checksums/EOF and equivalent timing scope.
Chunk sizes, data formats, UTF-8 checks, buffer reuse, encoding/output latency,
thread counts and optional normalization must be aligned or disclosed. Unsupported
features remain visible; no convenient corpus exclusions are hidden.

## Measurement and optimization

Reuse all existing six fixtures and chunk-size cases, extend with reviewed realistic
and adversarial distributions, vary data to resist compiler elision and validate
identical decoded rows/output independently. Retain old data unchanged. Calibrate
work duration; build baseline/candidate at the same source/build paths, retain
binary/section/source/compiler/flags/CPU/affinity hashes. Use paired/alternating
order plus identical-code A/A controls before interpreting marginal differences.
All samples, dispersion and per-fixture regressions must be retained. No global
winner claim from aggregate-only numbers, throughput with different semantics,
shared-host noise or unrelated cross-language process startup.

Profile released behavior before modifying hot paths. Pure Goose optimizations
first; a private native accelerator requires measured need, portable fallback,
independent interface/security review and differential parity at every split/error/
limit/lifecycle boundary. Never drop malformed-input rejection, output preservation,
resource limits or precise offsets for a benchmark win. Keep the simple implementation
as a reference where useful. Run oracles, seeded mutation, real hard-ceiling and
GCC/Clang generated/native sanitizers for accepted behavioral implementations.
SOTA is a measured, scoped conclusion, not a promise made before results exist.

Independent reviews must examine feature comparability, adapter fairness, generated
code attribution, ownership/security, methodology and every optimization acceptance.
Coordinate shared-host timing as courtesy only; no host settings or exclusivity claim.

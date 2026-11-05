# Changelog

## Unreleased

Documentation cleanup and checked example/benchmark source links.

## v0.1.0-alpha.2

Bounded run scanning and writer quote/escape plans. Long-field throughput improves
in the recorded workloads; several short-field readers are slower than alpha.1.
See [the comparison](docs/COMPARISON.md) for all cases and limits.

## v0.1.0-alpha.1

Initial byte-stream reader/writer: strict quoting, explicit newline policy,
owned rows, field/row/total/field-count limits, errors and atomic writer retry.

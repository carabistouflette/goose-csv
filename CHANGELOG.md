# Changelog

## Unreleased

Bounded ordinary-run reader scanning and writer quote/escape plans improve
long-field throughput while retaining strict grammar, exact budgets and atomic
writer retry. Short-field reader regressions and native alternative differences
are explicit in [the comparison report](docs/COMPARISON.md); no universal speedup
or SOTA ranking is established. Pinned optional benchmark adapters, feature
probes, matched-path controls and every timing trial accompany the report.

Initial experimental pure Goose streaming reader/writer with strict quoting,
explicit newline policy, owned rows, bounded field/row/total/field-count state,
precise reader errors, explicit EOF and atomic bounded writer rows.

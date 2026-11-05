# Third-party notices

No third-party runtime source or native backend is vendored. The separately
fetched pinned Goose compiler and standard library retain their source licenses.

The dialect uses common comma/double-quote conventions described in
[RFC4180](https://www.rfc-editor.org/rfc/rfc4180), with explicit differences documented
in [DESIGN.md](docs/DESIGN.md). Tests use Python's standard-library csv as an independent oracle for
the shared dialect; Python source is not copied into this module.

See LICENSE for this repository's Apache-2.0 terms.

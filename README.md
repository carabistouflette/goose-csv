# goose-csv

Bounded streaming CSV reader/writer for Goose. Pure Goose, Apache-2.0.
Experimental interface; initially Linux x86-64 validation. No stability promise
before 1.0. Applications own I/O, encoding, headers, types and spreadsheet policy.

```goose
import csv from "carabistouflette/goose-csv@e17b37d6864c3f4cacc56108880e29a865907e42";
import std;
fn main() {
    var reader = csv::Reader { .. };
    var row = csv::Row { .. };
    assert(csv::init(reader).error == csv::Error.None);
    let result = csv::read(reader, "a,\"b,c\"\r\n", row);
    assert(result.step == csv::Step.Row && result.consumed == 9);
    assert(csv::field_count(row) == 2 && csv::field(row, 1) == "b,c");
    assert(csv::finish(reader, row).step == csv::Step.End);
}
```

Declare the package in the application root; no other source dependencies.
See [complete reader/writer example](examples/stream.goose) and
[precise interface/dialect/limits](docs/DESIGN.md).

| Operation | Result |
| --- | --- |
| `init(reader, limits, allow_lf)` | Initialize/reset; defaults supported |
| `read(reader, chunk, row)` | Progress(step, consumed, status), at most one Row |
| `finish(reader, row)` | EOF: final unterminated Row, then End |
| `field_count(row)` / `field(row, index)` | Count / zero-based in-range borrowed view |
| `init(writer, limits)` | Initialize/reset Writer |
| `write(writer, fields, output)` | Replace output with one complete CRLF row |

Resume at chunk[consumed..] after Row. NeedInput consumes the chunk; empty chunks
are valid. Row output changes only on Row. Reader errors are sticky until init;
nonempty read after End is also sticky InvalidState. Repeated finish/read(empty)
return End. Finish all input successfully before claiming whole-input validity.

Reader, Writer and Row are root owners, not copyable/nestable/returnable values.
Retain a row by leaving its owner untouched. Views can change or become invalid
when its Row is reused. Input must not borrow output Row or Reader internals.
Goose permits aliases; do not assume every disallowed alias is caught statically.
Do not modify internal fields. Writer preflight failures preserve state/output
for retry; bounded scratch protects ordinary permitted input/output aliases.
Use explicitly typed byte-view fields, and csv::NO_FIELDS for zero fields.

Comma/double-quote/doubled-quote dialect: exact spaces, quoted CR/LF preserved,
outside CRLF or default LF-only (allow_lf=false selects CRLF-only), no bare CR or
quote recovery. EOF can end the last row. Blank record has zero fields, quoted
empty has one, trailing comma adds an empty field, trailing ending adds no row.
Writer emits CRLF and quotes a sole empty field. Bytes are opaque, including NUL
and high bytes. No BOM removal/UTF-8 validation or spreadsheet formula rewriting.
See [RFC4180](https://www.rfc-editor.org/rfc/rfc4180) for common quoting conventions;
our byte/newline/empty-row differences are explicit in the design.

| Limits | Default | Hard maximum |
| --- | --- | --- |
| Decoded field bytes | 1 MiB | 16 MiB |
| Wire row bytes, including quotes/delimiters/ending | 4 MiB | 64 MiB |
| Total accepted/emitted wire bytes per instance | 64 MiB | 2^60 |
| Fields per row | 4096 | 65536 |

Zero limits are valid; invalid options preserve old state. Status has error,
zero-based absolute wire offset and one-based record/field. Reader offending
bytes are excluded from consumed; EOF offset is one past accepted input. Writer
offset is start of the unwritten row. Success coordinates/error precedence are
unspecified. Canonical output may require more wire bytes than LF/EOF input.

Storage is current-row plus caller output with completed-row component copies;
writer preflights then scratch-encodes and copies output. Work is linear in bytes
and fields. No whole-file queue or O(1) ownership-swap promise. Logical limits are
not exact allocator/RSS guarantees: prior limits/capacity and runtime high-water
storage matter. Allocation failure follows Goose runtime behavior.

Development: pinned Goose (GOOSE_REVISION), CMake >=3.27, C/C++20 toolchain, Make,
Python >=3.11 and Clang. No pip/runtime packages. Use GOOSE=PATH for an existing
matching compiler. Run `make setup`, `make format check test test-debug`, both
GCC/Clang `make sanitize SANITIZER_CC=...`, and `make bench`.

See [contributing](CONTRIBUTING.md), [security](SECURITY.md),
[notices](THIRD_PARTY_NOTICES.md). See [validation](docs/VALIDATION.md) and [baseline methodology](bench/README.md)
for exact tested sources, corpus, compilers, measurements and limitations.

# goose-csv

Read CSV from byte chunks and write complete CSV rows in Goose. The reader keeps
one unfinished row; the writer checks limits before replacing your output.
Pure Goose, Apache-2.0.

Experimental API, tested on Linux x86-64/glibc. The latest release is
[v0.1.0-alpha.2](https://github.com/carabistouflette/goose-csv/releases/tag/v0.1.0-alpha.2)
at `60165e4053d4b2eaa01dc34b2fd3e7411558f0e1`. Main adds documentation;
[the source check](docs/AUDIT.md) identifies which measured code is unchanged.
Alpha.1 uses the earlier scalar implementation; its results are separate.

## Quickstart

Install the Goose revision in [GOOSE_REVISION](GOOSE_REVISION), save this as
`main.goose`, then run `goose run main.goose`. Package imports belong in the
application's root source file.

```goose
import csv from "carabistouflette/goose-csv@60165e4053d4b2eaa01dc34b2fd3e7411558f0e1";
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

For chunked input and writing, see [examples/stream.goose](examples/stream.goose).
From a checkout with the pinned compiler, run:

```sh
make setup
.toolchain/goose/build/goose run examples/stream.goose
```

## API

| Operation | Result |
| --- | --- |
| `init(reader, limits, allow_lf)` | Initialize or reset the reader |
| `read(reader, chunk, row)` | Consume through at most one Row; return step, consumed count and status |
| `finish(reader, row)` | Signal EOF; possibly return a final Row, then End |
| `field_count(row)` / `field(row, index)` | Count fields / borrow an in-range field |
| `init(writer, limits)` | Initialize or reset the writer |
| `write(writer, fields, output)` | Replace output with one CRLF-terminated row |

After a Row, resume at `chunk[consumed..]`. NeedInput consumes the chunk. Output
changes only on Row. Finish the entire input successfully before treating the
whole file as valid. Reader errors remain until reset; writer errors preserve
state/output so a corrected row can be retried.

Reader, Writer and Row are noncopyable root owners. Field views belong to their
Row and may become invalid when it is reused. Input must not borrow output Row
or Reader internals; not every disallowed alias is caught by the compiler.
Use typed `csv::NO_FIELDS` for a zero-field row. Do not modify internal state.

## Format and limits

Comma separator, double quotes, doubled quote escapes. Quoted CR/LF and spaces
are preserved. Outside quotes, CRLF and default LF are accepted;
`allow_lf=false` requires CRLF. Bare CR and malformed quoting are errors.
Blank records have zero fields; quoted empty has one; trailing comma adds an
empty field. EOF may end a row. The writer emits CRLF.

Bytes are opaque, including NUL/high bytes. Applications handle encoding,
headers, types and spreadsheet formula safety; quoting alone does not make
formulas safe. See the [full contract](docs/DESIGN.md) for errors and ownership.

| Logical limit | Default | Hard maximum |
| --- | --- | --- |
| Decoded bytes per field | 1 MiB | 16 MiB |
| Wire bytes per row, including syntax/ending | 4 MiB | 64 MiB |
| Total accepted/emitted wire bytes | 64 MiB | 2^60 |
| Fields per row | 4096 | 65536 |

Zero limits are valid. Invalid options preserve state. Logical limits are not
allocator/RSS ceilings: retained capacity, previous output and runtime allocation
behavior matter. Completed rows and writer output are copied.

## Performance and development

The [comparison](docs/COMPARISON.md) includes slower cases: several short-field
readers are slower than alpha.1. Long-field gains depend on layout and caller
compilation. It reports the recorded machine/toolchain, every workload and sample
range; it does not establish a universal fastest CSV library or memory advantage.

For development, see [CONTRIBUTING.md](CONTRIBUTING.md). Tests and historical
records are described in [validation](docs/VALIDATION.md); benchmark commands are
in [bench/compare/README.md](bench/compare/README.md). See also
[security](SECURITY.md) and [third-party notices](THIRD_PARTY_NOTICES.md).

// SPDX-License-Identifier: Apache-2.0
import csv from "..";
import std;
fn expect(row: const csv::Row&, fields: const (const u8[:])[:]) {
    assert(csv::field_count(row) == fields.len);
    for i in fields.len { assert(csv::field(row, i) == fields[i]); }
}
fn image(row: const csv::Row&) -> u8[>..] {
    var out: u8[>..] = str(csv::field_count(row), ":");
    for i in csv::field_count(row) {
        let field = csv::field(row, i);
        out.append(str(field.len, ":")); out.append(field);
    }
    return out;
}
fn one_row(data: const u8[:], fields: const (const u8[:])[:], first: i64, second: i64) {
    var reader = csv::Reader { .. };
    var row = csv::Row { .. };
    assert(csv::init(reader).error == csv::Error.None);
    let cuts: i64[4] = [0, first, second, data.len];
    var rows: i64 = 0;
    for part in 3 {
        var at = cuts[part];
        while at < cuts[part + 1] {
            let before = image(row);
            let progress = csv::read(reader, data[at..cuts[part + 1]], row);
            assert(progress.status.error == csv::Error.None);
            assert(progress.consumed > 0 && progress.consumed <= cuts[part + 1] - at);
            at += progress.consumed;
            if progress.step == csv::Step.Row { expect(row, fields); rows++; }
            else {
                assert(progress.step == csv::Step.NeedInput && at == cuts[part + 1]);
                assert(image(row) == before);
            }
        }
        let before = image(row);
        let empty = csv::read(reader, "", row);
        assert(empty.step == csv::Step.NeedInput && empty.consumed == 0 && image(row) == before);
    }
    let done = csv::finish(reader, row);
    assert(done.status.error == csv::Error.None && done.consumed == 0);
    if done.step == csv::Step.Row { expect(row, fields); rows++; }
    else { assert(done.step == csv::Step.End); }
    assert(rows == 1);
    expect(row, fields);
    assert(csv::finish(reader, row).step == csv::Step.End);
    assert(csv::finish(reader, row).step == csv::Step.End);
    assert(csv::read(reader, "", row).step == csv::Step.End);
    expect(row, fields);
}
fn all_splits(data: const u8[:], fields: const (const u8[:])[:]) {
    for first in 0..data.len + 1 {
        for second in first..data.len + 1 { one_row(data, fields, first, second); }
    }
}
fn same_status(a: csv::Status, b: csv::Status) -> bool {
    return a.error == b.error && a.offset == b.offset && a.record == b.record && a.field == b.field;
}
fn failure(data: const u8[:], limits: csv::Limits, error: csv::Error,
           offset: i64, record: i64, field: i64, allow_lf: bool = true) {
    var reader = csv::Reader { .. };
    var seed = csv::Reader { .. };
    var row = csv::Row { .. };
    assert(csv::init(seed).error == csv::Error.None);
    assert(csv::read(seed, "sentinel\n", row).step == csv::Step.Row);
    assert(csv::init(reader, limits, allow_lf).error == csv::Error.None);
    var at: i64 = 0;
    var status = csv::Status { .. };
    var failed = false;
    var before: u8[>..] = [];
    while at < data.len {
        before = image(row);
        let progress = csv::read(reader, data[at..], row);
        assert(progress.consumed >= 0 && progress.consumed <= data.len - at);
        at += progress.consumed;
        if progress.step == csv::Step.Error { status = progress.status; failed = true; break; }
        assert(progress.status.error == csv::Error.None && progress.consumed > 0);
        if progress.step != csv::Step.Row { assert(image(row) == before); }
    }
    if !failed {
        before = image(row);
        let progress = csv::finish(reader, row);
        assert(progress.step == csv::Step.Error && progress.consumed == 0);
        status = progress.status;
    }
    assert(status.error == error && status.offset == offset && status.record == record && status.field == field);
    assert(at == offset && image(row) == before);
    let again = csv::read(reader, "arbitrary ignored bytes", row);
    assert(again.step == csv::Step.Error && again.consumed == 0 && same_status(again.status, status));
    let eof = csv::finish(reader, row);
    assert(eof.step == csv::Step.Error && eof.consumed == 0 && same_status(eof.status, status));
    assert(image(row) == before);
    assert(csv::init(reader).error == csv::Error.None);
    assert(csv::read(reader, "ok\n", row).step == csv::Step.Row);
    expect(row, ["ok"]);
}
fn run_checks() {
    let defaults = csv::Limits { .. };
    for n in [15, 16, 17, 31, 32, 33, 63, 64, 65, 255, 256, 257] {
        var plain: u8[>..] = []; for _ in n { plain.push('x'); }
        let fields: (const u8[:])[2] = [plain[..], "tail"];
        let one:    (const u8[:])[1] = [plain[..]];
        let wire = str(plain, ",tail\r\n");
        for point in [0, 15, 16, 17, n] {
            let cut = min(point, wire.len);
            one_row(wire, fields, cut, cut);
        }
        let quoted = str("\"", plain, "\"");
        one_row(quoted, one, n, n + 1);
        failure(str(plain, "\""), defaults, csv::Error.UnexpectedQuote, n, 1, 1);
        failure(str("\"", plain, "\"!"), defaults, csv::Error.AfterQuote, n + 2, 1, 1);
        failure(plain, csv::Limits { max_field_bytes: n - 1, .. }, csv::Error.FieldLimit, n - 1, 1, 1);
        failure(quoted, csv::Limits { max_field_bytes: n - 1, .. }, csv::Error.FieldLimit, n, 1, 1);
        failure(plain, csv::Limits { max_row_bytes: n - 1, .. }, csv::Error.RowLimit, n - 1, 1, 1);
        failure(plain, csv::Limits { max_total_bytes: n - 1, .. }, csv::Error.TotalLimit, n - 1, 1, 1);
        failure(plain, csv::Limits { max_field_bytes: n - 1, max_row_bytes: n - 1, max_total_bytes: n - 1, .. },
            csv::Error.TotalLimit, n - 1, 1, 1);
        failure(plain, csv::Limits { max_fields: 0, .. }, csv::Error.FieldCountLimit, 0, 1, 1);
    }
}
fn reader_checks() {
    all_splits("a,b\r\n", ["a", "b"]);
    all_splits("\"a\"\"b\",c\r\n", ["a\"b", "c"]);
    all_splits("\"a\r\nb\",é", ["a\r\nb", "é"]);
    all_splits("\"\",z\n", ["", "z"]);
    all_splits("\"\"", [""]);
    all_splits("\r\n", []);
    all_splits(",", ["", ""]);
    all_splits("a,", ["a", ""]);
    all_splits("a\r\n", ["a"]);
    let binary:        u8[8]            = ['"', 0, 255, 128, '"', ',', 254, '\n'];
    let first:         u8[3]            = [0, 255, 128];
    let last:          u8[1]            = [254];
    let binary_fields: (const u8[:])[2] = [first[..], last[..]];
    all_splits(binary, binary_fields);
    let defaults = csv::Limits { .. };
    failure("a\"b", defaults, csv::Error.UnexpectedQuote, 1, 1, 1);
    failure("\"a\"x", defaults, csv::Error.AfterQuote, 3, 1, 1);
    failure("a\rx", defaults, csv::Error.ExpectedLf, 2, 1, 1);
    failure("a\r", defaults, csv::Error.ExpectedLf, 2, 1, 1);
    failure("\"abc", defaults, csv::Error.UnclosedQuote, 4, 1, 1);
    failure("a,b\n\"x\"!", defaults, csv::Error.AfterQuote, 7, 2, 1);
    failure("a\n", defaults, csv::Error.UnexpectedLf, 1, 1, 1, false);
    failure("ab", csv::Limits { max_field_bytes: 1, .. }, csv::Error.FieldLimit, 1, 1, 1);
    failure("\"a\"\"b\"", csv::Limits { max_field_bytes: 1, .. }, csv::Error.FieldLimit, 3, 1, 1);
    failure("a,b\n", csv::Limits { max_row_bytes: 3, .. }, csv::Error.RowLimit, 3, 1, 2);
    failure("a\nb\n", csv::Limits { max_total_bytes: 3, .. }, csv::Error.TotalLimit, 3, 2, 1);
    failure("a,b", csv::Limits { max_fields: 1, .. }, csv::Error.FieldCountLimit, 1, 1, 2);
    failure("a", csv::Limits { max_field_bytes: 0, .. }, csv::Error.FieldLimit, 0, 1, 1);
    failure("a", csv::Limits { max_fields: 0, .. }, csv::Error.FieldCountLimit, 0, 1, 1);
    failure("a", csv::Limits { max_row_bytes: 0, .. }, csv::Error.RowLimit, 0, 1, 1);
    failure("a", csv::Limits { max_total_bytes: 0, .. }, csv::Error.TotalLimit, 0, 1, 1);
}
fn lifecycle_checks() {
    var reader = csv::Reader { .. };
    var row = csv::Row { .. };
    let inactive = csv::read(reader, "a", row);
    assert(inactive.step == csv::Step.Error && inactive.status.error == csv::Error.InvalidState && inactive.consumed == 0);
    assert(csv::finish(reader, row).status.error == csv::Error.InvalidState);
    assert(csv::init(reader).error == csv::Error.None);
    assert(csv::read(reader, "before", row).step == csv::Step.NeedInput);
    for invalid in [csv::Limits { max_fields: -1, .. }, csv::Limits { max_fields: 65537, .. },
                    csv::Limits { max_field_bytes: 16777217, .. }, csv::Limits { max_row_bytes: 67108865, .. },
                    csv::Limits { max_total_bytes: 1152921504606846977, .. },
                    csv::Limits { max_field_bytes: -1, .. }, csv::Limits { max_row_bytes: -1, .. },
                    csv::Limits { max_total_bytes: -1, .. }, csv::Limits { max_total_bytes: 9223372036854775807, .. }] {
        assert(csv::init(reader, invalid).error == csv::Error.InvalidOptions);
    }
    assert(csv::finish(reader, row).step == csv::Step.Row);
    expect(row, ["before"]);
    assert(csv::finish(reader, row).step == csv::Step.End);
    let misuse = csv::read(reader, "x", row);
    assert(misuse.step == csv::Step.Error && misuse.status.error == csv::Error.InvalidState && misuse.consumed == 0);
    assert(same_status(csv::finish(reader, row).status, misuse.status));
    expect(row, ["before"]);
    let zero = csv::Limits { max_field_bytes: 0, max_row_bytes: 0, max_total_bytes: 0, max_fields: 0 };
    assert(csv::init(reader, zero).error == csv::Error.None);
    assert(csv::read(reader, "", row).step == csv::Step.NeedInput);
    assert(csv::finish(reader, row).step == csv::Step.End);
    expect(row, ["before"]);
    assert(csv::init(reader, csv::Limits { max_field_bytes: 0, max_row_bytes: 4, max_total_bytes: 4, max_fields: 1 }).error == csv::Error.None);
    assert(csv::read(reader, "\"\"\r\n", row).step == csv::Step.Row);
    expect(row, [""]);
    assert(csv::init(reader, csv::Limits { max_field_bytes: 1, max_row_bytes: 3, max_total_bytes: 3, max_fields: 1 }).error == csv::Error.None);
    assert(csv::read(reader, "a\r\n", row).step == csv::Step.Row);
    expect(row, ["a"]);
    assert(csv::finish(reader, row).step == csv::Step.End);
    assert(csv::init(reader, csv::Limits { max_field_bytes: 16777216, max_row_bytes: 67108864, max_total_bytes: 1152921504606846976, max_fields: 65536 }).error == csv::Error.None);
    assert(csv::finish(reader, row).step == csv::Step.End);
    var retained = csv::Row { .. };
    assert(csv::init(reader).error == csv::Error.None);
    assert(csv::read(reader, "first\nsecond\n", retained).consumed == 6);
    assert(csv::read(reader, "second\n", row).step == csv::Step.Row);
    expect(retained, ["first"]); expect(row, ["second"]);
    assert(csv::init(reader).error == csv::Error.None);
    expect(retained, ["first"]); expect(row, ["second"]);
    var strict = csv::Reader { .. };
    assert(csv::init(strict, csv::Limits { .. }, false).error == csv::Error.None);
    assert(csv::read(strict, "a\r", row).step == csv::Step.NeedInput);
    expect(row, ["second"]);
    assert(csv::read(strict, "\n", row).step == csv::Step.Row);
    expect(row, ["a"]);
}
fn writer_checks() {
    var writer = csv::Writer { .. };
    let no_fields: (const u8[:])[0] = [];
    var out: u8[>..] = "sentinel";
    assert(csv::write(writer, ["x"], out).error == csv::Error.InvalidState);
    assert(out == "sentinel");
    assert(csv::init(writer).error == csv::Error.None);
    assert(csv::write(writer, csv::NO_FIELDS, out).error == csv::Error.None && out == "\r\n");
    assert(csv::write(writer, [""], out).error == csv::Error.None && out == "\"\"\r\n");
    assert(csv::write(writer, ["", ""], out).error == csv::Error.None && out == ",\r\n");
    assert(csv::write(writer, ["a,b", "a\"b", "a\r\nb"], out).error == csv::Error.None);
    assert(out == "\"a,b\",\"a\"\"b\",\"a\r\nb\"\r\n");
    out = "a,b";
    let aliases: (const u8[:])[1] = [out[..]];
    assert(csv::write(writer, aliases, out).error == csv::Error.None && out == "\"a,b\"\r\n");
    let binary:        u8[3]            = [0, 128, 255];
    let binary_fields: (const u8[:])[1] = [binary[..]];
    assert(csv::write(writer, binary_fields, out).error == csv::Error.None);
    let binary_expected: u8[5] = [0, 128, 255, '\r', '\n'];
    assert(out == binary_expected);
    assert(csv::init(writer, csv::Limits { max_field_bytes: 1, max_row_bytes: 3, max_total_bytes: 6, max_fields: 1 }).error == csv::Error.None);
    out = "old";
    let oversized = csv::write(writer, ["ab"], out);
    assert(oversized.error == csv::Error.FieldLimit && oversized.offset == 0 && oversized.record == 1 && oversized.field == 1);
    assert(out == "old");
    assert(csv::write(writer, ["x"], out).error == csv::Error.None && out == "x\r\n");
    assert(csv::init(writer, csv::Limits { max_total_bytes: -1, .. }).error == csv::Error.InvalidOptions);
    assert(csv::write(writer, ["y"], out).error == csv::Error.None && out == "y\r\n");
    let total = csv::write(writer, ["z"], out);
    assert(total.error == csv::Error.TotalLimit && total.offset == 6 && total.record == 3);
    assert(out == "y\r\n");
    assert(csv::init(writer, csv::Limits { max_fields: 1, .. }).error == csv::Error.None);
    out = "unchanged";
    let fields = csv::write(writer, ["a", "b"], out);
    assert(fields.error == csv::Error.FieldCountLimit && out == "unchanged");
    assert(csv::write(writer, ["ok"], out).error == csv::Error.None && out == "ok\r\n");
    assert(csv::init(writer, csv::Limits { max_row_bytes: 3, .. }).error == csv::Error.None);
    out = "unchanged";
    assert(csv::write(writer, [""], out).error == csv::Error.RowLimit && out == "unchanged");
    assert(csv::write(writer, ["x"], out).error == csv::Error.None && out == "x\r\n");
    assert(csv::init(writer, csv::Limits { max_field_bytes: 0, max_row_bytes: 2, max_total_bytes: 2, max_fields: 0 }).error == csv::Error.None);
    assert(csv::write(writer, no_fields, out).error == csv::Error.None && out == "\r\n");
}
// Exercise real storage at the published field and field-count ceilings,
// in addition to the small exact-budget and overflow-option regressions.
fn large_field_checks() {
    var source: u8[>..] = [];
    let piece = "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx";
    for _ in csv::MAX_FIELD_BYTES / piece.len { source.append(piece); }
    let limits = csv::Limits { max_field_bytes: csv::MAX_FIELD_BYTES, max_row_bytes: csv::MAX_ROW_BYTES, .. };
    var reader = csv::Reader { .. }; var row = csv::Row { .. };
    assert(csv::init(reader, limits).error == csv::Error.None);
    var offset: i64 = 0;
    while offset < source.len {
        let end = min(source.len, offset + 65536);
        let next = csv::read(reader, source[offset..end], row);
        assert(next.step == csv::Step.NeedInput && next.consumed == end - offset); offset = end;
    }
    assert(csv::finish(reader, row).step == csv::Step.Row && csv::field_count(row) == 1);
    assert(csv::field(row, 0) == source && csv::finish(reader, row).step == csv::Step.End);
    var writer = csv::Writer { .. }; var output: u8[>..] = [];
    assert(csv::init(writer, limits).error == csv::Error.None);
    let valid: (const u8[:])[1] = [csv::field(row, 0)];
    assert(csv::write(writer, valid, output).error == csv::Error.None);
    assert(output.len == csv::MAX_FIELD_BYTES + 2 && output[..csv::MAX_FIELD_BYTES] == source);
    assert(output[csv::MAX_FIELD_BYTES..] == "\r\n");
    source.push('x');
    assert(csv::init(reader, limits).error == csv::Error.None);
    let failed = csv::read(reader, source, row);
    assert(failed.step == csv::Step.Error && failed.status.error == csv::Error.FieldLimit);
    assert(failed.consumed == csv::MAX_FIELD_BYTES && failed.status.offset == csv::MAX_FIELD_BYTES);
    assert(csv::field(row, 0).len == csv::MAX_FIELD_BYTES);
    let invalid: (const u8[:])[1] = [source[..]];
    let rejected = csv::write(writer, invalid, output);
    assert(rejected.error == csv::Error.FieldLimit && rejected.offset == csv::MAX_FIELD_BYTES + 2 && rejected.record == 2);
    assert(output.len == csv::MAX_FIELD_BYTES + 2 && output[..csv::MAX_FIELD_BYTES] == csv::field(row, 0));
    let retry: (const u8[:])[1] = [csv::field(row, 0)];
    assert(csv::write(writer, retry, output).error == csv::Error.None);
}
fn many_field_checks() {
    var fields: (const u8[:])[>..] = [];
    for _ in csv::MAX_FIELDS { fields.push(""); }
    let limits = csv::Limits { max_fields: csv::MAX_FIELDS, .. };
    var writer = csv::Writer { .. }; var output: u8[>..] = [];
    assert(csv::init(writer, limits).error == csv::Error.None);
    assert(csv::write(writer, fields, output).error == csv::Error.None && output.len == csv::MAX_FIELDS + 1);
    var reader = csv::Reader { .. }; var row = csv::Row { .. };
    assert(csv::init(reader, limits).error == csv::Error.None);
    let next = csv::read(reader, output, row);
    assert(next.step == csv::Step.Row && next.consumed == output.len);
    assert(csv::field_count(row) == csv::MAX_FIELDS && csv::field(row, 0).len == 0 && csv::field(row, csv::MAX_FIELDS - 1).len == 0);
    assert(csv::finish(reader, row).step == csv::Step.End);
    fields.push("");
    let rejected = csv::write(writer, fields, output);
    assert(rejected.error == csv::Error.FieldCountLimit && rejected.field == csv::MAX_FIELDS + 1 && rejected.record == 2);
    assert(output.len == csv::MAX_FIELDS + 1);
    assert(csv::init(reader, limits).error == csv::Error.None);
    var commas: u8[>..] = [];
    for _ in csv::MAX_FIELDS { commas.push(','); }
    let failed = csv::read(reader, commas, row);
    assert(failed.step == csv::Step.Error && failed.status.error == csv::Error.FieldCountLimit);
    assert(failed.consumed == csv::MAX_FIELDS - 1 && failed.status.offset == csv::MAX_FIELDS - 1 && failed.status.field == csv::MAX_FIELDS + 1);
    assert(csv::field_count(row) == csv::MAX_FIELDS);
}
fn main() {
    reader_checks(); run_checks(); lifecycle_checks(); writer_checks(); large_field_checks(); many_field_checks();
    print("csv public API: split boundaries, limits, ownership, lifecycle and atomic writer checks passed");
}

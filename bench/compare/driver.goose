// SPDX-License-Identifier: Apache-2.0
// Controlled benchmark fixtures only; file I/O and dataset setup are outside timing.
import csv from "../..";
import support from "../../tests";
import std;
import os;
const MOD: i64 = 2147483647;
struct Span { start: i64, len: i64 }
root struct Dataset {
    raw:    u8[>..]            = [], spans: Span[>..] = [], ends: i64[>..] = [],
    fields: (const u8[:])[>..] = [],
}
fn mix(value: i64, part: i64) -> i64 { return (value * 257 + part + 1) % MOD; }
fn row_signature(row: const csv::Row&) -> i64 {
    var value = csv::field_count(row);
    for i in csv::field_count(row) {
        let f = csv::field(row, i); value = mix(value, f.len);
        if f.len > 0 { value = mix(value, f[0]); value = mix(value, f[f.len / 2]); value = mix(value, f[f.len - 1]); }
    }
    return value;
}
fn wire_signature(wire: const u8[:]) -> i64 {
    var value = wire.len;
    if wire.len > 0 { value = mix(value, wire[0]); value = mix(value, wire[wire.len / 2]); value = mix(value, wire[wire.len - 1]); }
    return value;
}
fn dump_row(row: const csv::Row&) {
    write_stdout(str("R ", csv::field_count(row)));
    for i in csv::field_count(row) { write_stdout(str(" ", csv_test::hex(csv::field(row, i)))); }
    print("");
}
fn report(records: i64, bytes: i64, checksum: i64, elapsed: i64, ok: bool) {
    print("S ", records, " ", bytes, " ", checksum, " ", elapsed, " ", if ok { "ok" } else { "error" });
}
inline fn parse(data: const u8[:], chunk: i64, repeats: i64, dump: bool) {
    var reader = csv::Reader { .. }; var row = csv::Row { .. };
    assert(csv::init(reader, csv::Limits { max_total_bytes: csv::MAX_TOTAL_BYTES, .. }).error == csv::Error.None);
    var records: i64 = 0; var bytes: i64 = 0; var checksum: i64 = 0;
    var error = csv::Status { .. };
    let start = clock_ns();
    for _ in repeats {
        var at: i64 = 0;
        while at < data.len {
            let end = min(data.len, at + chunk);
            while at < end {
                let next = csv::read(reader, data[at..end], row);
                assert(next.consumed >= 0 && next.consumed <= end - at);
                at += next.consumed; bytes += next.consumed;
                if next.step == csv::Step.Error { error = next.status; break; }
                if next.step == csv::Step.Row {
                    if dump { dump_row(row); }
                    records++; checksum = (checksum + row_signature(row)) % MOD;
                } else { assert(next.step == csv::Step.NeedInput && at == end); }
            }
            if error.error != csv::Error.None { break; }
        }
        if error.error != csv::Error.None { break; }
    }
    if error.error == csv::Error.None {
        while true {
            let next = csv::finish(reader, row);
            if next.step == csv::Step.End { break; }
            if next.step == csv::Step.Error { error = next.status; break; }
            assert(next.step == csv::Step.Row);
            if dump { dump_row(row); }
            records++; checksum = (checksum + row_signature(row)) % MOD;
        }
    }
    let elapsed = clock_ns() - start;
    if dump && error.error != csv::Error.None {
        print("E ", csv_test::error_name(error.error), " ", error.offset, " ", error.record, " ", error.field);
    }
    report(records, bytes, checksum, elapsed, error.error == csv::Error.None);
}
fn number(data: const u8[:], at: i64&) -> i64 {
    assert(at >= 0 && at <= data.len && data.len - at >= 4);
    var n: i64 = 0;
    for i in 4 { n += (data[at + i] as i64) << (8 * i); }
    at += 4; return n;
}
fn load(data: Dataset&, path: const u8[:]) {
    assert(read_file(path, data.raw) && data.raw.len <= 8388608);
    assert(data.raw.len >= 12 && data.raw[..8] == "GCFIELDS");
    var at: i64 = 8; let records = number(data.raw, at); assert(records <= 65536);
    for _ in records {
        let count = number(data.raw, at); assert(count <= 65536);
        for _ in count {
            let len = number(data.raw, at); assert(at <= data.raw.len && len <= data.raw.len - at);
            data.spans.push(Span { at, len }); at += len;
        }
        data.ends.push(data.spans.len);
    }
    assert(at == data.raw.len);
    // All backing bytes are stable before views are constructed.
    for s in data.spans { data.fields.push(data.raw[s.start..s.start + s.len]); }
}
inline fn encode(data: const Dataset&, repeats: i64, dump: bool) {
    var writer = csv::Writer { .. }; var output: u8[>..] = [];
    assert(csv::init(writer, csv::Limits { max_total_bytes: csv::MAX_TOTAL_BYTES, .. }).error == csv::Error.None);
    var records: i64 = 0; var bytes: i64 = 0; var checksum: i64 = 0;
    var error = csv::Status { .. };
    let start = clock_ns();
    for _ in repeats {
        var begin: i64 = 0;
        for end in data.ends {
            let status = csv::write(writer, data.fields[begin..end], output);
            if status.error != csv::Error.None { error = status; break; }
            begin = end;
            if dump { print("W ", csv_test::hex(output)); }
            records++; bytes += output.len; checksum = (checksum + wire_signature(output)) % MOD;
        }
        if error.error != csv::Error.None { break; }
    }
    let elapsed = clock_ns() - start;
    if dump && error.error != csv::Error.None { print("E ", csv_test::error_name(error.error), " ", error.offset, " ", error.record, " ", error.field); }
    report(records, bytes, checksum, elapsed, error.error == csv::Error.None);
}
fn main() {
    let argv = args(); assert(argv.len == 7 && argv[1] == "goose");
    let chunk, cv = parse_int(argv[4]); let repeats, rv = parse_int(argv[5]);
    assert(cv && rv && repeats >= 1 && repeats <= 1000000);
    let dump = argv[6] == "1";
    if argv[2] == "parse" {
        var bytes: u8[>..] = []; assert(read_file(argv[3], bytes) && bytes.len <= 8388608 && chunk > 0);
        parse(bytes, chunk, repeats, dump);
    } else {
        assert(argv[2] == "write"); var data = Dataset { .. }; load(data, argv[3]); encode(data, repeats, dump);
    }
}

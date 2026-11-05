// SPDX-License-Identifier: Apache-2.0
// Deterministic public-interface mutation/property fuzzing, not coverage-guided.
import csv from "..";
import .support;
import std;
import os;
fn random(seed: i64&, bound: i64) -> i64 {
    seed = seed * 48271 % 2147483647;
    return seed % bound;
}
fn same_status(a: csv::Status, b: csv::Status) -> bool {
    return a.error == b.error && a.offset == b.offset && a.record == b.record && a.field == b.field;
}
fn snapshot(row: const csv::Row&) -> u8[>..] {
    var bytes: u8[>..] = []; csv_test::append_row(row, bytes); return bytes;
}
fn roundtrip(row: const csv::Row&) {
    var fields: (const u8[:])[>..] = [];
    for i in csv::field_count(row) { fields.push(csv::field(row, i)); }
    var writer = csv::Writer { .. };
    var reader = csv::Reader { .. };
    var actual = csv::Row { .. };
    var encoded: u8[>..] = [];
    assert(csv::init(writer).error == csv::Error.None);
    assert(csv::write(writer, fields, encoded).error == csv::Error.None);
    assert(csv::init(reader).error == csv::Error.None);
    let progress = csv::read(reader, encoded, actual);
    assert(progress.step == csv::Step.Row && progress.consumed == encoded.len);
    assert(csv::field_count(actual) == csv::field_count(row));
    for i in csv::field_count(row) { assert(csv::field(actual, i) == csv::field(row, i)); }
    assert(csv::finish(reader, actual).step == csv::Step.End);
}
fn parse(data: const u8[:], limits: csv::Limits, allow_lf: bool, chunk: i64) -> u8[>..] {
    var reader = csv::Reader { .. };
    var row = csv::Row { .. };
    assert(csv::init(reader, limits, allow_lf).error == csv::Error.None);
    var summary: u8[>..] = [];
    var at:      i64     = 0;
    var status = csv::Status { .. };
    var failed = false;
    while at < data.len {
        let before = snapshot(row);
        let end = min(data.len, at + chunk);
        let progress = csv::read(reader, data[at..end], row);
        assert(progress.consumed >= 0 && progress.consumed <= end - at);
        at += progress.consumed;
        if progress.step == csv::Step.Error {
            assert(snapshot(row) == before && progress.status.offset == at);
            status = progress.status; failed = true; break;
        }
        assert(progress.status.error == csv::Error.None && progress.consumed > 0);
        if progress.step == csv::Step.Row { roundtrip(row); csv_test::append_row(row, summary); }
        else { assert(progress.step == csv::Step.NeedInput && at == end && snapshot(row) == before); }
    }
    if !failed {
        let before = snapshot(row);
        let progress = csv::finish(reader, row);
        assert(progress.consumed == 0);
        if progress.step == csv::Step.Error {
            assert(snapshot(row) == before && progress.status.offset == at);
            status = progress.status; failed = true;
        } else {
            assert(progress.status.error == csv::Error.None);
            if progress.step == csv::Step.Row { roundtrip(row); csv_test::append_row(row, summary); }
            else { assert(progress.step == csv::Step.End && snapshot(row) == before); }
            assert(csv::finish(reader, row).step == csv::Step.End);
        }
    }
    if failed {
        let before = snapshot(row);
        let again = csv::read(reader, "arbitrary", row);
        assert(again.step == csv::Step.Error && again.consumed == 0 && same_status(again.status, status));
        let eof = csv::finish(reader, row);
        assert(eof.step == csv::Step.Error && eof.consumed == 0 && same_status(eof.status, status));
        assert(snapshot(row) == before);
        csv_test::append_error(status, summary);
    } else { summary.append("OK"); }
    return summary;
}
fn main() {
    let argv = args();
    var iterations: i64 = 10000;
    if argv.len == 2 { let count, valid = parse_int(argv[1]); assert(valid && count > 0 && count <= 1000000); iterations = count; }
    else { assert(argv.len == 1); }
    var seed: i64 = 81297;
    let seeds:    (const u8[:])[10] = ["", "\r\n", "a,b\r\n", "\"a\"\"b\",c", "\"a\r\nb\",\"\"", ",,", "\"\"", "\"", "a\rb", "a\"b"];
    let alphabet: u8[16]            = ['a', 'b', ' ', ',', '"', '\r', '\n', 0, 1, 127, 128, 255, '=', '+', '-', '@'];
    var checksum: i64 = 0;
    for iteration in iterations {
        var data: u8[>..] = [];
        data.append(seeds[random(seed, seeds.len)]);
        let mutations = random(seed, 16);
        for _ in mutations {
            let byte = alphabet[random(seed, alphabet.len)];
            if data.len > 0 && random(seed, 3) == 0 { data[random(seed, data.len)] = byte; }
            else { data.push(byte); }
        }
        let limits = csv::Limits { max_field_bytes: random(seed, 33), max_row_bytes: random(seed, 129),
            max_total_bytes: random(seed, 257), max_fields: random(seed, 9) };
        let allow_lf = random(seed, 2) == 1;
        let whole = parse(data, limits, allow_lf, max(1, data.len));
        let bytes = parse(data, limits, allow_lf, 1);
        let other = parse(data, limits, allow_lf, 1 + random(seed, 11));
        assert(whole == bytes && whole == other);
        for byte in whole { checksum = (checksum * 131 + byte) % 2147483647; }
    }
    print("csv seeded mutation fuzz: ", iterations, " cases, seed 81297, checksum ", checksum);
}

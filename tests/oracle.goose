// SPDX-License-Identifier: Apache-2.0
import csv from "..";
import .support;
import std;
import os;
struct Span { start: i64, len: i64 }
root struct InputFields { bytes: u8[>..], spans: Span[>..] }
fn number(text: const u8[:]) -> i64 {
    let value, valid = parse_int(text); assert(valid); return value;
}
fn parse_case(parts: const (const u8[:])[:], out: u8[>..]&) {
    assert(parts.len == 8);
    let chunk_size = number(parts[1]); assert(chunk_size > 0);
    let allow = number(parts[2]); assert(allow == 0 || allow == 1);
    let limits = csv::Limits { number(parts[3]), number(parts[4]), number(parts[5]), number(parts[6]) };
    var data: u8[>..] = []; csv_test::decode(parts[7], data);
    var reader = csv::Reader { .. };
    var row = csv::Row { .. };
    assert(csv::init(reader, limits, allow == 1).error == csv::Error.None);
    var at: i64 = 0;
    while at < data.len {
        let end = min(data.len, at + chunk_size);
        let progress = csv::read(reader, data[at..end], row);
        assert(progress.consumed >= 0 && progress.consumed <= end - at);
        at += progress.consumed;
        if progress.step == csv::Step.Error {
            assert(progress.status.error != csv::Error.None && progress.status.offset == at);
            csv_test::append_error(progress.status, out); return;
        }
        assert(progress.status.error == csv::Error.None && progress.consumed > 0);
        if progress.step == csv::Step.Row { csv_test::append_row(row, out); }
        else { assert(progress.step == csv::Step.NeedInput && at == end); }
    }
    let progress = csv::finish(reader, row);
    assert(progress.consumed == 0);
    if progress.step == csv::Step.Error {
        assert(progress.status.error != csv::Error.None && progress.status.offset == at);
        csv_test::append_error(progress.status, out); return;
    }
    assert(progress.status.error == csv::Error.None);
    if progress.step == csv::Step.Row {
        csv_test::append_row(row, out);
        assert(csv::finish(reader, row).step == csv::Step.End);
    } else { assert(progress.step == csv::Step.End); }
    assert(csv::finish(reader, row).step == csv::Step.End);
    out.append("OK");
}
fn write_case(parts: const (const u8[:])[:], out: u8[>..]&) {
    assert(parts.len >= 6);
    let limits = csv::Limits { number(parts[1]), number(parts[2]), number(parts[3]), number(parts[4]) };
    let count = number(parts[5]); assert(count >= 0 && parts.len == count + 6);
    var input = InputFields { .. };
    var decoded: u8[>..] = [];
    for i in count {
        csv_test::decode(parts[6 + i], decoded);
        let start = input.bytes.len; input.bytes.append(decoded);
        input.spans.push(Span { start, decoded.len });
    }
    var fields: (const u8[:])[>..] = [];
    for span in input.spans { fields.push(input.bytes[span.start..span.start + span.len]); }
    var writer = csv::Writer { .. };
    assert(csv::init(writer, limits).error == csv::Error.None);
    var encoded: u8[>..] = "sentinel";
    let status = csv::write(writer, fields, encoded);
    if status.error != csv::Error.None {
        assert(encoded == "sentinel"); csv_test::append_error(status, out); return;
    }
    out.append("W "); out.append(csv_test::hex(encoded));
}
fn main() {
    var line: u8[>..] = [];
    while true {
        line.clear(); if !read_line(line) { break; }
        let parts = split(line, ' ');
        assert(parts.len > 0);
        var out: u8[>..] = [];
        if parts[0] == "P" { parse_case(parts, out); }
        else { assert(parts[0] == "W"); write_case(parts, out); }
        print(out);
    }
}

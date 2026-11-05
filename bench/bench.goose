// SPDX-License-Identifier: Apache-2.0
import csv from "..";
import std;
import os;

const MODULUS: i64 = 2147483647;
fn mix(value: i64, part: i64) -> i64 { return (value * 257 + part + 1) % MODULUS; }
fn row_signature(row: const csv::Row&) -> i64 {
    var value = csv::field_count(row);
    for i in csv::field_count(row) {
        let text = csv::field(row, i);
        value = mix(value, text.len);
        if text.len > 0 {
            value = mix(value, text[0]);
            value = mix(value, text[text.len / 2]);
            value = mix(value, text[text.len - 1]);
        }
    }
    return value;
}
fn wire_signature(text: const u8[:]) -> i64 {
    var value = text.len;
    if text.len > 0 {
        value = mix(value, text[0]);
        value = mix(value, text[text.len / 2]);
        value = mix(value, text[text.len - 1]);
    }
    return value;
}
fn same_fields(row: const csv::Row&, fields: const (const u8[:])[:]) {
    assert(csv::field_count(row) == fields.len);
    for i in fields.len { assert(csv::field(row, i) == fields[i]); }
}
fn report(mode: const u8[:], label: const u8[:], chunk: i64, iterations: i64,
          bytes: i64, records: i64, elapsed: i64, checksum: i64) {
    assert(elapsed > 0);
    print("S ", mode, " ", label, " ", chunk, " ", iterations, " ", bytes,
        " ", records, " ", elapsed, " ", checksum);
}
fn parse_bench(label: const u8[:], batch: const u8[:], fields: const (const u8[:])[:],
               chunk: i64, block_rows: i64, iterations: i64, expected_signature: i64) {
    var reader = csv::Reader { .. };
    var row = csv::Row { .. };
    let limits = csv::Limits { max_total_bytes: csv::MAX_TOTAL_BYTES, .. };
    assert(csv::init(reader, limits).error == csv::Error.None);
    var bytes:    i64 = 0;
    var records:  i64 = 0;
    var checksum: i64 = 0;
    let start = clock_ns();
    for _ in iterations {
        var offset: i64 = 0;
        while offset < batch.len {
            let end = min(batch.len, offset + chunk);
            let progress = csv::read(reader, batch[offset..end], row);
            assert(progress.status.error == csv::Error.None);
            assert(progress.consumed > 0 && progress.consumed <= end - offset);
            bytes += progress.consumed;
            offset += progress.consumed;
            if progress.step == csv::Step.Row {
                records++;
                checksum += row_signature(row);
            } else { assert(progress.step == csv::Step.NeedInput); }
        }
    }
    assert(csv::finish(reader, row).step == csv::Step.End);
    let elapsed = clock_ns() - start;
    assert(records == block_rows * iterations && bytes == batch.len * iterations);
    assert(checksum == expected_signature * records);
    same_fields(row, fields);
    report("parse", label, chunk, iterations, bytes, records, elapsed, checksum);
}
fn write_bench(label: const u8[:], wire: const u8[:], fields: const (const u8[:])[:],
               block_rows: i64, iterations: i64) {
    var writer = csv::Writer { .. };
    let limits = csv::Limits { max_total_bytes: csv::MAX_TOTAL_BYTES, .. };
    assert(csv::init(writer, limits).error == csv::Error.None);
    var output:   u8[>..] = [];
    var bytes:    i64     = 0;
    var records:  i64     = 0;
    var checksum: i64     = 0;
    let start = clock_ns();
    for _ in block_rows * iterations {
        assert(csv::write(writer, fields, output).error == csv::Error.None);
        records++;
        bytes += output.len;
        checksum += wire_signature(output);
    }
    let elapsed = clock_ns() - start;
    assert(records == block_rows * iterations && bytes == wire.len * records);
    assert(output == wire && checksum == wire_signature(wire) * records);
    report("write", label, 0, iterations, bytes, records, elapsed, checksum);
}
fn fixture(label: const u8[:], fields: const (const u8[:])[:], iterations: i64, manifest: bool) {
    // Fixture construction and full decoded-field validation are outside timing.
    var writer = csv::Writer { .. };
    assert(csv::init(writer).error == csv::Error.None);
    var wire: u8[>..] = [];
    assert(csv::write(writer, fields, wire).error == csv::Error.None);
    var reader = csv::Reader { .. };
    var row = csv::Row { .. };
    assert(csv::init(reader).error == csv::Error.None);
    let progress = csv::read(reader, wire, row);
    assert(progress.step == csv::Step.Row && progress.consumed == wire.len);
    assert(csv::finish(reader, row).step == csv::Step.End);
    same_fields(row, fields);
    let signature = row_signature(row);
    let block_rows = max(1, 65536 / wire.len);
    if manifest {
        let digits = "0123456789abcdef";
        var hex: u8[>..] = [];
        for byte in wire { hex.push(digits[byte / 16]); hex.push(digits[byte % 16]); }
        print("M ", label, " ", wire.len, " ", block_rows, " ", fields.len,
            " ", signature, " ", wire_signature(wire), " ", hex[..]);
        return;
    }
    var batch: u8[>..] = [];
    for _ in block_rows { batch.append(wire); }
    // The ordinary fixture exercises both single-row and multirow chunk paths.
    if label == "simple" {
        parse_bench(label, batch, fields, 1, block_rows, iterations, signature);
        parse_bench(label, batch, fields, 64, block_rows, iterations, signature);
        parse_bench(label, batch, fields, 65536, block_rows, iterations, signature);
    }
    parse_bench(label, batch, fields, 4096, block_rows, iterations, signature);
    write_bench(label, wire, fields, block_rows, iterations);
}
fn main() {
    let argv = args();
    assert(argv.len == 2);
    let manifest = argv[1] == "--manifest";
    var iterations: i64 = 1;
    if !manifest {
        let number, valid = parse_int(argv[1]);
        assert(valid && number >= 1 && number <= 1000);
        iterations = number;
    }
    fixture("simple", ["alpha", "beta", "gamma", "delta", "epsilon", "zeta", "eta", "theta"], iterations, manifest);
    fixture("quoted", ["alpha,beta", "say \"hello\"", "line1\r\nline2", "tail"], iterations, manifest);
    var empty_fields: (const u8[:])[>..] = [];
    for _ in 256 { empty_fields.push(""); }
    fixture("empty256", empty_fields, iterations, manifest);
    fixture("utf8", ["café", "東京", "🙂", ""], iterations, manifest);
    var binary: u8[>..] = [];
    for i in 256 { binary.push(i as u8); }
    var nul: u8[3] = ['x', 0, 'y'];
    let binary_fields: const (const u8[:])[2] = [binary[..], nul[..]];
    fixture("binary", binary_fields, iterations, manifest);
    var long_field: u8[>..] = [];
    long_field.resize(262144, 'x');
    let long_fields: const (const u8[:])[1] = [long_field[..]];
    fixture("long256k", long_fields, iterations, manifest);
}

// SPDX-License-Identifier: Apache-2.0
import csv from "..";
import std;
fn show(row: const csv::Row&) {
    for i in csv::field_count(row) { print(i, ": ", csv::field(row, i)); }
}
fn main() {
    var reader = csv::Reader { .. };
    var row = csv::Row { .. };
    assert(csv::init(reader).error == csv::Error.None);
    // A producer may supply any chunk sizes, including splits inside quoted bytes.
    let chunk = "id,name\r\n1,\"hello,world\"\r\n";
    var offset: i64 = 0;
    while offset < chunk.len {
        let next = csv::read(reader, chunk[offset..], row);
        assert(next.step != csv::Step.Error);
        offset += next.consumed;
        if next.step == csv::Step.Row { show(row); }
        else { assert(next.step == csv::Step.NeedInput && offset == chunk.len); }
    }
    while true {
        let next = csv::finish(reader, row);
        assert(next.step != csv::Step.Error);
        if next.step == csv::Step.End { break; }
        assert(next.step == csv::Step.Row); show(row);
    }
    var writer = csv::Writer { .. };
    assert(csv::init(writer).error == csv::Error.None);
    let fields: const (const u8[:])[2] = ["1", "hello,world"];
    var encoded: u8[>..] = [];
    assert(csv::write(writer, fields, encoded).error == csv::Error.None);
    print(encoded);
}

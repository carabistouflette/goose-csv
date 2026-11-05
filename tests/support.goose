// SPDX-License-Identifier: Apache-2.0
namespace csv_test;
import csv;
import std;
fn nibble(c: u8) -> i64 {
    if c >= '0' && c <= '9' { return c - '0'; }
    if c >= 'a' && c <= 'f' { return c - 'a' + 10; }
    assert(false); return 0;
}
fn decode(token: const u8[:], out: u8[>..]&) {
    out.clear();
    if token == "-" { return; }
    assert(token.len % 2 == 0);
    for i in token.len / 2 { out.push((nibble(token[i * 2]) * 16 + nibble(token[i * 2 + 1])) as u8); }
}
fn hex(bytes: const u8[:]) -> u8[>..] {
    var out: u8[>..] = [];
    if bytes.len == 0 { out.push('-'); return out; }
    let digits = "0123456789abcdef";
    for b in bytes { out.push(digits[b / 16]); out.push(digits[b % 16]); }
    return out;
}
fn error_name(error: csv::Error) -> const u8[:] {
    if error == csv::Error.None { return "None"; }
    if error == csv::Error.InvalidOptions { return "InvalidOptions"; }
    if error == csv::Error.InvalidState { return "InvalidState"; }
    if error == csv::Error.UnexpectedQuote { return "UnexpectedQuote"; }
    if error == csv::Error.AfterQuote { return "AfterQuote"; }
    if error == csv::Error.ExpectedLf { return "ExpectedLf"; }
    if error == csv::Error.UnexpectedLf { return "UnexpectedLf"; }
    if error == csv::Error.UnclosedQuote { return "UnclosedQuote"; }
    if error == csv::Error.FieldLimit { return "FieldLimit"; }
    if error == csv::Error.RowLimit { return "RowLimit"; }
    if error == csv::Error.TotalLimit { return "TotalLimit"; }
    if error == csv::Error.FieldCountLimit { return "FieldCountLimit"; }
    assert(false); return "Unknown";
}
fn append_row(row: const csv::Row&, out: u8[>..]&) {
    out.append(str("R ", csv::field_count(row)));
    for i in csv::field_count(row) { out.push(' '); out.append(hex(csv::field(row, i))); }
    out.push(';');
}
fn append_error(status: csv::Status, out: u8[>..]&) {
    out.append(str("E ", error_name(status.error), " ", status.offset, " ", status.record, " ", status.field));
}

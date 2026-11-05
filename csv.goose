// SPDX-License-Identifier: Apache-2.0
namespace csv;
import std;

const MAX_FIELD_BYTES: i64              = 16777216;
const MAX_ROW_BYTES:   i64              = 67108864;
const MAX_TOTAL_BYTES: i64              = 1152921504606846976;
const MAX_FIELDS:      i64              = 65536;
const NO_FIELDS:       (const u8[:])[0] = [];
// Prepared once; the pinned standard runtime supplies bounded portable scanning.
const _BARE_STOPS:   ByteSet = byte_set(",\"\r\n");
const _QUOTE_STOP:   ByteSet = byte_set("\"");
const _PLAN_QUOTED:  u8      = 1;
const _PLAN_ESCAPES: u8      = 2;
const _PLAN_SCALAR:  u8      = 4;
struct Limits {
    max_field_bytes: i64 = 1048576,
    max_row_bytes:   i64 = 4194304,
    max_total_bytes: i64 = 67108864,
    max_fields:      i64 = 4096,
}
enum Error {
    None, InvalidOptions, InvalidState, UnexpectedQuote, AfterQuote, ExpectedLf,
    UnexpectedLf, UnclosedQuote, FieldLimit, RowLimit, TotalLimit, FieldCountLimit,
}
enum Step { NeedInput, Row, End, Error }
struct Status { error: Error = Error.None, offset: i64 = 0, record: i64 = 1, field: i64 = 1 }
struct Progress { step: Step, consumed: i64 = 0, status: Status = Status { .. } }
struct Span { start: i64, len: i64 }
root struct Row { _bytes: u8[>..] = [], _spans: Span[>..] = [] }
enum Phase { Inactive, Start, Bare, Quoted, QuoteEnd, AfterCr, Finished, Failed }
root struct Reader {
    _limits:   Limits  = Limits { .. }, _allow_lf: bool = true,
    _phase:    Phase   = Phase.Inactive, _error: Status = Status { .. },
    _total:    i64     = 0, _row_bytes: i64 = 0, _records: i64 = 0,
    _field_no: i64     = 1, _field_start: i64 = 0, _active: bool = false,
    _bytes:    u8[>..] = [], _spans: Span[>..] = [],
}
root struct Writer {
    _limits: Limits = Limits { .. }, _initialized: bool = false,
    _total:  i64    = 0, _records: i64 = 0, _scratch: u8[>..] = [],
}
fn valid_limits(limits: Limits) -> bool {
    return limits.max_field_bytes >= 0 && limits.max_field_bytes <= MAX_FIELD_BYTES &&
        limits.max_row_bytes >= 0 && limits.max_row_bytes <= MAX_ROW_BYTES &&
        limits.max_total_bytes >= 0 && limits.max_total_bytes <= MAX_TOTAL_BYTES &&
        limits.max_fields >= 0 && limits.max_fields <= MAX_FIELDS;
}
fn init(reader: Reader&, limits: Limits = Limits { .. }, allow_lf: bool = true) -> Status {
    if !valid_limits(limits) { return Status { error: Error.InvalidOptions, .. }; }
    reader._bytes.clear(); reader._spans.clear();
    reader._limits = limits; reader._allow_lf = allow_lf;
    reader._phase = Phase.Start; reader._error = Status { .. };
    reader._total = 0; reader._row_bytes = 0; reader._records = 0;
    reader._field_no = 1; reader._field_start = 0; reader._active = false;
    return Status { .. };
}
fn init(writer: Writer&, limits: Limits = Limits { .. }) -> Status {
    if !valid_limits(limits) { return Status { error: Error.InvalidOptions, .. }; }
    writer._scratch.clear(); writer._limits = limits;
    writer._total = 0; writer._records = 0; writer._initialized = true;
    return Status { .. };
}
fn field_count(row: const Row&) -> i64 { return row._spans.len; }
// Index must be in range; views are borrowed from this Row's storage.
fn field(row: const Row&, index: i64) -> const u8[:] {
    let span = row._spans[index];
    return row._bytes[span.start..span.start + span.len];
}
fn fail(reader: Reader&, error: Error, field_no: i64 = 0) -> bool {
    reader._error = Status { error: error, offset: reader._total,
        record: reader._records + 1, field: if field_no > 0 { field_no } else { reader._field_no } };
    reader._phase = Phase.Failed;
    return false;
}
fn error_progress(reader: const Reader&, consumed: i64 = 0) -> Progress {
    return Progress { step: Step.Error, consumed: consumed, status: reader._error };
}
fn current_field(reader: Reader&) -> bool {
    if reader._field_no > reader._limits.max_fields { return fail(reader, Error.FieldCountLimit); }
    return true;
}
fn append_byte(reader: Reader&, byte: u8) -> bool {
    if !current_field(reader) { return false; }
    if reader._bytes.len - reader._field_start >= reader._limits.max_field_bytes {
        return fail(reader, Error.FieldLimit);
    }
    reader._bytes.push(byte);
    return true;
}
fn end_field(reader: Reader&) -> bool {
    if !current_field(reader) { return false; }
    reader._spans.push(Span { start: reader._field_start, len: reader._bytes.len - reader._field_start });
    reader._field_start = reader._bytes.len;
    return true;
}
fn comma(reader: Reader&) -> bool {
    if !current_field(reader) { return false; }
    // A delimiter already implies the following field, even if EOF follows.
    if reader._field_no >= reader._limits.max_fields { return fail(reader, Error.FieldCountLimit, reader._field_no + 1); }
    if !end_field(reader) { return false; }
    reader._field_no++; reader._active = true; reader._phase = Phase.Start;
    return true;
}
fn end_record(reader: Reader&) -> bool {
    // A blank record has zero fields; quoted empty and trailing comma are active.
    if reader._active { return end_field(reader); }
    return true;
}
fn emit(reader: Reader&, row: Row&) {
    // Roots cannot be nested or moved. Copy only the completed row, once.
    row._bytes = copy(reader._bytes); row._spans = copy(reader._spans);
    reader._bytes.clear(); reader._spans.clear();
    reader._row_bytes = 0; reader._field_no = 1; reader._field_start = 0;
    reader._active = false; reader._phase = Phase.Start; reader._records++;
}
// Keep byte transitions inline so Root components stay visible to optimization.
inline fn _advance(reader: Reader&, byte: u8) -> bool, bool {
    // Budgets are checked before counting the candidate byte or growing storage.
    if reader._total >= reader._limits.max_total_bytes {
        fail(reader, Error.TotalLimit); return false, false;
    }
    if reader._row_bytes >= reader._limits.max_row_bytes {
        fail(reader, Error.RowLimit); return false, false;
    }
    var complete = false;
    if reader._phase == Phase.AfterCr {
        if byte != '\n' { fail(reader, Error.ExpectedLf); return false, false; }
        complete = true;
    } else if reader._phase == Phase.Quoted {
        if byte == '"' { reader._phase = Phase.QuoteEnd; }
        else if !append_byte(reader, byte) { return false, false; }
    } else if reader._phase == Phase.QuoteEnd && byte == '"' {
        if !append_byte(reader, byte) { return false, false; }
        reader._phase = Phase.Quoted;
    } else if byte == ',' {
        if !comma(reader) { return false, false; }
    } else if byte == '\r' || byte == '\n' {
        if byte == '\n' && !reader._allow_lf {
            fail(reader, Error.UnexpectedLf); return false, false;
        }
        if !end_record(reader) { return false, false; }
        if byte == '\r' { reader._phase = Phase.AfterCr; }
        else { complete = true; }
    } else if reader._phase == Phase.QuoteEnd {
        fail(reader, Error.AfterQuote); return false, false;
    } else if byte == '"' {
        if reader._phase != Phase.Start {
            fail(reader, Error.UnexpectedQuote); return false, false;
        }
        if !current_field(reader) { return false, false; }
        reader._phase = Phase.Quoted; reader._active = true;
    } else {
        if !append_byte(reader, byte) { return false, false; }
        reader._phase = Phase.Bare; reader._active = true;
    }
    reader._total++; reader._row_bytes++;
    return true, complete;
}
inline fn _read_scalar(reader: Reader&, chunk: const u8[:], row: Row&, base: i64 = 0) -> Progress {
    var accepted_bytes: i64 = 0;
    for byte in chunk {
        let accepted, complete = _advance(reader, byte);
        if !accepted { return error_progress(reader, base + accepted_bytes); }
        accepted_bytes++;
        if complete {
            let consumed = base + accepted_bytes;
            emit(reader, row);
            return Progress { step: Step.Row, consumed: consumed, .. };
        }
    }
    return Progress { step: Step.NeedInput, consumed: base + chunk.len, .. };
}
// Select bulk scanning only for a promising initial field prefix.
// Later long fields can stay scalar until the caller supplies another chunk.
inline fn _prefer_runs(reader: const Reader&, chunk: const u8[:]) -> bool {
    if chunk.len < 64 || reader._limits.max_total_bytes - reader._total < 64 ||
        reader._limits.max_row_bytes - reader._row_bytes < 64 ||
        reader._limits.max_field_bytes - (reader._bytes.len - reader._field_start) < 32 ||
        reader._field_no > reader._limits.max_fields { return false; }
    var start: i64 = 0;
    var quoted = reader._phase == Phase.Quoted;
    if reader._phase == Phase.Start {
        if chunk[0] == '"' { quoted = true; start = 1; }
    } else if reader._phase != Phase.Bare && !quoted { return false; }
    for i in 32 {
        let byte = chunk[start + i];
        if byte == '"' || (!quoted && (byte == ',' || byte == '\r' || byte == '\n')) { return false; }
    }
    return true;
}
inline fn _read_runs(reader: Reader&, chunk: const u8[:], row: Row&) -> Progress {
    var rest: const u8[:] = chunk;
    while rest.len >= 16 {
        let byte = rest[0];
        let quoted = reader._phase == Phase.Quoted;
        if (quoted && byte != '"') ||
            ((reader._phase == Phase.Start || reader._phase == Phase.Bare) && byte != ',' && byte != '"' && byte != '\r' && byte != '\n') {
            let available = min(rest.len, min(reader._limits.max_total_bytes - reader._total,
                min(reader._limits.max_row_bytes - reader._row_bytes,
                    reader._limits.max_field_bytes - (reader._bytes.len - reader._field_start))));
            if available >= 16 {
                if !current_field(reader) { return error_progress(reader, chunk.len - rest.len); }
                var count: i64 = 0;
                while count < 16 {
                    let next = rest[count];
                    if next == '"' || (!quoted && (next == ',' || next == '\r' || next == '\n')) { break; }
                    count++;
                }
                if count == 16 && available > 16 {
                    let input = rest[16..available];
                    let stop = if quoted { find_any(input, _QUOTE_STOP) } else { find_any(input, _BARE_STOPS) };
                    count += if stop < 0 { input.len } else { stop };
                }
                reader._bytes.append(rest[..count]);
                if !quoted { reader._phase = Phase.Bare; reader._active = true; }
                reader._total += count; reader._row_bytes += count;
                rest = rest[count..];
                // Keep dense quoted remainders on the canonical scalar loop.
                if quoted && count < 16 { break; }
                continue;
            }
        }
        let accepted, complete = _advance(reader, byte);
        if !accepted { return error_progress(reader, chunk.len - rest.len); }
        rest = rest[1..];
        if complete {
            let consumed = chunk.len - rest.len;
            emit(reader, row); return Progress { step: Step.Row, consumed: consumed, .. };
        }
    }
    var consumed = chunk.len - rest.len;
    for byte in rest {
        let accepted, complete = _advance(reader, byte);
        if !accepted { return error_progress(reader, consumed); }
        consumed++;
        if complete {
            emit(reader, row);
            return Progress { step: Step.Row, consumed: consumed, .. };
        }
    }
    return Progress { step: Step.NeedInput, consumed: consumed, .. };
}
inline fn read(reader: Reader&, chunk: const u8[:], row: Row&) -> Progress {
    if reader._phase == Phase.Failed { return error_progress(reader); }
    if reader._phase == Phase.Inactive {
        fail(reader, Error.InvalidState); return error_progress(reader);
    }
    if reader._phase == Phase.Finished {
        if chunk.len == 0 { return Progress { step: Step.End, .. }; }
        fail(reader, Error.InvalidState); return error_progress(reader);
    }
    if _prefer_runs(reader, chunk) { return _read_runs(reader, chunk, row); }
    return _read_scalar(reader, chunk, row);
}
fn finish(reader: Reader&, row: Row&) -> Progress {
    if reader._phase == Phase.Failed { return error_progress(reader); }
    if reader._phase == Phase.Inactive {
        fail(reader, Error.InvalidState); return error_progress(reader);
    }
    if reader._phase == Phase.Finished { return Progress { step: Step.End, .. }; }
    if reader._phase == Phase.Quoted {
        fail(reader, Error.UnclosedQuote); return error_progress(reader);
    }
    if reader._phase == Phase.AfterCr {
        fail(reader, Error.ExpectedLf); return error_progress(reader);
    }
    if reader._active {
        if !end_field(reader) { return error_progress(reader); }
        emit(reader, row); reader._phase = Phase.Finished;
        return Progress { step: Step.Row, .. };
    }
    reader._phase = Phase.Finished;
    return Progress { step: Step.End, .. };
}
fn writer_status(writer: const Writer&, error: Error, field_no: i64 = 1) -> Status {
    return Status { error: error, offset: writer._total, record: writer._records + 1, field: field_no };
}
fn write(writer: Writer&, fields: const (const u8[:])[:], output: u8[>..]&) -> Status {
    if !writer._initialized { return writer_status(writer, Error.InvalidState); }
    if fields.len > writer._limits.max_fields { return writer_status(writer, Error.FieldCountLimit, writer._limits.max_fields + 1); }
    // Preflight mutates no writer/output state, so a corrected row can retry.
    var size: i64 = 2; // canonical CRLF, including for a zero-field row
    if size > writer._limits.max_row_bytes { return writer_status(writer, Error.RowLimit); }
    if size > writer._limits.max_total_bytes - writer._total { return writer_status(writer, Error.TotalLimit); }
    let capacity = min(writer._limits.max_row_bytes, writer._limits.max_total_bytes - writer._total);
    // One byte records quoting, escapes and the scalar rendering fallback.
    var plans: u8[>..] = [];
    for i in fields.len {
        let text = fields[i];
        if text.len > writer._limits.max_field_bytes { return writer_status(writer, Error.FieldLimit, i + 1); }
        var quoted = fields.len == 1 && text.len == 0;
        var escapes: i64 = 0;
        let prefix = min(text.len, 32);
        for byte in text[..prefix] {
            if byte == '"' { quoted = true; escapes++; }
            else if byte == ',' || byte == '\r' || byte == '\n' { quoted = true; }
        }
        if prefix < text.len {
            let rest = text[prefix..];
            let first = if quoted { find_any(rest, _QUOTE_STOP) } else { find_any(rest, _BARE_STOPS) };
            if first >= 0 {
                quoted = true;
                var at = prefix + first;
                while at < text.len {
                    if text[at] == '"' { escapes++; }
                    let next = find_any(text[at + 1..], _QUOTE_STOP);
                    if next < 0 { break; }
                    at += next + 1;
                    // Closely spaced quotes use one simple count pass.
                    if next < 16 {
                        for byte in text[at..] { if byte == '"' { escapes++; } }
                        break;
                    }
                }
            }
        }
        // text and escape counts are each <= MAX_FIELD_BYTES, so this cannot wrap.
        let additional = text.len + escapes + (if quoted { 2 } else { 0 }) + (if i > 0 { 1 } else { 0 });
        if additional > capacity - size {
            // Preserve RowLimit precedence even when this field crosses both caps.
            if additional > writer._limits.max_row_bytes - size { return writer_status(writer, Error.RowLimit, i + 1); }
            return writer_status(writer, Error.TotalLimit, i + 1);
        }
        size += additional;
        var plan: u8 = 0;
        if quoted {
            plan = _PLAN_QUOTED;
            if escapes > 0 {
                plan |= _PLAN_ESCAPES;
                if text.len < 32 || escapes > text.len / 16 { plan |= _PLAN_SCALAR; }
            }
        }
        plans.push(plan);
    }
    writer._scratch.clear();
    for i in fields.len {
        if i > 0 { writer._scratch.push(','); }
        let text = fields[i];
        if (plans[i] & _PLAN_QUOTED) != 0 {
            writer._scratch.push('"');
            var start: i64 = 0;
            if (plans[i] & _PLAN_ESCAPES) != 0 {
                if (plans[i] & _PLAN_SCALAR) != 0 {
                    for at in text.len {
                        if text[at] == '"' {
                            writer._scratch.append(text[start..at]); writer._scratch.append("\"\""); start = at + 1;
                        }
                    }
                } else {
                    while start < text.len {
                        let found = find_any(text[start..], _QUOTE_STOP);
                        if found < 0 { break; }
                        let at = start + found;
                        writer._scratch.append(text[start..at]); writer._scratch.append("\"\""); start = at + 1;
                    }
                }
            }
            if start < text.len { writer._scratch.append(text[start..]); }
            writer._scratch.push('"');
        } else if text.len > 0 { writer._scratch.append(text); }
    }
    writer._scratch.append("\r\n");
    assert(writer._scratch.len == size);
    output = copy(writer._scratch);
    writer._total += size; writer._records++;
    return Status { .. };
}

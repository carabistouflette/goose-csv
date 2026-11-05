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
// Reader roots pass many component references; inline only the per-byte step.
inline fn _advance(reader: Reader&, byte: u8) -> Step {
    // Budgets are checked before counting the candidate byte or growing storage.
    if reader._total >= reader._limits.max_total_bytes {
        fail(reader, Error.TotalLimit); return Step.Error;
    }
    if reader._row_bytes >= reader._limits.max_row_bytes {
        fail(reader, Error.RowLimit); return Step.Error;
    }
    var complete = false;
    if reader._phase == Phase.AfterCr {
        if byte != '\n' { fail(reader, Error.ExpectedLf); return Step.Error; }
        complete = true;
    } else if reader._phase == Phase.Quoted {
        if byte == '"' { reader._phase = Phase.QuoteEnd; }
        else if !append_byte(reader, byte) { return Step.Error; }
    } else if reader._phase == Phase.QuoteEnd && byte == '"' {
        if !append_byte(reader, byte) { return Step.Error; }
        reader._phase = Phase.Quoted;
    } else if byte == ',' {
        if !comma(reader) { return Step.Error; }
    } else if byte == '\r' || byte == '\n' {
        if byte == '\n' && !reader._allow_lf {
            fail(reader, Error.UnexpectedLf); return Step.Error;
        }
        if !end_record(reader) { return Step.Error; }
        if byte == '\r' { reader._phase = Phase.AfterCr; }
        else { complete = true; }
    } else if reader._phase == Phase.QuoteEnd {
        fail(reader, Error.AfterQuote); return Step.Error;
    } else if byte == '"' {
        if reader._phase != Phase.Start {
            fail(reader, Error.UnexpectedQuote); return Step.Error;
        }
        if !current_field(reader) { return Step.Error; }
        reader._phase = Phase.Quoted; reader._active = true;
    } else {
        if !append_byte(reader, byte) { return Step.Error; }
        reader._phase = Phase.Bare; reader._active = true;
    }
    reader._total++; reader._row_bytes++;
    return if complete { Step.Row } else { Step.NeedInput };
}
fn _read_runs(reader: Reader&, chunk: const u8[:], row: Row&) -> Progress {
    var consumed: i64 = 0;
    while consumed < chunk.len {
        let byte = chunk[consumed];
        let quoted = reader._phase == Phase.Quoted;
        if chunk.len - consumed >= 16 && ((quoted && byte != '"') ||
            ((reader._phase == Phase.Start || reader._phase == Phase.Bare) && byte != ',' && byte != '"' && byte != '\r' && byte != '\n')) {
            // Cap work before scanning; boundary bytes use the shared scalar step.
            let available = min(chunk.len - consumed, min(reader._limits.max_total_bytes - reader._total,
                min(reader._limits.max_row_bytes - reader._row_bytes,
                    reader._limits.max_field_bytes - (reader._bytes.len - reader._field_start))));
            if available >= 16 {
                if !current_field(reader) { return error_progress(reader, consumed); }
                // Short ordinary runs avoid a native search call entirely.
                var count: i64 = 0;
                while count < 16 {
                    let next = chunk[consumed + count];
                    if next == '"' || (!quoted && (next == ',' || next == '\r' || next == '\n')) { break; }
                    count++;
                }
                if count == 16 && available > 16 {
                    let input = chunk[consumed + 16..consumed + available];
                    let stop = if quoted { find_any(input, _QUOTE_STOP) } else { find_any(input, _BARE_STOPS) };
                    count += if stop < 0 { input.len } else { stop };
                }
                reader._bytes.append(chunk[consumed..consumed + count]);
                if !quoted { reader._phase = Phase.Bare; reader._active = true; }
                reader._total += count; reader._row_bytes += count; consumed += count;
                continue;
            }
        }
        let step = _advance(reader, byte);
        if step == Step.Error { return error_progress(reader, consumed); }
        consumed++;
        if step == Step.Row { emit(reader, row); return Progress { step: Step.Row, consumed: consumed, .. }; }
    }
    return Progress { step: Step.NeedInput, consumed: consumed, .. };
}
fn read(reader: Reader&, chunk: const u8[:], row: Row&) -> Progress {
    if reader._phase == Phase.Failed { return error_progress(reader); }
    if reader._phase == Phase.Inactive {
        fail(reader, Error.InvalidState); return error_progress(reader);
    }
    if reader._phase == Phase.Finished {
        if chunk.len == 0 { return Progress { step: Step.End, .. }; }
        fail(reader, Error.InvalidState); return error_progress(reader);
    }
    if chunk.len >= 16 { return _read_runs(reader, chunk, row); }
    var consumed: i64 = 0;
    for byte in chunk {
        let step = _advance(reader, byte);
        if step == Step.Error { return error_progress(reader, consumed); }
        consumed++;
        if step == Step.Row { emit(reader, row); return Progress { step: Step.Row, consumed: consumed, .. }; }
    }
    return Progress { step: Step.NeedInput, consumed: consumed, .. };
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
    // One byte records quoting, escapes and the scalar rendering fallback.
    var plans: u8[>..] = [];
    for i in fields.len {
        let text = fields[i];
        if text.len > writer._limits.max_field_bytes { return writer_status(writer, Error.FieldLimit, i + 1); }
        var quoted = fields.len == 1 && text.len == 0;
        var escapes: i64 = 0;
        if text.len < 32 {
            for byte in text {
                if byte == '"' { quoted = true; escapes++; }
                else if byte == ',' || byte == '\r' || byte == '\n' { quoted = true; }
            }
        } else {
            let first = find_any(text, _BARE_STOPS);
            if first >= 0 {
                quoted = true;
                var at = first;
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
        if additional > writer._limits.max_row_bytes - size { return writer_status(writer, Error.RowLimit, i + 1); }
        if additional > writer._limits.max_total_bytes - writer._total - size { return writer_status(writer, Error.TotalLimit, i + 1); }
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
            writer._scratch.append(text[start..]); writer._scratch.push('"');
        } else { writer._scratch.append(text); }
    }
    writer._scratch.append("\r\n");
    assert(writer._scratch.len == size);
    output = copy(writer._scratch);
    writer._total += size; writer._records++;
    return Status { .. };
}

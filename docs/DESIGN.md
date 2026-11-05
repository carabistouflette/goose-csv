# Bounded streaming CSV contract

## Scope and dialect

Pure Goose module, no I/O or native acceleration initially. Comma separator,
double-quote quoting and doubled quote escapes. Spaces remain data. Quoted CR/LF
bytes are preserved exactly; outside quotes CR must be followed by LF. LF-only
record endings are accepted by default, with an explicit allow_lf=false option.
Writer emits CRLF. EOF can terminate an unquoted or closed-quoted last record.
Reject quote inside an unquoted field and bytes after a closing quote other than
quote/comma/record ending. No whitespace trimming or permissive quote recovery.

Bytes are opaque, including NUL/high bytes; no UTF-8 validation/transcoding or BOM
stripping. This is a documented CSV dialect, not a strict RFC4180 TEXTDATA-byte
validator. No header inference, equal-column enforcement, type conversion,
custom delimiters, comments, automatic formula rewriting or whole-file table.
CSV quoting does not establish spreadsheet formula safety; applications own that.

Empty input has no rows. A blank record has zero fields (Python-csv convention).
A quoted empty field is one empty field. Trailing comma denotes a final empty
field. A trailing record ending creates no phantom row. Writer supports zero
fields as CRLF and quotes a sole empty field to preserve the distinction.
Reference grammar/conventions: https://www.rfc-editor.org/rfc/rfc4180 and Python
standard-library csv. Differences above are deliberate and tested explicitly.

## Public interface and ownership

- Limits: max_field_bytes (decoded bytes), max_row_bytes (raw wire bytes including
  delimiters/quotes/record ending), max_total_bytes (all accepted wire bytes in
  this reader or all emitted wire bytes in this writer), max_fields.
- Defaults: field 1 MiB, row 4 MiB, total 64 MiB, fields 4096. All zero limits are valid.
  Hard ceilings: field 16 MiB, row 64 MiB, total 2^60, fields 65536. Negative or above
  ceiling options are invalid. Limits are snapshotted at initialization.
- Row is a root owner of decoded bytes plus offset/length spans. field_count(row)
  reports the number of fields; field(row,index) takes a zero-based in-range index
  and returns a borrowed view (invalid indexing follows Goose bounds behavior).
  Retain a Row by not passing it as a later output. Views refer to that Row and
  can change or be invalidated when it is reused; finish reading them first.
- Reader, Writer and Row are caller-owned root owners, not ordinary copyable
  values. Reader stores partial bytes/spans directly, not a nested Row root. Do
  not modify, serialize or exchange internal fields. Default Reader/Writer states
  are inactive; roots cannot be copied, nested, reassigned or returned by value.
- init(Reader&, limits=default, allow_lf=true) and init(Writer&, limits=default)
  validate before mutation. Invalid initialization leaves old state unchanged;
  valid initialization resets counters and clears individual storage components.
  Capacity retention follows Goose runtime behavior, not an OS-memory guarantee.
- read(Reader&, chunk: const u8[:], Row&) returns Progress {step, consumed, status}.
  Step is NeedInput/Row/End/Error. It consumes at most one completed row, retains
  no input views, and stops exactly after that row's ending. Caller resumes at
  chunk[consumed..]. Empty chunks are allowed. Row output changes only on Row.
  Input chunks must not borrow output Row storage or Reader internals: replacing
  an output owner must not alter the caller's remaining input. Goose supports
  aliases; do not assume the compiler rejects every disallowed alias.
- finish(Reader&, Row&) signals EOF. It can emit one final unterminated Row, then
  End; repeated finish returns End. Read on a finished reader with nonempty input
  is InvalidState. Read(empty) on a finished reader returns End.
- Parser errors are sticky until init; subsequent operations consume zero bytes
  and return the first Status. Nonempty read after End also makes InvalidState
  sticky; subsequent finish/read return that error until init. Uninitialized
  reader operations similarly make InvalidState sticky. Writer failures do not
  poison its state. An emitted Row validates its prefix only: callers must drive
  the entire input through finish/End before claiming whole-input validity.
- write(Writer&, fields: const (const u8[:])[:], output: u8[>..]&) replaces output
  with exactly one encoded CRLF row. Preflight bounds before encoding; on any
  reported failure writer state and previous output are unchanged, permitting a
  corrected retry. A private scratch buffer avoids destructive input/output alias
  interactions where the compiler permits borrowing them at the call. Use the
  typed NO_FIELDS constant for a zero-field row (bare [] inference is conservative).

LF-only input in CRLF-only mode reports UnexpectedLf; a CR lacking its LF reports
ExpectedLf.

## Errors and accounting

Status {error, offset, record, field}: offset is zero-based absolute wire-byte
position, record/field are one-based. Reader errors point to the offending byte;
EOF errors point one past the accepted input. read.consumed excludes an offending
byte; valid prefix bytes remain counted and internal partial state is poisoned.
Success coordinates are unspecified. Writer errors identify the failing field
(and next record); offset is start of the unwritten row because no bytes escaped.
Errors: None, InvalidOptions, InvalidState, UnexpectedQuote, AfterQuote,
ExpectedLf, UnexpectedLf, UnclosedQuote, FieldLimit, RowLimit, TotalLimit, FieldCountLimit.
If multiple constraints fail simultaneously, precedence is unspecified.

No unbounded addition or counter wrap. Check subtraction budgets before accepting
bytes/appending spans or computing writer sizes. Check field-count capacity
before creating fields; a comma already implies an additional field. Reader
storage holds only its current row plus the caller's previous output capacity,
reused as independent components. Completed rows copy bytes/spans to the caller
before clearing partial storage, linear in total emitted bytes/fields. Writer
preflights then encodes into bounded scratch and copies to caller output. No
O(1) growable-buffer swap or copyable-root promise is made; std::swap aliases/
copies nonfixed values and is not used for ownership transfer. Prior caller
output capacity and previously used limits can affect retained capacity.
Logical limits do not imply exact allocator/RSS bounds; runtime allocation failure
follows Goose runtime behavior. No whole input copy, per-byte rescanning or growing
queue of rows. Reader O(input bytes), writer O(input bytes + fields + output bytes).
Writer uses bounded per-field quote metadata and copies safe runs.

## Validation and release gates

Public regressions for every split of representative CRLF/escaped-quote/UTF-8-byte
inputs, EOF variants, blank rows, malformed quotes, exact limits/overflow and
terminal state; output preservation and writer retry. Test retained-row ownership,
reuse/reset and all public entry paths. Canonical output may exceed reader
  limits when LF/unterminated rows gain CRLF or a sole empty field gains quotes;
  roundtrip checks distinguish valid writer bounds rejection from codec failure. Independent Python csv reader/writer
oracle for the shared dialect, plus explicit divergence cases; bounded seeded
public-interface mutation fuzzing and roundtrip checks. Do not label random fuzz
coverage as coverage-guided/native-libFuzzer coverage.

Instrument generated Goose/runtime C with GCC/Clang ASan/UBSan; check JIT, debug
and native public paths. Repeated independent interface/security/correctness/
performance/test-quality reviews. Profile before optimizing. Retain raw benchmark
samples with exact source/compiler/binary/flags/platform/fixture identities;
shared-host timing is not exclusive/isolation or universal superiority evidence.
CI runs correctness and benchmark smoke without timing thresholds; checks source
formatting rather than repairing it. Public immutable source/license/dependency,
anonymous clone/import and hosted CI evidence precede final owner handoff. Parent
registration and sibling sources remain owned by their existing threads.

# Security policy

Experimental module, initially validated on Linux x86-64 only. Report sensitive
vulnerabilities privately through GitHub's vulnerability reporting facility when
available, or contact the maintainer privately before public disclosure.

Limits constrain logical accepted/emitted bytes, fields and current-row storage.
They do not promise exact allocator/RSS bounds or recoverable runtime allocation
failure. Do not modify or deserialize internal Reader/Writer/Row state. Public
root owners follow Goose's lifetime and bounds rules; field indices must be valid.

An emitted row validates only a prefix. Applications must finish the complete
input successfully before committing whole-file decisions. Bytes are opaque:
encoding validation, headers/types, equal column counts and application policy
remain caller-owned. CSV quoting does not neutralize spreadsheet formulas.

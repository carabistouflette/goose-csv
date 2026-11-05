#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Independent byte fixtures and complete output expectations for comparison drivers."""
from __future__ import annotations
import csv
import hashlib
import io
import random
import struct

MOD = 2147483647
SEED = 712911
csv.field_size_limit(16777216)


def canonical(rows):
    out = io.StringIO(newline="")
    writer = csv.writer(out, lineterminator="\r\n")
    for row in rows:
        writer.writerow([field.decode("latin1") for field in row])
    return out.getvalue().encode("latin1")


def bundle(rows):
    out = bytearray(b"GCFIELDS" + struct.pack("<I", len(rows)))
    for row in rows:
        out.extend(struct.pack("<I", len(row)))
        for field in row:
            out.extend(struct.pack("<I", len(field)))
            out.extend(field)
    return bytes(out)


def mix(value, part):
    return (value * 257 + part + 1) % MOD


def signature(fields):
    value = len(fields)
    for field in fields:
        value = mix(value, len(field))
        if field:
            for byte in (field[0], field[len(field) // 2], field[-1]):
                value = mix(value, byte)
    return value


def wire_signature(wire):
    value = len(wire)
    if wire:
        for byte in (wire[0], wire[len(wire) // 2], wire[-1]):
            value = mix(value, byte)
    return value


def summary(rows, operation, repeats=1):
    if operation == "parse":
        checksum = sum(map(signature, rows))
    else:
        checksum = sum(wire_signature(canonical([row])) for row in rows)
    return (len(rows) * repeats, len(canonical(rows)) * repeats, checksum * repeats % MOD)


def workloads():
    # Preserve all six original fixture contents, plus variable data and varied widths.
    original = {
        "simple": [b"alpha", b"beta", b"gamma", b"delta", b"epsilon", b"zeta", b"eta", b"theta"],
        "quoted": [b"alpha,beta", b'say "hello"', b"line1\r\nline2", b"tail"],
        "empty256": [b""] * 256,
        "utf8": ["café".encode(), "東京".encode(), "🙂".encode(), b""],
        "binary": [bytes(range(256)), b"x\0y"],
        "long256k": [b"x" * 262144],
    }
    found = {name: [row] * max(1, 65536 // len(canonical([row]))) for name, row in original.items()}
    # Escapes span caller/output buffers and the native 64 KiB internal buffer.
    found["long-escaped"] = [[(b'x,"a\r\nb"' * 18000) + b"tail", b"last"]]
    found["quote-cluster"] = [[b"x" * 8192 + b'"' * 128 + b"tail" * 2048, b"last"]] * 4
    rng = random.Random(SEED)
    found["mixed-records"] = [
        [str(i).encode(), f"account-{rng.randrange(1000000):06d}".encode(),
         f"{rng.randrange(-100000, 100000)}.{rng.randrange(100):02d}".encode(),
         rng.choice([b"active", b"", b"review, pending", b'notes "quoted"', b"line1\r\nline2"]),
         bytes(rng.randrange(32, 127) for _ in range(rng.randrange(4, 35)))]
        for i in range(1000)
    ]
    found["wide-variable"] = [[f"r{i}-c{j}-{rng.randrange(10000)}".encode() for j in range(1024)] for i in range(5)]
    found["escape-heavy"] = [[bytes(rng.choice(b'a,"\r\n') for _ in range(rng.randrange(10, 100)))
                               for _ in range(8)] for _ in range(100)]
    for rows in found.values():
        encoded = canonical(rows)
        parsed = [[field.encode("latin1") for field in row]
                  for row in csv.reader(io.StringIO(encoded.decode("latin1"), newline=""), strict=True)]
        assert parsed == rows
        assert encoded.endswith(b"\r\n")
        assert len(encoded) <= 8388608 and len(bundle(rows)) <= 8388608
    return found


def feature_cases():
    return {
        "empty-input": (b"", [], None),
        "blank-crlf": (b"\r\n", [[]], None),
        "blank-lf": (b"\n", [[]], None),
        "sole-empty": (b'""\r\n', [[b""]], None),
        "trailing-empty": (b"a,\r\n", [[b"a", b""]], None),
        "spaces": (b' a ," b "\r\n', [[b" a ", b" b "]], None),
        "unterminated-valid": (b'a,"b"', [[b"a", b"b"]], None),
        "multiline": (b'"a\r\nb\nc",d\r\n', [[b"a\r\nb\nc", b"d"]], None),
        "opaque-bytes": (canonical([[bytes(range(256)), b"\0"]]), [[bytes(range(256)), b"\0"]], None),
        "initial-bom": (b"\xef\xbb\xbfa,b\r\n", [[b"\xef\xbb\xbfa", b"b"]], None),
        "bare-quote": (b'a"b,c\r\n', [], "UnexpectedQuote"),
        "post-quote": (b'"a"x,b\r\n', [], "AfterQuote"),
        "unclosed-quote": (b'"a,b', [], "UnclosedQuote"),
        "bare-cr": (b"a\rb\r\n", [], "ExpectedLf"),
        "cr-at-eof": (b"a\r", [], "ExpectedLf"),
        "quoted-cr-eof": (b'"a\r"', [[b"a\r"]], None),
    }


def identity(data):
    return {"bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}

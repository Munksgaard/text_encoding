"""Generates differential test expectations with encoding_rs.

Usage:

    cargo build --offline --release --manifest-path dev/oracle/Cargo.toml
    python3 -I dev/oracle_vectors.py dev/oracle/target/release/oracle \\
        > test/fixtures/oracle/sweeps.tsv

The inputs are built deterministically, here and in test/oracle_test.gleam,
which must stay in step. Each line is:

    <encoding name> <sweep> <number of inputs> <SHA-256 of the results>

Each input is decoded on its own. The results are, for each input in order,
its decoding without BOM handling as UTF-8, then the byte 0xFF, then the
number of errors as a 32-bit big-endian integer.

With `--dump ENCODING SWEEP`, prints each input and result instead, to find
the input behind a mismatch.
"""

import hashlib
import itertools
import subprocess
import sys

ENCODINGS = [
    "UTF-8", "IBM866", "ISO-8859-2", "ISO-8859-3", "ISO-8859-4", "ISO-8859-5",
    "ISO-8859-6", "ISO-8859-7", "ISO-8859-8", "ISO-8859-8-I", "ISO-8859-10",
    "ISO-8859-13", "ISO-8859-14", "ISO-8859-15", "ISO-8859-16", "KOI8-R",
    "KOI8-U", "macintosh", "windows-874", "windows-1250", "windows-1251",
    "windows-1252", "windows-1253", "windows-1254", "windows-1255",
    "windows-1256", "windows-1257", "windows-1258", "x-mac-cyrillic", "GBK",
    "gb18030", "Big5", "EUC-JP", "ISO-2022-JP", "Shift_JIS", "EUC-KR",
    "replacement", "UTF-16BE", "UTF-16LE", "x-user-defined",
]

# Bytes with a role in some encoding, used for half of the random bytes.
ALPHABET = [
    0x00, 0x0E, 0x0F, 0x1B, 0x20, 0x24, 0x28, 0x30, 0x39, 0x40, 0x41, 0x42,
    0x49, 0x4A, 0x5C, 0x7E, 0x7F, 0x80, 0x81, 0x8E, 0x8F, 0xA0, 0xA1, 0xBB,
    0xBF, 0xC2, 0xD8, 0xDC, 0xDF, 0xE0, 0xED, 0xEF, 0xF0, 0xF4, 0xFC, 0xFD,
    0xFE, 0xFF,
]

RANDOM_INPUTS = 2000
MODULUS = 2147483647


def single(_encoding):
    return [bytes([b]) for b in range(256)]


def pairs(_encoding):
    return [bytes([lead, trail]) for lead in range(256) for trail in range(256)]


def euc_jp_triples(_encoding):
    return [bytes([0x8F, second, third]) for second in range(256) for third in range(256)]


def gb18030_fours(_encoding):
    # Every four-byte sequence is complete, so they are batched by first byte.
    return [
        b"".join(
            bytes([first, second, third, fourth])
            for second in range(0x30, 0x3A)
            for third in range(0x81, 0xFF)
            for fourth in range(0x30, 0x3A)
        )
        for first in range(0x81, 0xFF)
    ]


ESCAPES = [b"\x1b(B", b"\x1b(J", b"\x1b(I", b"\x1b$@", b"\x1b$B"]


def iso_2022_jp_states(_encoding):
    return [
        escape + bytes([lead, trail])
        for escape in ESCAPES
        for lead in range(256)
        for trail in range(256)
    ]


# The bytes of the escape sequences, and a byte that is valid in every state.
ESCAPE_ALPHABET = [0x1B, 0x24, 0x28, 0x42, 0x4A, 0x49, 0x21]


def iso_2022_jp_escapes(_encoding):
    return [
        bytes(sequence)
        for length in range(1, 7)
        for sequence in itertools.product(ESCAPE_ALPHABET, repeat=length)
    ]


def random_inputs(encoding):
    state = (ENCODINGS.index(encoding) + 1) * 7919

    def next_value():
        nonlocal state
        state = state * 48271 % MODULUS
        return state

    inputs = []
    for _ in range(RANDOM_INPUTS):
        length = next_value() % 25
        data = bytearray()
        for _ in range(length):
            r = next_value()
            if r % 2 == 0:
                data.append(ALPHABET[r // 2 % len(ALPHABET)])
            else:
                data.append(r // 2 % 256)
        inputs.append(bytes(data))
    return inputs


def sweeps():
    for encoding in ENCODINGS:
        yield encoding, "single", single
        yield encoding, "pairs", pairs
        yield encoding, "random", random_inputs
    yield "EUC-JP", "euc_jp_triples", euc_jp_triples
    yield "gb18030", "gb18030_fours", gb18030_fours
    yield "GBK", "gb18030_fours", gb18030_fours
    yield "ISO-2022-JP", "iso_2022_jp_states", iso_2022_jp_states
    yield "ISO-2022-JP", "iso_2022_jp_escapes", iso_2022_jp_escapes


def decode_all(oracle, requests):
    stdin = "".join("%s %s\n" % (name, data.hex()) for name, data in requests)
    result = subprocess.run([oracle], input=stdin, capture_output=True, text=True, check=True)
    outputs = []
    for line in result.stdout.splitlines():
        text, errors = line.split(" ")
        outputs.append((bytes.fromhex(text), int(errors)))
    assert len(outputs) == len(requests)
    return outputs


def main():
    oracle = sys.argv[1]
    if len(sys.argv) > 2 and sys.argv[2] == "--dump":
        wanted = (sys.argv[3], sys.argv[4])
        for encoding, sweep, build in sweeps():
            if (encoding, sweep) == wanted:
                inputs = build(encoding)
                outputs = decode_all(oracle, [(encoding, data) for data in inputs])
                for data, (text, errors) in zip(inputs, outputs):
                    print(data.hex(), text.hex(), errors)
        return
    plan = [(encoding, sweep, build(encoding)) for encoding, sweep, build in sweeps()]
    requests = [(encoding, data) for encoding, _, inputs in plan for data in inputs]
    outputs = iter(decode_all(oracle, requests))
    print("# Generated by dev/oracle_vectors.py with encoding_rs 0.8.35.")
    for encoding, sweep, inputs in plan:
        digest = hashlib.sha256()
        for _ in inputs:
            text, errors = next(outputs)
            digest.update(text + b"\xff" + errors.to_bytes(4, "big"))
        print("\t".join([encoding, sweep, str(len(inputs)), digest.hexdigest()]))


main()

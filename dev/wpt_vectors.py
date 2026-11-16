"""Extracts decoder test vectors from the web-platform-tests encoding/
directory, by reading the literal data in the test files (they are not run).

Usage: python3 -I dev/wpt_vectors.py WPT_CHECKOUT > test/fixtures/wpt/vectors.tsv

Each output line is tab-separated:

    <label> <fatal 0|1> <input as hex> <expected UTF-8 as hex, or !>

"!" means TextDecoder with `fatal: true` must throw. Tests written as
procedures rather than data (byte order marks, ignoreBOM, the "mistakes"
tests, invalid labels) are ported by hand in test/wpt_test.gleam.
"""

import pathlib
import re
import sys

ESCAPE = re.compile(r"\\u\{([0-9a-fA-F]+)\}|\\u([0-9a-fA-F]{4})|\\x([0-9a-fA-F]{2})|\\(.)")
SIMPLE = {"n": "\n", "r": "\r", "t": "\t", "0": "\0", "\\": "\\", "'": "'", '"': '"'}


def js_string(literal):
    """Decodes the body of a JavaScript string literal. Surrogate pairs
    written as two \\u escapes are joined."""

    def replace(match):
        braced, four, two, other = match.groups()
        if braced:
            return chr(int(braced, 16))
        if four:
            return chr(int(four, 16))
        if two:
            return chr(int(two, 16))
        return SIMPLE[other]

    text = ESCAPE.sub(replace, literal)
    return text.encode("utf-16", "surrogatepass").decode("utf-16")


def int_list(literal):
    return [int(item, 0) for item in literal.replace("\n", " ").split(",") if item.strip()]


def byte_list(literal):
    return bytes(int_list(literal))


STRING = r"""(?:"((?:[^"\\]|\\.)*)"|'((?:[^'\\]|\\.)*)')"""


def string_group(match, first):
    value = match.group(first)
    return value if value is not None else match.group(first + 1)


def line(label, fatal, data, expected):
    expected = "!" if expected is None else expected.encode("utf-8").hex()
    return "\t".join([label, "1" if fatal else "0", data.hex(), expected])


def decode_calls(path, labels):
    """decode([bytes], "expected", ...) calls."""
    pattern = re.compile(r"^decode\(\s*\[([^\]]*)\],\s*" + STRING, re.M)
    for match in pattern.finditer(path.read_text()):
        data = byte_list(match.group(1))
        expected = js_string(string_group(match, 2))
        for label in labels:
            yield line(label, False, data, expected)


def bad_entries(path, with_expected):
    """Entries { encoding: '..', input: [..], expected: '..' } of `bad`."""
    text = path.read_text()
    pattern = re.compile(
        r"encoding:\s*'([^']*)',\s*input:\s*\[([^\]]*)\]"
        + (r",\s*expected:\s*" + STRING if with_expected else ""),
        re.S,
    )
    for match in pattern.finditer(text):
        label, data = match.group(1), byte_list(match.group(2))
        if with_expected:
            yield line(label, False, data, js_string(string_group(match, 3)))
        yield line(label, True, data, None)


def single_asserts(path):
    """assert_equals(new TextDecoder(label?).decode(new Uint8Array([..])), "..")."""
    pattern = re.compile(
        r"assert_equals\(new TextDecoder\((?:\"([^\"]*)\")?\)\.decode\("
        r"new Uint8Array\(\[([^\]]*)\]\)\),\s*" + STRING
    )
    for match in pattern.finditer(path.read_text()):
        label = match.group(1) or "utf-8"
        yield line(label, False, byte_list(match.group(2)), js_string(string_group(match, 3)))


def gbk_pointers(path):
    """The GBK pointer table: both arrays, decoded as the test does."""
    text = path.read_text()
    pointers = re.search(r"const gbkPointers = \[([^\]]*)\]", text).group(1)
    code_points = re.search(r"const codePoints = \[([^\]]*)\]", text).group(1)
    for pointer, code_point in zip(int_list(pointers), int_list(code_points)):
        trail = pointer % 190
        offset = 0x40 if trail < 0x3F else 0x41
        data = bytes([pointer // 190 + 0x81, trail + offset])
        yield line("gbk", False, data, chr(code_point))


def main():
    root = pathlib.Path(sys.argv[1]) / "encoding"
    schinese = root / "legacy-mb-schinese"
    lines = []
    lines += decode_calls(schinese / "gb18030" / "gb18030-decoder.any.js", ["gb18030", "gbk"])
    lines += gbk_pointers(schinese / "gbk" / "gbk-decoder.any.js")
    lines += decode_calls(root / "iso-2022-jp-decoder.any.js", ["iso-2022-jp"])
    lines += bad_entries(root / "textdecoder-fatal.any.js", with_expected=False)
    lines += bad_entries(root / "textdecoder-utf16-surrogates.any.js", with_expected=True)
    lines += single_asserts(root / "textdecoder-eof.any.js")
    unique = dict.fromkeys(lines)
    for entry in unique:
        print(entry)
    print(len(unique), "vectors", file=sys.stderr)


main()

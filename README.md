# text_encoding

The decoders of the [WHATWG Encoding Standard](https://encoding.spec.whatwg.org/)
in pure Gleam: UTF-8, UTF-16, the 28 legacy single-byte encodings, and the
Chinese, Japanese and Korean encodings (gb18030/GBK, Big5, EUC-JP,
ISO-2022-JP, Shift_JIS, EUC-KR). These are the encodings web browsers
support, decoded the way browsers decode them. It runs on Erlang and
JavaScript, and has no native dependencies.

```gleam
import text_encoding

pub fn main() {
  let assert Ok(encoding) = text_encoding.get("Shift_JIS")
  text_encoding.decode(<<0x82, 0xA0, 0x82, 0xA2>>, encoding)
  // -> "あい"

  // An error count, and control over byte order marks.
  let decoded =
    text_encoding.decode_with(<<0x82, 0xFF>>, encoding, text_encoding.StripBom)
  decoded.text
  // -> "\u{FFFD}"
  decoded.errors
  // -> 1
}
```

## The API follows the standard

| Standard | text_encoding |
| --- | --- |
| [get an encoding](https://encoding.spec.whatwg.org/#concept-encoding-get) | `get(label)` |
| encoding's name | `name(encoding)` |
| [get an output encoding](https://encoding.spec.whatwg.org/#get-an-output-encoding) | `output_encoding(encoding)` |
| [decode](https://encoding.spec.whatwg.org/#decode) | `decode(bytes, fallback)` |
| [BOM sniff](https://encoding.spec.whatwg.org/#bom-sniff) | `bom_sniff(bytes)` |
| [UTF-8 decode](https://encoding.spec.whatwg.org/#utf-8-decode) | `utf8_decode(bytes)` |
| [UTF-8 decode without BOM](https://encoding.spec.whatwg.org/#utf-8-decode-without-bom) | `utf8_decode_without_bom(bytes)` |
| [UTF-8 decode without BOM or fail](https://encoding.spec.whatwg.org/#utf-8-decode-without-bom-or-fail) | `utf8_decode_without_bom_or_fail(bytes)` |
| `TextDecoder` with `fatal` and `ignoreBOM` | `decode_with(bytes, encoding, StripBom \| KeepBom)` and `Decoded.errors` |

Decoding takes a complete `BitArray`; bits after the last whole byte are
one error. Streaming and the encoders are not implemented yet. Labels outside the standard (`utf-7`, `utf-32`, EBCDIC and
DOS code pages) are not supported, as the standard requires: `get` returns
`Error(Nil)` for them.

## How it is tested

- **web-platform-tests**: vectors extracted from the gb18030, GBK,
  ISO-2022-JP, UTF-8, UTF-16 and Big5 decoder tests, and the label and
  byte order mark tests, ported by hand.
- **Differential tests against [encoding_rs](https://crates.io/crates/encoding_rs)**,
  Firefox's implementation, compared on the text and the exact error
  count: every 1- and 2-byte input in every encoding, every 3-byte JIS X
  0212 sequence in EUC-JP, every ISO-2022-JP escape followed by every
  2-byte input, every escape-byte-escape triple and every sequence of up to
  6 escape bytes, and 2,000 seeded random inputs per encoding, each decoded
  on its own; and every 4-byte gb18030 sequence, in batches.
- **Properties** with [qcheck](https://hex.pm/packages/qcheck), and
  **doubling tests** that check each decoder runs in linear time.

The tables are generated from a pinned commit of the standard by
`dev/generate.py`, and CI checks that regenerating them changes nothing.
See [docs/assumptions.md](docs/assumptions.md) for the design.

## Licence

Apache-2.0. The generated tables contain data from the WHATWG Encoding
Standard, under the BSD 3-Clause License ([LICENSE-WHATWG](LICENSE-WHATWG)).

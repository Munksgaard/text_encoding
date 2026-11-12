# text_encoding: design and assumptions

A pure Gleam implementation of the decoding half of the WHATWG Encoding
Standard, for the Erlang and JavaScript targets. It is written to be used by
`eml`, but is independent of it.

## Source of truth

- The WHATWG Encoding Standard, pinned at commit
  `be17ac5c49881336538acfc7b40dba3c8009144b` (2026-10-19). The same commit
  that eml's single-byte tables were generated from.
- Behaviour that the spec leaves to implementations (only performance) is
  decided here. Everything observable follows the spec: the decoded string,
  and whether an error occurred.
- Oracle for differential tests: `encoding_rs` 0.8.35 (Firefox's
  implementation), and the web-platform-tests `encoding/` directory.

## Scope (v0.1)

In:

- All 40 encodings of the standard, including `replacement`, `UTF-16BE`,
  `UTF-16LE` and `x-user-defined`.
- "get an encoding" (labels), encoding names, "get an output encoding".
- The hooks: `decode` (BOM sniffing), `UTF-8 decode`, `UTF-8 decode without
  BOM`, `UTF-8 decode without BOM or fail`, and `BOM sniff`.
- A lower-level `decode_with` with the TextDecoder BOM options and an error
  count, which covers TextDecoder's `fatal` and `ignoreBOM`.

Out, for now (each can be added without breaking the API):

- Encoders. The standard defines them (UTF-8 and the legacy ones for HTML
  forms and URLs), but eml only needs decoding. Planned as the next
  milestone of this library.
- Streaming (TextDecoder's `stream: true`). Decoding takes a complete
  `BitArray`. A streaming decoder would need to keep at most 3 bytes plus
  ISO-2022-JP's state between chunks.
- Encodings and labels outside the standard (UTF-7, UTF-32, EBCDIC, DOS code
  pages). The standard forbids them for user agents; a caller can handle
  them before calling this library. Labels that are not in the standard are
  `Error(Nil)`, as "get an encoding" returns failure.

## API

```gleam
pub type Encoding { Utf8 Ibm866 Iso88592 ... ShiftJis EucKr Replacement Utf16Be Utf16Le XUserDefined }

pub fn get(label: String) -> Result(Encoding, Nil)   // get an encoding
pub fn name(encoding: Encoding) -> String            // "Shift_JIS", "UTF-8", ...
pub fn output_encoding(encoding: Encoding) -> Encoding
pub fn bom_sniff(bytes: BitArray) -> Option(Encoding)

pub fn decode(bytes: BitArray, fallback: Encoding) -> String
pub fn utf8_decode(bytes: BitArray) -> String
pub fn utf8_decode_without_bom(bytes: BitArray) -> String
pub fn utf8_decode_without_bom_or_fail(bytes: BitArray) -> Result(String, Nil)

pub type Bom { SniffBom StripBom KeepBom }
pub type Decoded { Decoded(text: String, encoding: Encoding, errors: Int) }
pub fn decode_with(bytes: BitArray, encoding: Encoding, bom: Bom) -> Decoded
```

- `Encoding` is a public custom type so callers can match on it. The list of
  encodings has not changed since 2017 (only labels were added, in 2020);
  adding one would be a breaking change, which matches its rarity.
- `get` follows the spec exactly: it removes leading and trailing ASCII
  whitespace (TAB, LF, FF, CR, SPACE) and compares with ASCII case
  insensitivity. Unicode case folding is not used, so `"\u{212A}oi8-r"`
  (KELVIN SIGN) is not a label, although Unicode lowercases it to "k".
- `decode_with`:
  - `SniffBom` is the spec's `decode`: a UTF-8, UTF-16BE or UTF-16LE BOM
    overrides `encoding`, and `Decoded.encoding` is the encoding used. This
    replaces the separate "BOM sniff then decode" dance the spec describes.
  - `StripBom` is TextDecoder's default: for UTF-8 and UTF-16BE/LE a leading
    U+FEFF in the output is removed; the encoding is never changed.
  - `KeepBom` is TextDecoder's `ignoreBOM: true`.
  - `errors` is the number of errors the decoder returned, which is the
    number of U+FFFD it inserted in replacement mode. Fatal mode is
    `errors > 0`. Nothing is lost by always decoding to the end; the cost is
    only time on bad input.
- `replacement` decodes non-empty input to one U+FFFD (one error), and empty
  input to "". `get` returns it for its labels ("iso-2022-kr", ...), as the
  spec's "get an encoding" does; TextDecoder's extra RangeError for it is an
  API decision left to callers.

## Implementation

- Decoders are written in "lookahead" form over the input instead of the
  spec's byte-at-a-time handler with an I/O queue. Each "restore" in the
  spec becomes "consume fewer bytes". The two are equivalent; the
  equivalence is checked by differential tests against encoding_rs over all
  1- and 2-byte inputs and random structured inputs. ISO-2022-JP keeps its
  state (`decoder state` = `output state` outside escapes, and the `output`
  flag) as loop parameters.
- Performance rules (from eml):
  - Every loop over input is direct self-recursion, so it compiles to a loop
    on JavaScript. No mutual recursion over input, no recursion through
    callbacks.
  - Output is a reversed list of UTF-8 chunks, concatenated once. Runs of
    ASCII (and, for UTF-8, valid sequences) are sliced from the input rather
    than copied byte by byte.
  - Decoding is linear in the input size; a perf test compares n and 8n.
- Indexes are BitArray constants generated from `indexes.json`: 16 bits per
  entry for BMP-only indexes, 24 bits for Big5 (it has supplementary-plane
  code points). Code point 0 means "no entry": no index maps a pointer to
  U+0000. Lookup is a constant-time slice. Each index lives in its own
  module with a lookup function, so the data is stored once and an unused
  index is never loaded on the BEAM in interactive mode.
- `index gb18030 ranges` (207 entries) is a sorted BitArray searched with a
  binary search.
- UTF-8 output: the final concatenated bytes are valid UTF-8 by
  construction. On JavaScript, `bit_array.to_string` uses `TextDecoder`,
  which removes a leading BOM; that is undone, as in eml.

## Tests

- web-platform-tests `encoding/` vectors ported by hand: labels, BOM
  handling, UTF-8 and UTF-16 errors and surrogates, single-byte, and the
  gb18030, Big5, EUC-JP, ISO-2022-JP, Shift_JIS and EUC-KR decoder tests.
  BSD-3-Clause, with notice.
- Index round trips: for every entry of every index, the byte sequence that
  the decoder maps to that pointer decodes to that code point. The test
  vectors are generated from `indexes.json`, not from the decoder.
- Differential vectors from encoding_rs, generated by `dev/oracle`: every
  1-byte and 2-byte input (with ASCII before and after, to check restores)
  for every encoding, and seeded random inputs biased towards each
  encoding's structural bytes. Committed as hashes of the expected output
  for the large sweeps, and as full expected text for the random ones.
- Properties (qcheck): never crashes; ASCII input decodes to itself for
  ASCII-compatible encodings; `errors == 0` exactly when the strict hook
  succeeds.
- Performance: n vs 8n for each family, ratio < 32 (as in eml).

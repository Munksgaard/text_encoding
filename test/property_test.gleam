//// Properties over generated input, for every encoding.

import gleam/bit_array
import gleam/list
import gleam/string
import qcheck
import text_encoding.{type Encoding, KeepBom}

/// Bytes from a small alphabet of bytes with a role in some encoding, mixed
/// with arbitrary bytes.
fn bytes() -> qcheck.Generator(BitArray) {
  let structural =
    qcheck.from_generators(qcheck.constant(0x1B), [
      qcheck.constant(0x24),
      qcheck.constant(0x28),
      qcheck.constant(0x30),
      qcheck.constant(0x42),
      qcheck.constant(0x80),
      qcheck.constant(0x81),
      qcheck.constant(0x8E),
      qcheck.constant(0x8F),
      qcheck.constant(0xA1),
      qcheck.constant(0xD8),
      qcheck.constant(0xDC),
      qcheck.constant(0xE0),
      qcheck.constant(0xF0),
      qcheck.constant(0xFE),
      qcheck.constant(0xFF),
    ])
  qcheck.generic_list(
    qcheck.from_generators(structural, [qcheck.bounded_int(0, 255)]),
    qcheck.bounded_int(0, 40),
  )
  |> qcheck.map(fn(bytes) {
    bytes |> list.map(fn(b) { <<b>> }) |> bit_array.concat
  })
}

fn encoding() -> qcheck.Generator(Encoding) {
  let assert [first, ..rest] = text_encoding.encodings
  qcheck.from_generators(
    qcheck.constant(first),
    list.map(rest, qcheck.constant),
  )
}

fn config() {
  qcheck.default_config() |> qcheck.with_test_count(2000)
}

/// Counts code points, not grapheme clusters: U+FFFD followed by a
/// combining mark is one cluster.
fn count_replacements(text: String) -> Int {
  text
  |> string.to_utf_codepoints
  |> list.count(fn(c) { string.utf_codepoint_to_int(c) == 0xFFFD })
}

/// Every error inserts one U+FFFD, and there are no other U+FFFD unless the
/// input could encode one.
pub fn errors_are_replacements_test() {
  use #(encoding, input) <- qcheck.run(
    config(),
    qcheck.tuple2(encoding(), bytes()),
  )
  let decoded = text_encoding.decode_with(input, encoding, KeepBom)
  assert decoded.errors <= count_replacements(decoded.text)
  case encoding {
    text_encoding.Replacement -> Nil
    _ -> {
      assert list.length(string.to_utf_codepoints(decoded.text))
        <= bit_array.byte_size(input) * 2
    }
  }
}

/// ASCII decodes to itself, except in ISO-2022-JP (where ESC, SO and SI are
/// special), UTF-16 and replacement.
pub fn ascii_is_unchanged_test() {
  use #(encoding, codes) <- qcheck.run(
    config(),
    qcheck.tuple2(
      encoding(),
      qcheck.generic_list(
        qcheck.bounded_int(0, 0x7F),
        qcheck.bounded_int(0, 40),
      ),
    ),
  )
  let input = codes |> list.map(fn(b) { <<b>> }) |> bit_array.concat
  case encoding {
    text_encoding.Iso2022Jp
    | text_encoding.Utf16Be
    | text_encoding.Utf16Le
    | text_encoding.Replacement -> Nil
    _ -> {
      let assert Ok(expected) = bit_array.to_string(input)
      assert text_encoding.decode_with(input, encoding, KeepBom)
        == text_encoding.Decoded(expected, encoding, 0)
    }
  }
}

/// Valid UTF-8 decodes to itself, and the strict hook agrees with the
/// error count.
pub fn utf8_agrees_with_strict_hook_test() {
  use input <- qcheck.run(config(), bytes())
  let decoded = text_encoding.decode_with(input, text_encoding.Utf8, KeepBom)
  case text_encoding.utf8_decode_without_bom_or_fail(input) {
    Ok(text) -> {
      assert decoded == text_encoding.Decoded(text, text_encoding.Utf8, 0)
    }
    Error(_) -> {
      assert decoded.errors > 0
    }
  }
}

/// UTF-16 of any string decodes back to it.
pub fn utf16_round_trip_test() {
  use text <- qcheck.run(config(), qcheck.string())
  let units =
    text
    |> string.to_utf_codepoints
    |> list.flat_map(fn(c) {
      let c = string.utf_codepoint_to_int(c)
      case c > 0xFFFF {
        True -> {
          let c = c - 0x10000
          [0xD800 + c / 0x400, 0xDC00 + c % 0x400]
        }
        False -> [c]
      }
    })
  let be = units |> list.map(fn(u) { <<u:16-big>> }) |> bit_array.concat
  let le = units |> list.map(fn(u) { <<u:16-little>> }) |> bit_array.concat
  assert text_encoding.decode_with(be, text_encoding.Utf16Be, KeepBom).text
    == text
  assert text_encoding.decode_with(le, text_encoding.Utf16Le, KeepBom).text
    == text
}

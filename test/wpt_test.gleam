//// Test vectors from the web-platform-tests encoding/ directory
//// (https://github.com/web-platform-tests/wpt, BSD 3-Clause License).
//// test/fixtures/wpt/vectors.tsv is extracted by dev/wpt_vectors.py; the
//// tests written as procedures are ported by hand below.

import gleam/bit_array
import gleam/list
import gleam/string
import support.{hex}
import text_encoding.{type Encoding, KeepBom, StripBom}

/// TextDecoder(label, {fatal}).decode(bytes), returning Error(Nil) where
/// TextDecoder throws.
fn text_decoder(label: String, fatal: Bool, bytes: BitArray, bom) {
  let assert Ok(encoding) = text_encoding.get(label)
  let decoded = text_encoding.decode_with(bytes, encoding, bom)
  case fatal && decoded.errors > 0 {
    True -> Error(Nil)
    False -> Ok(decoded.text)
  }
}

pub fn extracted_vectors_test() {
  let failures =
    support.fixture_lines("test/fixtures/wpt/vectors.tsv")
    |> list.filter_map(fn(fields) {
      let assert [label, fatal, input, expected] = fields
      let expected = case expected {
        "!" -> Error(Nil)
        _ -> {
          let assert Ok(text) = bit_array.to_string(hex(expected))
          Ok(text)
        }
      }
      let actual = text_decoder(label, fatal == "1", hex(input), StripBom)
      case actual == expected {
        True -> Error(Nil)
        False -> Ok(#(label, fatal, input, expected, actual))
      }
    })
  assert failures == []
}

const bom_string = "z\u{A2}\u{6C34}\u{1D11E}\u{10FFFD}"

const bom_cases = [
  #("utf-8", <<0xEF, 0xBB, 0xBF>>, <<
    0x7A, 0xC2, 0xA2, 0xE6, 0xB0, 0xB4, 0xF0, 0x9D, 0x84, 0x9E, 0xF4, 0x8F, 0xBF,
    0xBD,
  >>),
  #("utf-16le", <<0xFF, 0xFE>>, <<
    0x7A, 0x00, 0xA2, 0x00, 0x34, 0x6C, 0x34, 0xD8, 0x1E, 0xDD, 0xFF, 0xDB, 0xFD,
    0xDF,
  >>),
  #("utf-16be", <<0xFE, 0xFF>>, <<
    0x00, 0x7A, 0x00, 0xA2, 0x6C, 0x34, 0xD8, 0x34, 0xDD, 0x1E, 0xDB, 0xFF, 0xDF,
    0xFD,
  >>),
]

// textdecoder-byte-order-marks.any.js
pub fn byte_order_marks_test() {
  list.each(bom_cases, fn(case_) {
    let #(label, bom, bytes) = case_
    assert text_decoder(label, False, bytes, StripBom) == Ok(bom_string)
    assert text_decoder(label, False, <<bom:bits, bytes:bits>>, StripBom)
      == Ok(bom_string)
    list.each(bom_cases, fn(other) {
      case other.0 == label {
        True -> Nil
        False -> {
          let mismatched = <<other.1:bits, bytes:bits>>
          assert text_decoder(label, False, mismatched, StripBom)
            != Ok(bom_string)
        }
      }
    })
  })
}

// textdecoder-ignorebom.any.js
pub fn ignore_bom_test() {
  [
    #("utf-8", <<0xEF, 0xBB, 0xBF, 0x61, 0x62, 0x63>>),
    #("utf-16le", <<0xFF, 0xFE, 0x61, 0x00, 0x62, 0x00, 0x63, 0x00>>),
    #("utf-16be", <<0xFE, 0xFF, 0x00, 0x61, 0x00, 0x62, 0x00, 0x63>>),
  ]
  |> list.each(fn(case_) {
    let #(label, bytes) = case_
    assert text_decoder(label, False, bytes, KeepBom) == Ok("\u{FEFF}abc")
    assert text_decoder(label, False, bytes, StripBom) == Ok("abc")
  })
}

fn utf16(units: List(Int), big_endian: Bool) -> BitArray {
  list.fold(units, <<>>, fn(acc, unit) {
    case big_endian {
      True -> <<acc:bits, unit:16-big>>
      False -> <<acc:bits, unit:16-little>>
    }
  })
}

fn from_units(units: List(Int)) -> String {
  units
  |> list.filter_map(string.utf_codepoint)
  |> string.from_utf_codepoints
}

// textdecoder-mistakes.any.js
pub fn mistakes_test() {
  [
    #(<<0, 254, 255>>, [0, 0xFFFD, 0xFFFD]),
    #(<<0x80>>, [0xFFFD]),
    #(<<0xF0, 0x90, 0x80>>, [0xFFFD]),
    #(<<0xF0, 0x80, 0x80>>, [0xFFFD, 0xFFFD, 0xFFFD]),
  ]
  |> list.each(fn(case_) {
    assert text_decoder("utf-8", False, case_.0, StripBom)
      == Ok(from_units(case_.1))
  })
  [
    #([0x61, 0x62, 0xD800, 0x77, 0x78], [0x61, 0x62, 0xFFFD, 0x77, 0x78]),
    #([0xD800], [0xFFFD]),
    #([0xD800, 0xD800], [0xFFFD, 0xFFFD]),
    #([0x61, 0x62, 0xDFFF, 0x77, 0x78], [0x61, 0x62, 0xFFFD, 0x77, 0x78]),
    #([0xDFFF, 0xD800], [0xFFFD, 0xFFFD]),
  ]
  |> list.each(fn(case_) {
    assert text_decoder("utf-16le", False, utf16(case_.0, False), StripBom)
      == Ok(from_units(case_.1))
    assert text_decoder("utf-16be", False, utf16(case_.0, True), StripBom)
      == Ok(from_units(case_.1))
  })
  // ASCII supersets.
  [
    "windows-1252", "ibm866", "gbk", "gb18030", "big5", "euc-jp", "shift_jis",
    "euc-kr",
  ]
  |> list.each(fn(label) {
    list.each([0x00, 0x1A, 0x1C, 0x42, 0x7F], fn(b) {
      let assert Ok(char) = string.utf_codepoint(b)
      let expected = Ok(string.from_utf_codepoints([char]))
      assert text_decoder(label, False, <<b>>, StripBom) == expected
      assert text_decoder(label, True, <<b>>, StripBom) == expected
    })
  })
}

// api-invalid-label.any.js: labels with other whitespace are rejected.
pub fn invalid_label_test() {
  assert text_encoding.get("invalid-invalidLabel") == Error(Nil)
  let spaces = ["\u{0000}", "\u{000B}", "\u{00A0}", "\u{2028}", "\u{2029}"]
  support.fixture_lines("test/fixtures/whatwg/labels.tsv")
  |> list.each(fn(fields) {
    let assert [label, _] = fields
    list.each(spaces, fn(space) {
      assert text_encoding.get(space <> label) == Error(Nil)
      assert text_encoding.get(label <> space) == Error(Nil)
      assert text_encoding.get(space <> label <> space) == Error(Nil)
    })
  })
}

// textdecoder-labels.any.js
pub fn labels_test() {
  let whitespace = [" ", "\t", "\n", "\f", "\r"]
  let rows = support.fixture_lines("test/fixtures/whatwg/labels.tsv")
  assert list.length(rows) == 228
  list.each(rows, fn(fields) {
    let assert [label, name] = fields
    let expected = encoding_named(name)
    assert text_encoding.get(label) == expected
    assert text_encoding.get(string.uppercase(label)) == expected
    list.each(whitespace, fn(space) {
      assert text_encoding.get(space <> label) == expected
      assert text_encoding.get(label <> space) == expected
      assert text_encoding.get(space <> label <> space) == expected
    })
  })
}

fn encoding_named(name: String) -> Result(Encoding, Nil) {
  case
    list.find(text_encoding.encodings, fn(e) { text_encoding.name(e) == name })
  {
    Ok(encoding) -> Ok(encoding)
    Error(_) -> panic as { "no encoding named " <> name }
  }
}

pub fn every_encoding_has_a_name_test() {
  assert list.length(text_encoding.encodings) == 40
  let names = list.map(text_encoding.encodings, text_encoding.name)
  assert list.length(list.unique(names)) == 40
  // Each name, lowercased, is one of its labels.
  list.each(text_encoding.encodings, fn(encoding) {
    assert text_encoding.get(text_encoding.name(encoding)) == Ok(encoding)
  })
}

//// The API around the decoders: labels, names, BOM handling, hooks and
//// error counts.

import gleam/option.{None, Some}
import text_encoding.{
  Big5, Decoded, EucKr, Gbk, Iso2022Jp, KeepBom, Replacement, ShiftJis, SniffBom,
  StripBom, Utf16Be, Utf16Le, Utf8, Windows1252, XUserDefined,
}

pub fn get_test() {
  assert text_encoding.get("utf-8") == Ok(Utf8)
  assert text_encoding.get(" \t\n\u{000C}\rSHIFT_JIS \r\n") == Ok(ShiftJis)
  assert text_encoding.get("latin1") == Ok(Windows1252)
  assert text_encoding.get("ascii") == Ok(Windows1252)
  assert text_encoding.get("utf-16") == Ok(Utf16Le)
  assert text_encoding.get("ks_c_5601-1987") == Ok(EucKr)
  assert text_encoding.get("iso-2022-kr") == Ok(Replacement)
  assert text_encoding.get("utf-7") == Error(Nil)
  assert text_encoding.get("") == Error(Nil)
  assert text_encoding.get("utf-8\u{0}") == Error(Nil)
}

// Only ASCII letters are case-folded: Unicode lowercases KELVIN SIGN to
// "k" and LATIN CAPITAL LETTER I WITH DOT ABOVE to "i" plus a dot.
pub fn get_is_ascii_case_insensitive_only_test() {
  assert text_encoding.get("\u{212A}OI8-R") == Error(Nil)
  assert text_encoding.get("KOI8-R") == text_encoding.get("koi8-r")
  assert text_encoding.get("\u{0130}so-2022-jp") == Error(Nil)
  assert text_encoding.get("ISO-2022-JP") == Ok(Iso2022Jp)
}

pub fn name_test() {
  assert text_encoding.name(ShiftJis) == "Shift_JIS"
  assert text_encoding.name(Gbk) == "GBK"
  assert text_encoding.name(XUserDefined) == "x-user-defined"
}

pub fn output_encoding_test() {
  assert text_encoding.output_encoding(Replacement) == Utf8
  assert text_encoding.output_encoding(Utf16Be) == Utf8
  assert text_encoding.output_encoding(Utf16Le) == Utf8
  assert text_encoding.output_encoding(Big5) == Big5
}

pub fn bom_sniff_test() {
  assert text_encoding.bom_sniff(<<0xEF, 0xBB, 0xBF>>) == Some(Utf8)
  assert text_encoding.bom_sniff(<<0xFE, 0xFF, 0>>) == Some(Utf16Be)
  assert text_encoding.bom_sniff(<<0xFF, 0xFE>>) == Some(Utf16Le)
  assert text_encoding.bom_sniff(<<0xEF, 0xBB>>) == None
  assert text_encoding.bom_sniff(<<>>) == None
}

pub fn sniff_bom_overrides_the_encoding_test() {
  assert text_encoding.decode_with(<<0xFF, 0xFE, 0x41, 0>>, ShiftJis, SniffBom)
    == Decoded("A", Utf16Le, 0)
  assert text_encoding.decode_with(
      <<0xEF, 0xBB, 0xBF, 0xC3, 0xA9>>,
      Windows1252,
      SniffBom,
    )
    == Decoded("é", Utf8, 0)
  // Only one byte order mark is removed.
  assert text_encoding.decode(<<0xEF, 0xBB, 0xBF, 0xEF, 0xBB, 0xBF>>, Utf8)
    == "\u{FEFF}"
  assert text_encoding.decode(<<0x82, 0xA0>>, ShiftJis) == "あ"
}

pub fn strip_bom_keeps_the_encoding_test() {
  // A UTF-16 BOM is not removed when decoding UTF-8, and windows-1252
  // decodes the UTF-8 BOM's bytes as characters.
  assert text_encoding.decode_with(<<0xFF, 0xFE, 0x41>>, Utf8, StripBom)
    == Decoded("\u{FFFD}\u{FFFD}A", Utf8, 2)
  assert text_encoding.decode_with(<<0xEF, 0xBB, 0xBF>>, Windows1252, StripBom)
    == Decoded("ï»¿", Windows1252, 0)
  assert text_encoding.decode_with(<<0xFE, 0xFF, 0, 0x41>>, Utf16Be, StripBom)
    == Decoded("A", Utf16Be, 0)
  assert text_encoding.decode_with(<<0xFE, 0xFF, 0, 0x41>>, Utf16Le, StripBom)
    == Decoded("\u{FFFE}\u{4100}", Utf16Le, 0)
}

pub fn keep_bom_test() {
  assert text_encoding.decode_with(<<0xEF, 0xBB, 0xBF, 0x41>>, Utf8, KeepBom)
    == Decoded("\u{FEFF}A", Utf8, 0)
}

pub fn utf8_hooks_test() {
  let bytes = <<0xEF, 0xBB, 0xBF, 0x41, 0xFF>>
  assert text_encoding.utf8_decode(bytes) == "A\u{FFFD}"
  assert text_encoding.utf8_decode_without_bom(bytes) == "\u{FEFF}A\u{FFFD}"
  assert text_encoding.utf8_decode_without_bom_or_fail(bytes) == Error(Nil)
  assert text_encoding.utf8_decode_without_bom_or_fail(<<
      0xEF,
      0xBB,
      0xBF,
      0x41,
    >>)
    == Ok("\u{FEFF}A")
  // Leading BOMs survive on JavaScript too, where TextDecoder would remove
  // one.
  assert text_encoding.utf8_decode_without_bom(<<
      0xEF, 0xBB, 0xBF, 0xEF, 0xBB, 0xBF,
    >>)
    == "\u{FEFF}\u{FEFF}"
}

pub fn error_counts_test() {
  let count = fn(bytes, encoding) {
    text_encoding.decode_with(bytes, encoding, KeepBom).errors
  }
  assert count(<<0xF0, 0x80, 0x80>>, Utf8) == 3
  assert count(<<0xF0, 0x9F, 0x92>>, Utf8) == 1
  assert count(<<0xEF, 0xBF, 0xBD>>, Utf8) == 0
  assert count(<<0x81, 0x30, 0xFE, 0x29>>, Gbk) == 2
  assert count(<<>>, Replacement) == 0
  assert count(<<0, 0, 0>>, Replacement) == 1
  assert count(<<0x81>>, Windows1252) == 0
  assert count(<<0x00, 0xD8>>, Utf16Le) == 1
  assert count(<<0x41>>, Utf16Le) == 1
}

pub fn replacement_test() {
  assert text_encoding.decode(<<>>, Replacement) == ""
  assert text_encoding.decode(<<"abc":utf8>>, Replacement) == "\u{FFFD}"
  // A BOM still decides the encoding.
  assert text_encoding.decode(<<0xEF, 0xBB, 0xBF, 0x41>>, Replacement) == "A"
}

pub fn x_user_defined_test() {
  assert text_encoding.decode(<<0x41, 0x80, 0xFF>>, XUserDefined)
    == "A\u{F780}\u{F7FF}"
}

// The pointers that decode to two code points.
pub fn big5_two_code_points_test() {
  assert text_encoding.decode(<<0x88, 0x62, 0x88, 0x64>>, Big5)
    == "\u{CA}\u{304}\u{CA}\u{30C}"
  assert text_encoding.decode(<<0x88, 0xA3, 0x88, 0xA5>>, Big5)
    == "\u{EA}\u{304}\u{EA}\u{30C}"
  assert text_encoding.decode(<<0x87, 0x40>>, Big5) == "\u{43F0}"
  // A supplementary-plane code point.
  assert text_encoding.decode(<<0x87, 0x45>>, Big5) == "\u{27267}"
  assert text_encoding.decode(<<0xFE, 0xFE>>, Big5) == "\u{79D4}"
}

pub fn readme_example_test() {
  let assert Ok(encoding) = text_encoding.get("Shift_JIS")
  assert text_encoding.decode(<<0x82, 0xA0, 0x82, 0xA2>>, encoding) == "あい"
  assert text_encoding.decode_with(<<0x82, 0xFF>>, encoding, StripBom)
    == Decoded("\u{FFFD}", ShiftJis, 1)
}

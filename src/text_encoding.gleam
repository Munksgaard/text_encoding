//// Decoding text with the encodings of the WHATWG Encoding Standard
//// (https://encoding.spec.whatwg.org/), the encodings that web browsers
//// support. Pure Gleam, for the Erlang and JavaScript targets.
////
//// ```gleam
//// let assert Ok(encoding) = text_encoding.get("shift_jis")
//// text_encoding.decode(<<0x82, 0xA0>>, encoding)
//// // -> "あ"
//// ```
////
//// Decoding never fails: bytes that the encoding cannot decode become
//// U+FFFD REPLACEMENT CHARACTER, as the standard's "replacement" error mode
//// requires. `decode_with` also reports how many errors there were, and
//// `utf8_decode_without_bom_or_fail` fails instead.

import gleam/bit_array
import gleam/option.{type Option, None, Some}
import gleam/string
import text_encoding/internal/chinese
import text_encoding/internal/japanese
import text_encoding/internal/korean
import text_encoding/internal/labels
import text_encoding/internal/output
import text_encoding/internal/single_byte
import text_encoding/internal/single_byte_index
import text_encoding/internal/utf16
import text_encoding/internal/utf8

/// An encoding of the Encoding Standard.
pub type Encoding {
  Utf8
  Ibm866
  Iso88592
  Iso88593
  Iso88594
  Iso88595
  Iso88596
  Iso88597
  Iso88598
  Iso88598I
  Iso885910
  Iso885913
  Iso885914
  Iso885915
  Iso885916
  Koi8R
  Koi8U
  Macintosh
  Windows874
  Windows1250
  Windows1251
  Windows1252
  Windows1253
  Windows1254
  Windows1255
  Windows1256
  Windows1257
  Windows1258
  XMacCyrillic
  Gbk
  Gb18030
  Big5
  EucJp
  Iso2022Jp
  ShiftJis
  EucKr
  Replacement
  Utf16Be
  Utf16Le
  XUserDefined
}

/// Every encoding, in the order of the standard's table.
pub const encodings = [
  Utf8,
  Ibm866,
  Iso88592,
  Iso88593,
  Iso88594,
  Iso88595,
  Iso88596,
  Iso88597,
  Iso88598,
  Iso88598I,
  Iso885910,
  Iso885913,
  Iso885914,
  Iso885915,
  Iso885916,
  Koi8R,
  Koi8U,
  Macintosh,
  Windows874,
  Windows1250,
  Windows1251,
  Windows1252,
  Windows1253,
  Windows1254,
  Windows1255,
  Windows1256,
  Windows1257,
  Windows1258,
  XMacCyrillic,
  Gbk,
  Gb18030,
  Big5,
  EucJp,
  Iso2022Jp,
  ShiftJis,
  EucKr,
  Replacement,
  Utf16Be,
  Utf16Le,
  XUserDefined,
]

/// The encoding's name, as the standard writes it: "UTF-8", "Shift_JIS",
/// "windows-1252", ...
pub fn name(encoding: Encoding) -> String {
  case encoding {
    Utf8 -> "UTF-8"
    Ibm866 -> "IBM866"
    Iso88592 -> "ISO-8859-2"
    Iso88593 -> "ISO-8859-3"
    Iso88594 -> "ISO-8859-4"
    Iso88595 -> "ISO-8859-5"
    Iso88596 -> "ISO-8859-6"
    Iso88597 -> "ISO-8859-7"
    Iso88598 -> "ISO-8859-8"
    Iso88598I -> "ISO-8859-8-I"
    Iso885910 -> "ISO-8859-10"
    Iso885913 -> "ISO-8859-13"
    Iso885914 -> "ISO-8859-14"
    Iso885915 -> "ISO-8859-15"
    Iso885916 -> "ISO-8859-16"
    Koi8R -> "KOI8-R"
    Koi8U -> "KOI8-U"
    Macintosh -> "macintosh"
    Windows874 -> "windows-874"
    Windows1250 -> "windows-1250"
    Windows1251 -> "windows-1251"
    Windows1252 -> "windows-1252"
    Windows1253 -> "windows-1253"
    Windows1254 -> "windows-1254"
    Windows1255 -> "windows-1255"
    Windows1256 -> "windows-1256"
    Windows1257 -> "windows-1257"
    Windows1258 -> "windows-1258"
    XMacCyrillic -> "x-mac-cyrillic"
    Gbk -> "GBK"
    Gb18030 -> "gb18030"
    Big5 -> "Big5"
    EucJp -> "EUC-JP"
    Iso2022Jp -> "ISO-2022-JP"
    ShiftJis -> "Shift_JIS"
    EucKr -> "EUC-KR"
    Replacement -> "replacement"
    Utf16Be -> "UTF-16BE"
    Utf16Le -> "UTF-16LE"
    XUserDefined -> "x-user-defined"
  }
}

/// "Get an encoding": the encoding with this label, ignoring ASCII case and
/// leading and trailing ASCII whitespace. `Error(Nil)` if no encoding has
/// the label.
///
/// Some labels ("iso-2022-kr", "hz-gb-2312", ...) give `Replacement`, an
/// encoding that decodes any input to a single U+FFFD. It exists so that
/// content in those encodings cannot be misread as ASCII.
pub fn get(label: String) -> Result(Encoding, Nil) {
  case labels.name(ascii_lowercase(trim(label))) {
    Ok(name) -> from_name(name)
    Error(_) -> Error(Nil)
  }
}

fn from_name(name: String) -> Result(Encoding, Nil) {
  case name {
    "UTF-8" -> Ok(Utf8)
    "IBM866" -> Ok(Ibm866)
    "ISO-8859-2" -> Ok(Iso88592)
    "ISO-8859-3" -> Ok(Iso88593)
    "ISO-8859-4" -> Ok(Iso88594)
    "ISO-8859-5" -> Ok(Iso88595)
    "ISO-8859-6" -> Ok(Iso88596)
    "ISO-8859-7" -> Ok(Iso88597)
    "ISO-8859-8" -> Ok(Iso88598)
    "ISO-8859-8-I" -> Ok(Iso88598I)
    "ISO-8859-10" -> Ok(Iso885910)
    "ISO-8859-13" -> Ok(Iso885913)
    "ISO-8859-14" -> Ok(Iso885914)
    "ISO-8859-15" -> Ok(Iso885915)
    "ISO-8859-16" -> Ok(Iso885916)
    "KOI8-R" -> Ok(Koi8R)
    "KOI8-U" -> Ok(Koi8U)
    "macintosh" -> Ok(Macintosh)
    "windows-874" -> Ok(Windows874)
    "windows-1250" -> Ok(Windows1250)
    "windows-1251" -> Ok(Windows1251)
    "windows-1252" -> Ok(Windows1252)
    "windows-1253" -> Ok(Windows1253)
    "windows-1254" -> Ok(Windows1254)
    "windows-1255" -> Ok(Windows1255)
    "windows-1256" -> Ok(Windows1256)
    "windows-1257" -> Ok(Windows1257)
    "windows-1258" -> Ok(Windows1258)
    "x-mac-cyrillic" -> Ok(XMacCyrillic)
    "GBK" -> Ok(Gbk)
    "gb18030" -> Ok(Gb18030)
    "Big5" -> Ok(Big5)
    "EUC-JP" -> Ok(EucJp)
    "ISO-2022-JP" -> Ok(Iso2022Jp)
    "Shift_JIS" -> Ok(ShiftJis)
    "EUC-KR" -> Ok(EucKr)
    "replacement" -> Ok(Replacement)
    "UTF-16BE" -> Ok(Utf16Be)
    "UTF-16LE" -> Ok(Utf16Le)
    "x-user-defined" -> Ok(XUserDefined)
    _ -> Error(Nil)
  }
}

/// Removes leading and trailing ASCII whitespace: TAB, LF, FF, CR and SPACE.
fn trim(label: String) -> String {
  label
  |> string.to_utf_codepoints
  |> drop_whitespace
  |> reverse([])
  |> drop_whitespace
  |> reverse([])
  |> string.from_utf_codepoints
}

fn drop_whitespace(codepoints: List(UtfCodepoint)) -> List(UtfCodepoint) {
  case codepoints {
    [c, ..rest] ->
      case string.utf_codepoint_to_int(c) {
        0x09 | 0x0A | 0x0C | 0x0D | 0x20 -> drop_whitespace(rest)
        _ -> codepoints
      }
    [] -> []
  }
}

fn reverse(list: List(a), acc: List(a)) -> List(a) {
  case list {
    [x, ..rest] -> reverse(rest, [x, ..acc])
    [] -> acc
  }
}

/// Lowercases ASCII letters only. Unicode case mapping would make, for
/// example, "\u{212A}oi8-r" (KELVIN SIGN) a label.
fn ascii_lowercase(label: String) -> String {
  label
  |> string.to_utf_codepoints
  |> lowercase_loop([])
  |> string.from_utf_codepoints
}

fn lowercase_loop(
  codepoints: List(UtfCodepoint),
  acc: List(UtfCodepoint),
) -> List(UtfCodepoint) {
  case codepoints {
    [c, ..rest] -> {
      let i = string.utf_codepoint_to_int(c)
      let c = case i >= 0x41 && i <= 0x5A, string.utf_codepoint(i + 0x20) {
        True, Ok(lower) -> lower
        _, _ -> c
      }
      lowercase_loop(rest, [c, ..acc])
    }
    [] -> reverse(acc, [])
  }
}

/// "Get an output encoding": the encoding to use when encoding text for a
/// document in `encoding`. `Replacement`, `Utf16Be` and `Utf16Le` give
/// `Utf8`; other encodings are unchanged.
pub fn output_encoding(encoding: Encoding) -> Encoding {
  case encoding {
    Replacement | Utf16Be | Utf16Le -> Utf8
    _ -> encoding
  }
}

/// "BOM sniff": the encoding indicated by a byte order mark at the start of
/// `bytes`, if any.
pub fn bom_sniff(bytes: BitArray) -> Option(Encoding) {
  case bytes {
    <<0xEF, 0xBB, 0xBF, _:bits>> -> Some(Utf8)
    <<0xFE, 0xFF, _:bits>> -> Some(Utf16Be)
    <<0xFF, 0xFE, _:bits>> -> Some(Utf16Le)
    _ -> None
  }
}

/// How `decode_with` treats a byte order mark.
pub type Bom {
  /// As the standard's `decode`: a UTF-8, UTF-16BE or UTF-16LE byte order
  /// mark is removed and decides the encoding, whatever encoding was given.
  SniffBom
  /// As `TextDecoder` by default: when decoding UTF-8, UTF-16BE or
  /// UTF-16LE, a leading U+FEFF is removed. The encoding is never changed,
  /// so a mark for the other byte order decodes as U+FFFE.
  StripBom
  /// As `TextDecoder` with `ignoreBOM`: the text is decoded as is.
  KeepBom
}

/// The result of `decode_with`.
pub type Decoded {
  Decoded(
    /// The decoded text.
    text: String,
    /// The encoding used: with `SniffBom`, the one a byte order mark gave.
    encoding: Encoding,
    /// The number of errors, each replaced with U+FFFD. Decoding in the
    /// standard's "fatal" error mode fails exactly when this is not 0.
    errors: Int,
  )
}

/// Decodes `bytes` as `encoding`, with the given byte order mark handling,
/// and counts the errors. Bits after the last whole byte are one error.
pub fn decode_with(bytes: BitArray, encoding: Encoding, bom: Bom) -> Decoded {
  let #(encoding, bytes) = case bom, encoding, bytes {
    SniffBom, _, <<0xEF, 0xBB, 0xBF, rest:bits>> -> #(Utf8, rest)
    SniffBom, _, <<0xFE, 0xFF, rest:bits>> -> #(Utf16Be, rest)
    SniffBom, _, <<0xFF, 0xFE, rest:bits>> -> #(Utf16Le, rest)
    StripBom, Utf8, <<0xEF, 0xBB, 0xBF, rest:bits>> -> #(encoding, rest)
    StripBom, Utf16Be, <<0xFE, 0xFF, rest:bits>> -> #(encoding, rest)
    StripBom, Utf16Le, <<0xFF, 0xFE, rest:bits>> -> #(encoding, rest)
    _, _, _ -> #(encoding, bytes)
  }
  let #(text, errors) = run(bytes, encoding)
  Decoded(text, encoding, errors)
}

/// The standard's `decode`: decodes `bytes`, using the encoding a byte
/// order mark indicates if there is one, and `fallback` otherwise. Errors
/// become U+FFFD.
pub fn decode(bytes: BitArray, fallback: Encoding) -> String {
  decode_with(bytes, fallback, SniffBom).text
}

/// "UTF-8 decode": decodes UTF-8, removing a leading UTF-8 byte order mark.
/// Errors become U+FFFD.
pub fn utf8_decode(bytes: BitArray) -> String {
  decode_with(bytes, Utf8, StripBom).text
}

/// "UTF-8 decode without BOM": decodes UTF-8; a byte order mark is kept as
/// U+FEFF. Errors become U+FFFD.
pub fn utf8_decode_without_bom(bytes: BitArray) -> String {
  run(bytes, Utf8).0
}

/// "UTF-8 decode without BOM or fail": decodes UTF-8, or fails if the bytes
/// are not valid UTF-8. A byte order mark is kept as U+FEFF. For other
/// encodings, decoding fails in the standard's "fatal" mode exactly when
/// `decode_with(..).errors` is not 0.
pub fn utf8_decode_without_bom_or_fail(bytes: BitArray) -> Result(String, Nil) {
  output.validate(bytes)
}

/// Runs the decoder of `encoding` over all of `bytes`. Bits after the last
/// whole byte are one error.
fn run(bytes: BitArray, encoding: Encoding) -> #(String, Int) {
  let size = bit_array.bit_size(bytes)
  case size % 8, bytes {
    0, _ -> run_bytes(bytes, encoding)
    _, <<whole:bytes-size(size / 8), _:bits>> -> {
      let #(text, errors) = run_bytes(whole, encoding)
      case encoding, errors {
        // The replacement decoder gives one U+FFFD for any input.
        Replacement, 1 -> #(text, errors)
        _, _ -> #(text <> "\u{FFFD}", errors + 1)
      }
    }
    // Unreachable: the pattern above matches any partial final byte.
    _, _ -> run_bytes(bytes, encoding)
  }
}

fn run_bytes(bytes: BitArray, encoding: Encoding) -> #(String, Int) {
  case encoding {
    Utf8 -> utf8.decode(bytes)
    Utf16Be -> utf16.decode(bytes, True)
    Utf16Le -> utf16.decode(bytes, False)
    Gbk | Gb18030 -> chinese.gb18030(bytes)
    Big5 -> chinese.big5(bytes)
    EucJp -> japanese.euc_jp(bytes)
    Iso2022Jp -> japanese.iso_2022_jp(bytes)
    ShiftJis -> japanese.shift_jis(bytes)
    EucKr -> korean.euc_kr(bytes)
    XUserDefined -> #(single_byte.user_defined(bytes), 0)
    Replacement ->
      case bytes {
        <<>> -> #("", 0)
        _ -> #("\u{FFFD}", 1)
      }
    _ ->
      case single_byte_index.table(name(encoding)) {
        Ok(table) -> single_byte.decode(bytes, table)
        // Unreachable: every other encoding is a single-byte encoding.
        Error(_) -> #("", 0)
      }
  }
}

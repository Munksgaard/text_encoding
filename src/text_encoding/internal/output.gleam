//// Decoder output: a reversed list of UTF-8 chunks, joined once at the end.
//// Decoders slice runs of bytes that are already UTF-8 (ASCII, say) from
//// the input instead of copying them byte by byte.

import gleam/bit_array
import gleam/list
import gleam/string

pub type Output =
  List(BitArray)

/// U+FFFD REPLACEMENT CHARACTER.
pub const replacement = <<0xEF, 0xBF, 0xBD>>

/// The UTF-8 encoding of a scalar value.
pub fn utf8(code_point: Int) -> BitArray {
  let low = 0x80 + code_point % 0x40
  case code_point {
    _ if code_point < 0x80 -> <<code_point>>
    _ if code_point < 0x800 -> {
      let lead = 0xC0 + code_point / 0x40
      <<lead, low>>
    }
    _ if code_point < 0x10000 -> {
      let lead = 0xE0 + code_point / 0x1000
      let middle = 0x80 + code_point / 0x40 % 0x40
      <<lead, middle, low>>
    }
    _ -> {
      let lead = 0xF0 + code_point / 0x40000
      let high = 0x80 + code_point / 0x1000 % 0x40
      let middle = 0x80 + code_point / 0x40 % 0x40
      <<lead, high, middle, low>>
    }
  }
}

/// Adds `input` from byte `from` to byte `to` (exclusive), then `chunk`.
pub fn push(
  output: Output,
  input: BitArray,
  from: Int,
  to: Int,
  chunk: BitArray,
) -> Output {
  [chunk, ..run(output, input, from, to)]
}

/// Adds `input` from byte `from` to byte `to` (exclusive).
pub fn run(output: Output, input: BitArray, from: Int, to: Int) -> Output {
  case to > from, bit_array.slice(input, from, to - from) {
    True, Ok(bytes) -> [bytes, ..output]
    _, _ -> output
  }
}

/// Joins the output. The chunks are valid UTF-8 by construction.
pub fn finish(output: Output) -> String {
  output |> list.reverse |> bit_array.concat |> to_string
}

/// Converts valid UTF-8 to a string. On JavaScript, `bit_array.to_string`
/// uses `TextDecoder`, which removes a leading byte order mark; leading
/// marks are therefore kept aside and put back, so both targets agree.
pub fn to_string(bytes: BitArray) -> String {
  let #(marks, rest) = leading_marks(bytes, 0)
  case bit_array.to_string(rest) {
    Ok(text) -> string.repeat("\u{FEFF}", marks) <> text
    Error(_) -> ""
  }
}

/// Like `to_string`, but fails on invalid UTF-8.
pub fn validate(bytes: BitArray) -> Result(String, Nil) {
  let #(marks, rest) = leading_marks(bytes, 0)
  case bit_array.to_string(rest) {
    Ok(text) -> Ok(string.repeat("\u{FEFF}", marks) <> text)
    Error(_) -> Error(Nil)
  }
}

fn leading_marks(bytes: BitArray, count: Int) -> #(Int, BitArray) {
  case bytes {
    <<0xEF, 0xBB, 0xBF, rest:bytes>> -> leading_marks(rest, count + 1)
    _ -> #(count, bytes)
  }
}

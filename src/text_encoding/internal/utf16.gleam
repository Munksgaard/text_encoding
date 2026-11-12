//// The shared UTF-16 decoder, for UTF-16BE and UTF-16LE.
////
//// UTF-16 has no runs of bytes that are already UTF-8, so the output is
//// kept as a reversed list of code points (0xFFFD for errors), which
//// allocates less than a list of small UTF-8 chunks.

import gleam/string

/// Decodes UTF-16 without BOM handling. Returns the text and the number of
/// errors.
pub fn decode(input: BitArray, big_endian: Bool) -> #(String, Int) {
  loop(input, big_endian, [], 0)
}

fn code_unit(a: Int, b: Int, big_endian: Bool) -> Int {
  case big_endian {
    True -> a * 0x100 + b
    False -> b * 0x100 + a
  }
}

fn loop(
  rest: BitArray,
  big_endian: Bool,
  acc: List(Int),
  errors: Int,
) -> #(String, Int) {
  case rest {
    <<a, b, rest:bytes>> -> {
      let first = code_unit(a, b, big_endian)
      case
        first >= 0xD800 && first <= 0xDBFF,
        first >= 0xDC00 && first <= 0xDFFF
      {
        True, _ ->
          case rest {
            <<c, d, tail:bytes>> -> {
              let next = code_unit(c, d, big_endian)
              case next >= 0xDC00 && next <= 0xDFFF {
                True -> {
                  let scalar =
                    0x10000 + { first - 0xD800 } * 0x400 + { next - 0xDC00 }
                  loop(tail, big_endian, [scalar, ..acc], errors)
                }
                // The next code unit is restored and decoded on its own.
                False -> loop(rest, big_endian, [0xFFFD, ..acc], errors + 1)
              }
            }
            // A leading surrogate, then at most one byte: one error.
            _ -> finish([0xFFFD, ..acc], errors + 1)
          }
        _, True -> loop(rest, big_endian, [0xFFFD, ..acc], errors + 1)
        False, False -> loop(rest, big_endian, [first, ..acc], errors)
      }
    }
    <<_>> -> finish([0xFFFD, ..acc], errors + 1)
    _ -> finish(acc, errors)
  }
}

fn finish(reversed: List(Int), errors: Int) -> #(String, Int) {
  #(string.from_utf_codepoints(to_codepoints(reversed, [])), errors)
}

/// Reverses the list and converts each scalar value to a `UtfCodepoint`.
fn to_codepoints(
  reversed: List(Int),
  acc: List(UtfCodepoint),
) -> List(UtfCodepoint) {
  case reversed {
    [c, ..rest] ->
      case string.utf_codepoint(c) {
        Ok(c) -> to_codepoints(rest, [c, ..acc])
        // Unreachable: surrogates are never added.
        Error(_) -> to_codepoints(rest, acc)
      }
    [] -> acc
  }
}

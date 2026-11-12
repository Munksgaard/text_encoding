//// The UTF-8 decoder. Each maximal subpart of an ill-formed sequence
//// becomes one U+FFFD, as the WHATWG UTF-8 decoder (and Unicode's "best
//// practice") requires.

import text_encoding/internal/output.{type Output}

/// Decodes UTF-8 without BOM handling. Returns the text and the number of
/// errors.
pub fn decode(input: BitArray) -> #(String, Int) {
  case output.validate(input) {
    Ok(text) -> #(text, 0)
    Error(_) -> loop(input, input, 0, 0, [], 0)
  }
}

fn loop(
  input: BitArray,
  rest: BitArray,
  pos: Int,
  run: Int,
  acc: Output,
  errors: Int,
) -> #(String, Int) {
  case rest {
    <<b, rest:bytes>> if b < 0x80 -> loop(input, rest, pos + 1, run, acc, errors)
    <<lead, rest:bytes>> ->
      case sequence(lead, rest) {
        Ok(length) ->
          loop(input, skip(rest, length - 1), pos + length, run, acc, errors)
        Error(length) -> {
          let acc = output.push(acc, input, run, pos, output.replacement)
          let pos = pos + length
          loop(input, skip(rest, length - 1), pos, pos, acc, errors + 1)
        }
      }
    _ -> #(output.finish(output.run(acc, input, run, pos)), errors)
  }
}

fn skip(bytes: BitArray, count: Int) -> BitArray {
  case bytes {
    <<_:bytes-size(count), rest:bytes>> -> rest
    _ -> <<>>
  }
}

/// For a lead byte and the bytes after it: `Ok(length)` of a valid
/// sequence, or `Error(length)` of the bytes to replace with one U+FFFD.
fn sequence(lead: Int, rest: BitArray) -> Result(Int, Int) {
  let #(length, low, high) = case lead {
    _ if lead >= 0xC2 && lead <= 0xDF -> #(2, 0x80, 0xBF)
    0xE0 -> #(3, 0xA0, 0xBF)
    0xED -> #(3, 0x80, 0x9F)
    _ if lead >= 0xE1 && lead <= 0xEF -> #(3, 0x80, 0xBF)
    0xF0 -> #(4, 0x90, 0xBF)
    0xF4 -> #(4, 0x80, 0x8F)
    _ if lead >= 0xF1 && lead <= 0xF3 -> #(4, 0x80, 0xBF)
    _ -> #(0, 0, 0)
  }
  case length, rest {
    0, _ -> Error(1)
    _, <<b, rest:bytes>> if b >= low && b <= high ->
      continuation(rest, 2, length)
    _, _ -> Error(1)
  }
}

fn continuation(rest: BitArray, seen: Int, length: Int) -> Result(Int, Int) {
  case seen == length, rest {
    True, _ -> Ok(length)
    False, <<b, rest:bytes>> if b >= 0x80 && b <= 0xBF ->
      continuation(rest, seen + 1, length)
    False, _ -> Error(seen)
  }
}

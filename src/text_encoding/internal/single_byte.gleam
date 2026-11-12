//// The single-byte decoder, and x-user-defined's decoder.

import text_encoding/internal/index
import text_encoding/internal/output.{type Output}

/// Decodes with a single-byte index (128 entries of 16 bits). Returns the
/// text and the number of errors.
pub fn decode(input: BitArray, table: BitArray) -> #(String, Int) {
  loop(input, input, table, 0, 0, [], 0)
}

fn loop(
  input: BitArray,
  rest: BitArray,
  table: BitArray,
  pos: Int,
  run: Int,
  acc: Output,
  errors: Int,
) -> #(String, Int) {
  case rest {
    <<b, rest:bytes>> if b < 0x80 ->
      loop(input, rest, table, pos + 1, run, acc, errors)
    <<b, rest:bytes>> -> {
      let #(chunk, errors) = case index.lookup16(table, b - 0x80) {
        0 -> #(output.replacement, errors + 1)
        code_point -> #(output.utf8(code_point), errors)
      }
      let acc = output.push(acc, input, run, pos, chunk)
      loop(input, rest, table, pos + 1, pos + 1, acc, errors)
    }
    _ -> #(output.finish(output.run(acc, input, run, pos)), errors)
  }
}

/// x-user-defined maps the bytes 0x80 to 0xFF to U+F780 to U+F7FF. It has
/// no errors.
pub fn user_defined(input: BitArray) -> String {
  user_defined_loop(input, input, 0, 0, [])
}

fn user_defined_loop(
  input: BitArray,
  rest: BitArray,
  pos: Int,
  run: Int,
  acc: Output,
) -> String {
  case rest {
    <<b, rest:bytes>> if b < 0x80 ->
      user_defined_loop(input, rest, pos + 1, run, acc)
    <<b, rest:bytes>> -> {
      let acc =
        output.push(acc, input, run, pos, output.utf8(0xF780 + b - 0x80))
      user_defined_loop(input, rest, pos + 1, pos + 1, acc)
    }
    _ -> output.finish(output.run(acc, input, run, pos))
  }
}

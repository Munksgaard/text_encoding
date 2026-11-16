//// Decoder output: a reversed list of UTF-8 chunks, joined once at the end.
//// Decoders slice runs of bytes that are already UTF-8 (ASCII, say) from
//// the input instead of copying them byte by byte.
////
//// Also the loop shared by the CJK decoders but ISO-2022-JP. The spec's
//// decoders read one byte at a time and "restore" bytes to the input on
//// some errors. Here each step looks ahead instead, and returns how many
//// bytes it consumed; restoring a byte is consuming one byte fewer.

import gleam/bit_array
import gleam/list
import gleam/result
import gleam/string

pub type Output =
  List(BitArray)

/// The result of decoding one sequence, and the number of bytes consumed.
pub type Step {
  Valid(chunk: BitArray, consumed: Int)
  /// An error, which becomes one U+FFFD.
  Invalid(consumed: Int)
}

/// U+FFFD REPLACEMENT CHARACTER.
pub const replacement = <<0xEF, 0xBF, 0xBD>>

/// Decodes `input`, ASCII bytes as themselves and each other sequence with
/// `step`, which gets its first byte and the bytes after it. Returns the
/// text and the number of errors.
pub fn decode(
  input: BitArray,
  step: fn(Int, BitArray) -> Step,
) -> #(String, Int) {
  loop(input, input, step, 0, 0, [], 0)
}

/// `start` is where the run of ASCII bytes not yet in `acc` starts.
fn loop(
  input: BitArray,
  rest: BitArray,
  step: fn(Int, BitArray) -> Step,
  pos: Int,
  start: Int,
  acc: Output,
  errors: Int,
) -> #(String, Int) {
  case rest {
    <<b, tail:bytes>> if b < 0x80 ->
      loop(input, tail, step, pos + 1, start, acc, errors)
    <<b, tail:bytes>> -> {
      let #(chunk, consumed, errors) = case step(b, tail) {
        Valid(chunk, consumed) -> #(chunk, consumed, errors)
        Invalid(consumed) -> #(replacement, consumed, errors + 1)
      }
      let acc = push(acc, input, start, pos, chunk)
      let pos = pos + consumed
      loop(input, drop(rest, consumed), step, pos, pos, acc, errors)
    }
    _ -> #(finish(run(acc, input, start, pos)), errors)
  }
}

/// The step for a sequence of `consumed` bytes that ends with `byte`, given
/// its index code point (0 for none). On an error, an ASCII `byte` is
/// restored.
pub fn lookup(code_point: Int, byte: Int, consumed: Int) -> Step {
  case code_point, byte < 0x80 {
    0, True -> Invalid(consumed - 1)
    0, False -> Invalid(consumed)
    _, _ -> Valid(utf8(code_point), consumed)
  }
}

/// `bytes` without the first `count` bytes. The UTF-8 and ISO-2022-JP
/// loops have their own copy: on the BEAM, a call to another module is
/// noticeably slower here.
fn drop(bytes: BitArray, count: Int) -> BitArray {
  case bytes {
    <<_:bytes-size(count), rest:bytes>> -> rest
    _ -> <<>>
  }
}

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
  output |> list.reverse |> bit_array.concat |> validate |> result.unwrap("")
}

/// Converts UTF-8 to a string, or fails on invalid UTF-8. On JavaScript,
/// `bit_array.to_string` uses `TextDecoder`, which removes a leading byte
/// order mark; leading marks are therefore kept aside and put back, so both
/// targets agree.
pub fn validate(bytes: BitArray) -> Result(String, Nil) {
  let #(marks, rest) = leading_marks(bytes, 0)
  use text <- result.map(bit_array.to_string(rest))
  string.repeat("\u{FEFF}", marks) <> text
}

fn leading_marks(bytes: BitArray, count: Int) -> #(Int, BitArray) {
  case bytes {
    <<0xEF, 0xBB, 0xBF, rest:bytes>> -> leading_marks(rest, count + 1)
    _ -> #(count, bytes)
  }
}

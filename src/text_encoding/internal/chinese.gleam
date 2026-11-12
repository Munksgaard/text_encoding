//// The gb18030 decoder (also GBK's decoder) and the Big5 decoder.
////
//// The spec's decoders read one byte at a time and "restore" bytes to the
//// input on some errors. Here each step looks ahead instead, and returns
//// how many bytes it consumed; restoring a byte is consuming one byte fewer.

import text_encoding/internal/index_big5
import text_encoding/internal/index_gb18030
import text_encoding/internal/index_gb18030_ranges as ranges
import text_encoding/internal/output.{type Output}

/// The result of decoding one sequence: the output (or an error) and the
/// number of bytes consumed.
type Step {
  Step(output: Result(BitArray, Nil), consumed: Int)
}

// ---------------------------------------------------------------------------
// gb18030

pub fn gb18030(input: BitArray) -> #(String, Int) {
  gb18030_loop(input, input, 0, 0, [], 0)
}

fn gb18030_loop(
  input: BitArray,
  rest: BitArray,
  pos: Int,
  run: Int,
  acc: Output,
  errors: Int,
) -> #(String, Int) {
  case rest {
    <<b, tail:bytes>> if b < 0x80 ->
      gb18030_loop(input, tail, pos + 1, run, acc, errors)
    <<b, tail:bytes>> -> {
      let step = case b {
        0x80 -> Step(Ok(<<0xE2, 0x82, 0xAC>>), 1)
        0xFF -> Step(Error(Nil), 1)
        _ -> gb18030_sequence(b, tail)
      }
      let #(chunk, errors) = chunk(step, errors)
      let acc = output.push(acc, input, run, pos, chunk)
      let pos = pos + step.consumed
      gb18030_loop(input, drop(rest, step.consumed), pos, pos, acc, errors)
    }
    _ -> #(output.finish(output.run(acc, input, run, pos)), errors)
  }
}

fn is_digit(b: Int) -> Bool {
  b >= 0x30 && b <= 0x39
}

fn is_gb_byte(b: Int) -> Bool {
  b >= 0x81 && b <= 0xFE
}

/// A sequence starting with `first` (0x81 to 0xFE), followed by `tail`.
fn gb18030_sequence(first: Int, tail: BitArray) -> Step {
  case tail {
    // Four bytes.
    <<second, third, fourth, _:bytes>>
      if fourth >= 0x30
      && fourth <= 0x39
      && second >= 0x30
      && second <= 0x39
      && third >= 0x81
      && third <= 0xFE
    -> {
      let pointer =
        { first - 0x81 }
        * { 10 * 126 * 10 }
        + { second - 0x30 }
        * { 10 * 126 }
        + { third - 0x81 }
        * 10
        + fourth
        - 0x30
      case ranges_code_point(pointer) {
        0 -> Step(Error(Nil), 4)
        code_point -> Step(Ok(output.utf8(code_point)), 4)
      }
    }
    // A bad fourth byte: second, third and the fourth byte are restored.
    <<second, _, _, _:bytes>> ->
      case is_digit(second) {
        True -> Step(Error(Nil), 1)
        False -> two_bytes(first, second)
      }
    // The end of the input after the third byte: all are consumed.
    <<second, third>> ->
      case is_digit(second), is_gb_byte(third) {
        True, True -> Step(Error(Nil), 3)
        True, False -> Step(Error(Nil), 1)
        False, _ -> two_bytes(first, second)
      }
    <<second>> ->
      case is_digit(second) {
        True -> Step(Error(Nil), 2)
        False -> two_bytes(first, second)
      }
    _ -> Step(Error(Nil), 1)
  }
}

fn two_bytes(first: Int, second: Int) -> Step {
  let offset = case second < 0x7F {
    True -> 0x40
    False -> 0x41
  }
  let code_point = case
    { second >= 0x40 && second <= 0x7E } || { second >= 0x80 && second <= 0xFE }
  {
    True -> index_gb18030.code_point({ first - 0x81 } * 190 + second - offset)
    False -> 0
  }
  case code_point, second < 0x80 {
    0, True -> Step(Error(Nil), 1)
    0, False -> Step(Error(Nil), 2)
    _, _ -> Step(Ok(output.utf8(code_point)), 2)
  }
}

/// The index gb18030 ranges code point for a pointer, or 0 for null.
fn ranges_code_point(pointer: Int) -> Int {
  case pointer {
    _ if pointer > 39_419 && pointer < 189_000 -> 0
    _ if pointer > 1_237_575 -> 0
    7457 -> 0xE7C7
    _ -> {
      let #(offset, code_point) = last_range(pointer, 0, ranges.count - 1)
      code_point + pointer - offset
    }
  }
}

/// Binary search for the last range whose pointer is at most `pointer`.
/// The first range starts at pointer 0.
fn last_range(pointer: Int, low: Int, high: Int) -> #(Int, Int) {
  case low >= high {
    True -> range(low)
    False -> {
      // The upper middle, so that `low = middle` always makes progress.
      let middle = { low + high + 1 } / 2
      case range(middle).0 <= pointer {
        True -> last_range(pointer, middle, high)
        False -> last_range(pointer, low, middle - 1)
      }
    }
  }
}

fn range(i: Int) -> #(Int, Int) {
  let offset = i * 8
  case ranges.data {
    <<_:bytes-size(offset), pointer:32, code_point:32, _:bits>> -> #(
      pointer,
      code_point,
    )
    _ -> #(0, 0)
  }
}

// ---------------------------------------------------------------------------
// Big5

pub fn big5(input: BitArray) -> #(String, Int) {
  big5_loop(input, input, 0, 0, [], 0)
}

fn big5_loop(
  input: BitArray,
  rest: BitArray,
  pos: Int,
  run: Int,
  acc: Output,
  errors: Int,
) -> #(String, Int) {
  case rest {
    <<b, tail:bytes>> if b < 0x80 ->
      big5_loop(input, tail, pos + 1, run, acc, errors)
    <<b, tail:bytes>> -> {
      let step = case b >= 0x81 && b <= 0xFE, tail {
        True, <<second, _:bytes>> -> big5_sequence(b, second)
        _, _ -> Step(Error(Nil), 1)
      }
      let #(chunk, errors) = chunk(step, errors)
      let acc = output.push(acc, input, run, pos, chunk)
      let pos = pos + step.consumed
      big5_loop(input, drop(rest, step.consumed), pos, pos, acc, errors)
    }
    _ -> #(output.finish(output.run(acc, input, run, pos)), errors)
  }
}

fn big5_sequence(leading: Int, byte: Int) -> Step {
  let offset = case byte < 0x7F {
    True -> 0x40
    False -> 0x62
  }
  let pointer = case
    { byte >= 0x40 && byte <= 0x7E } || { byte >= 0xA1 && byte <= 0xFE }
  {
    True -> { leading - 0x81 } * 157 + byte - offset
    False -> -1
  }
  case pointer {
    // Pointers that decode to two code points.
    1133 -> Step(Ok(<<0xC3, 0x8A, 0xCC, 0x84>>), 2)
    1135 -> Step(Ok(<<0xC3, 0x8A, 0xCC, 0x8C>>), 2)
    1164 -> Step(Ok(<<0xC3, 0xAA, 0xCC, 0x84>>), 2)
    1166 -> Step(Ok(<<0xC3, 0xAA, 0xCC, 0x8C>>), 2)
    _ ->
      case index_big5.code_point(pointer), byte < 0x80 {
        0, True -> Step(Error(Nil), 1)
        0, False -> Step(Error(Nil), 2)
        code_point, _ -> Step(Ok(output.utf8(code_point)), 2)
      }
  }
}

// ---------------------------------------------------------------------------

fn chunk(step: Step, errors: Int) -> #(BitArray, Int) {
  case step.output {
    Ok(chunk) -> #(chunk, errors)
    Error(_) -> #(output.replacement, errors + 1)
  }
}

fn drop(bytes: BitArray, count: Int) -> BitArray {
  case bytes {
    <<_:bytes-size(count), rest:bytes>> -> rest
    _ -> <<>>
  }
}

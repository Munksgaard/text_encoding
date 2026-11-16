//// The gb18030 decoder (also GBK's decoder) and the Big5 decoder.

import text_encoding/internal/index_big5
import text_encoding/internal/index_gb18030
import text_encoding/internal/index_gb18030_ranges as ranges
import text_encoding/internal/output.{type Step, Invalid, Valid}

// ---------------------------------------------------------------------------
// gb18030

pub fn gb18030(input: BitArray) -> #(String, Int) {
  output.decode(input, gb18030_step)
}

fn is_digit(b: Int) -> Bool {
  b >= 0x30 && b <= 0x39
}

fn is_gb_byte(b: Int) -> Bool {
  b >= 0x81 && b <= 0xFE
}

/// A sequence starting with `first`, followed by `tail`.
fn gb18030_step(first: Int, tail: BitArray) -> Step {
  case first, tail {
    0x80, _ -> Valid(<<0xE2, 0x82, 0xAC>>, 1)
    0xFF, _ -> Invalid(1)
    // Four bytes.
    _, <<second, third, fourth, _:bytes>>
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
        0 -> Invalid(4)
        code_point -> Valid(output.utf8(code_point), 4)
      }
    }
    // A bad fourth byte: second, third and the fourth byte are restored.
    _, <<second, _, _, _:bytes>> ->
      case is_digit(second) {
        True -> Invalid(1)
        False -> two_bytes(first, second)
      }
    // The end of the input after the third byte: all are consumed.
    _, <<second, third>> ->
      case is_digit(second), is_gb_byte(third) {
        True, True -> Invalid(3)
        True, False -> Invalid(1)
        False, _ -> two_bytes(first, second)
      }
    _, <<second>> ->
      case is_digit(second) {
        True -> Invalid(2)
        False -> two_bytes(first, second)
      }
    _, _ -> Invalid(1)
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
  output.lookup(code_point, second, 2)
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
  output.decode(input, big5_step)
}

fn big5_step(leading: Int, tail: BitArray) -> Step {
  case tail {
    <<byte, _:bytes>> if leading >= 0x81 && leading <= 0xFE -> {
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
        1133 -> Valid(<<0xC3, 0x8A, 0xCC, 0x84>>, 2)
        1135 -> Valid(<<0xC3, 0x8A, 0xCC, 0x8C>>, 2)
        1164 -> Valid(<<0xC3, 0xAA, 0xCC, 0x84>>, 2)
        1166 -> Valid(<<0xC3, 0xAA, 0xCC, 0x8C>>, 2)
        _ -> output.lookup(index_big5.code_point(pointer), byte, 2)
      }
    }
    _ -> Invalid(1)
  }
}

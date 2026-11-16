//// The EUC-JP, ISO-2022-JP and Shift_JIS decoders.

import text_encoding/internal/index_jis0208
import text_encoding/internal/index_jis0212
import text_encoding/internal/output.{type Output, type Step, Invalid, Valid}

fn in(byte: Int, low: Int, high: Int) -> Bool {
  byte >= low && byte <= high
}

// ---------------------------------------------------------------------------
// EUC-JP

pub fn euc_jp(input: BitArray) -> #(String, Int) {
  output.decode(input, euc_jp_step)
}

fn euc_jp_step(leading: Int, tail: BitArray) -> Step {
  case leading, tail {
    0x8E, <<byte, _:bytes>> if byte >= 0xA1 && byte <= 0xDF ->
      Valid(output.utf8(0xFF61 - 0xA1 + byte), 2)
    0x8F, <<byte, rest:bytes>> if byte >= 0xA1 && byte <= 0xFE ->
      case rest {
        <<trail, _:bytes>> -> {
          let code_point = case in(trail, 0xA1, 0xFE) {
            True ->
              index_jis0212.code_point({ byte - 0xA1 } * 94 + trail - 0xA1)
            False -> 0
          }
          output.lookup(code_point, trail, 3)
        }
        _ -> Invalid(2)
      }
    _, <<byte, _:bytes>> if leading == 0x8E || leading == 0x8F ->
      output.lookup(0, byte, 2)
    _, <<byte, _:bytes>> if leading >= 0xA1 && leading <= 0xFE -> {
      let code_point = case in(byte, 0xA1, 0xFE) {
        True -> index_jis0208.code_point({ leading - 0xA1 } * 94 + byte - 0xA1)
        False -> 0
      }
      output.lookup(code_point, byte, 2)
    }
    // A byte that cannot lead, or a leading byte at the end of the input.
    _, _ -> Invalid(1)
  }
}

// ---------------------------------------------------------------------------
// Shift_JIS

pub fn shift_jis(input: BitArray) -> #(String, Int) {
  output.decode(input, shift_jis_step)
}

fn shift_jis_step(leading: Int, tail: BitArray) -> Step {
  case leading, tail {
    0x80, _ -> Valid(output.utf8(0x80), 1)
    _, _ if leading >= 0xA1 && leading <= 0xDF ->
      Valid(output.utf8(0xFF61 - 0xA1 + leading), 1)
    _, <<byte, _:bytes>>
      if leading >= 0x81 && leading <= 0x9F || leading >= 0xE0 && leading <= 0xFC
    -> {
      let offset = case byte < 0x7F {
        True -> 0x40
        False -> 0x41
      }
      let leading_offset = case leading < 0xA0 {
        True -> 0x81
        False -> 0xC1
      }
      let pointer = case in(byte, 0x40, 0x7E) || in(byte, 0x80, 0xFC) {
        True -> { leading - leading_offset } * 188 + byte - offset
        False -> -1
      }
      case in(pointer, 8836, 10_715) {
        // Windows EUDC, mapped to the Private Use Area.
        True -> Valid(output.utf8(0xE000 - 8836 + pointer), 2)
        False -> output.lookup(index_jis0208.code_point(pointer), byte, 2)
      }
    }
    _, _ -> Invalid(1)
  }
}

// ---------------------------------------------------------------------------
// ISO-2022-JP
//
// Outside an escape sequence, the spec's decoder state and output state are
// equal, so one state is kept. A trailing byte is read together with its
// leading byte. `flag` is the spec's ISO-2022-JP output flag: true just after
// an escape sequence, so that two escape sequences in a row are an error.

type State {
  Ascii
  Roman
  Katakana
  LeadByte
}

pub fn iso_2022_jp(input: BitArray) -> #(String, Int) {
  iso_2022_jp_loop(input, input, Ascii, False, 0, 0, [], 0)
}

fn iso_2022_jp_loop(
  input: BitArray,
  rest: BitArray,
  state: State,
  flag: Bool,
  pos: Int,
  run: Int,
  acc: Output,
  errors: Int,
) -> #(String, Int) {
  case rest {
    <<0x1B, tail:bytes>> -> {
      let next = case tail {
        <<0x28, 0x42, _:bytes>> -> Ok(Ascii)
        <<0x28, 0x4A, _:bytes>> -> Ok(Roman)
        <<0x28, 0x49, _:bytes>> -> Ok(Katakana)
        <<0x24, 0x40, _:bytes>> | <<0x24, 0x42, _:bytes>> -> Ok(LeadByte)
        _ -> Error(Nil)
      }
      case next {
        Ok(next) -> {
          let #(acc, errors) = case flag {
            False -> #(output.run(acc, input, run, pos), errors)
            True -> #(
              output.push(acc, input, run, pos, output.replacement),
              errors + 1,
            )
          }
          let pos = pos + 3
          let rest = drop(rest, 3)
          iso_2022_jp_loop(input, rest, next, True, pos, pos, acc, errors)
        }
        // Only the escape byte is consumed; the bytes after it are decoded
        // in the current state.
        Error(_) -> {
          let acc = output.push(acc, input, run, pos, output.replacement)
          let pos = pos + 1
          iso_2022_jp_loop(input, tail, state, False, pos, pos, acc, errors + 1)
        }
      }
    }
    // A byte that decodes to itself extends the run.
    <<b, tail:bytes>>
      if b < 0x80
      && b != 0x0E
      && b != 0x0F
      && { state == Ascii || state == Roman && b != 0x5C && b != 0x7E }
    -> iso_2022_jp_loop(input, tail, state, False, pos + 1, run, acc, errors)
    <<b, tail:bytes>> -> {
      let step = case state, b {
        Roman, 0x5C -> Valid(output.utf8(0xA5), 1)
        Roman, 0x7E -> Valid(output.utf8(0x203E), 1)
        // SO, SI and bytes from 0x80.
        Ascii, _ | Roman, _ -> Invalid(1)
        Katakana, _ if b >= 0x21 && b <= 0x5F ->
          Valid(output.utf8(0xFF61 - 0x21 + b), 1)
        Katakana, _ -> Invalid(1)
        LeadByte, _ if b >= 0x21 && b <= 0x7E ->
          case tail {
            <<trail, _:bytes>> if trail >= 0x21 && trail <= 0x7E ->
              case index_jis0208.code_point({ b - 0x21 } * 94 + trail - 0x21) {
                0 -> Invalid(2)
                code_point -> Valid(output.utf8(code_point), 2)
              }
            // An escape byte is decoded next, as an escape sequence.
            <<0x1B, _:bytes>> -> Invalid(1)
            <<_, _:bytes>> -> Invalid(2)
            _ -> Invalid(1)
          }
        LeadByte, _ -> Invalid(1)
      }
      let #(chunk, consumed, errors) = case step {
        Valid(chunk, consumed) -> #(chunk, consumed, errors)
        Invalid(consumed) -> #(output.replacement, consumed, errors + 1)
      }
      let acc = output.push(acc, input, run, pos, chunk)
      let pos = pos + consumed
      let rest = drop(rest, consumed)
      iso_2022_jp_loop(input, rest, state, False, pos, pos, acc, errors)
    }
    _ -> #(output.finish(output.run(acc, input, run, pos)), errors)
  }
}

/// As `output.drop`, kept local for speed on the BEAM.
fn drop(bytes: BitArray, count: Int) -> BitArray {
  case bytes {
    <<_:bytes-size(count), rest:bytes>> -> rest
    _ -> <<>>
  }
}

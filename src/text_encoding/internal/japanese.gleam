//// The EUC-JP, ISO-2022-JP and Shift_JIS decoders.
////
//// As in the Chinese decoders, each step looks ahead and returns how many
//// bytes it consumed; restoring a byte is consuming one byte fewer.

import text_encoding/internal/index_jis0208
import text_encoding/internal/index_jis0212
import text_encoding/internal/output.{type Output}

/// The output of one step (or an error) and the number of bytes consumed.
type Step {
  Step(output: Result(BitArray, Nil), consumed: Int)
}

fn found(code_point: Int, byte: Int, consumed: Int) -> Step {
  case code_point, byte < 0x80 {
    // An ASCII byte after the leading byte is restored.
    0, True -> Step(Error(Nil), consumed - 1)
    0, False -> Step(Error(Nil), consumed)
    _, _ -> Step(Ok(output.utf8(code_point)), consumed)
  }
}

fn in(byte: Int, low: Int, high: Int) -> Bool {
  byte >= low && byte <= high
}

// ---------------------------------------------------------------------------
// EUC-JP

pub fn euc_jp(input: BitArray) -> #(String, Int) {
  euc_jp_loop(input, input, 0, 0, [], 0)
}

fn euc_jp_loop(
  input: BitArray,
  rest: BitArray,
  pos: Int,
  run: Int,
  acc: Output,
  errors: Int,
) -> #(String, Int) {
  case rest {
    <<b, tail:bytes>> if b < 0x80 ->
      euc_jp_loop(input, tail, pos + 1, run, acc, errors)
    <<b, tail:bytes>> -> {
      let step = euc_jp_sequence(b, tail)
      let #(chunk, errors) = chunk(step, errors)
      let acc = output.push(acc, input, run, pos, chunk)
      let pos = pos + step.consumed
      euc_jp_loop(input, drop(rest, step.consumed), pos, pos, acc, errors)
    }
    _ -> #(output.finish(output.run(acc, input, run, pos)), errors)
  }
}

fn euc_jp_sequence(leading: Int, tail: BitArray) -> Step {
  case leading, tail {
    0x8E, <<byte, _:bytes>> if byte >= 0xA1 && byte <= 0xDF ->
      Step(Ok(output.utf8(0xFF61 - 0xA1 + byte)), 2)
    0x8F, <<byte, rest:bytes>> if byte >= 0xA1 && byte <= 0xFE ->
      case rest {
        <<trail, _:bytes>> -> {
          let code_point = case in(trail, 0xA1, 0xFE) {
            True ->
              index_jis0212.code_point({ byte - 0xA1 } * 94 + trail - 0xA1)
            False -> 0
          }
          found(code_point, trail, 3)
        }
        _ -> Step(Error(Nil), 2)
      }
    _, <<byte, _:bytes>> if leading == 0x8E || leading == 0x8F ->
      found(0, byte, 2)
    _, <<byte, _:bytes>> if leading >= 0xA1 && leading <= 0xFE -> {
      let code_point = case in(byte, 0xA1, 0xFE) {
        True -> index_jis0208.code_point({ leading - 0xA1 } * 94 + byte - 0xA1)
        False -> 0
      }
      found(code_point, byte, 2)
    }
    // A byte that cannot lead, or a leading byte at the end of the input.
    _, _ -> Step(Error(Nil), 1)
  }
}

// ---------------------------------------------------------------------------
// Shift_JIS

pub fn shift_jis(input: BitArray) -> #(String, Int) {
  shift_jis_loop(input, input, 0, 0, [], 0)
}

fn shift_jis_loop(
  input: BitArray,
  rest: BitArray,
  pos: Int,
  run: Int,
  acc: Output,
  errors: Int,
) -> #(String, Int) {
  case rest {
    <<b, tail:bytes>> if b < 0x80 ->
      shift_jis_loop(input, tail, pos + 1, run, acc, errors)
    <<b, tail:bytes>> -> {
      let step = case b {
        0x80 -> Step(Ok(output.utf8(0x80)), 1)
        _ if b >= 0xA1 && b <= 0xDF ->
          Step(Ok(output.utf8(0xFF61 - 0xA1 + b)), 1)
        _ if b >= 0x81 && b <= 0x9F || b >= 0xE0 && b <= 0xFC ->
          case tail {
            <<byte, _:bytes>> -> shift_jis_sequence(b, byte)
            _ -> Step(Error(Nil), 1)
          }
        _ -> Step(Error(Nil), 1)
      }
      let #(chunk, errors) = chunk(step, errors)
      let acc = output.push(acc, input, run, pos, chunk)
      let pos = pos + step.consumed
      shift_jis_loop(input, drop(rest, step.consumed), pos, pos, acc, errors)
    }
    _ -> #(output.finish(output.run(acc, input, run, pos)), errors)
  }
}

fn shift_jis_sequence(leading: Int, byte: Int) -> Step {
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
    True -> Step(Ok(output.utf8(0xE000 - 8836 + pointer)), 2)
    False -> found(index_jis0208.code_point(pointer), byte, 2)
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
    <<>> -> #(output.finish(output.run(acc, input, run, pos)), errors)
    <<0x1B, tail:bytes>> -> {
      let next = case tail {
        <<0x28, 0x42, _:bytes>> -> Ok(Ascii)
        <<0x28, 0x4A, _:bytes>> -> Ok(Roman)
        <<0x28, 0x49, _:bytes>> -> Ok(Katakana)
        <<0x24, 0x40, _:bytes>> | <<0x24, 0x42, _:bytes>> -> Ok(LeadByte)
        _ -> Error(Nil)
      }
      case next, flag {
        Ok(next), False ->
          iso_2022_jp_loop(
            input,
            drop(rest, 3),
            next,
            True,
            pos + 3,
            pos + 3,
            output.run(acc, input, run, pos),
            errors,
          )
        Ok(next), True -> {
          let acc = output.push(acc, input, run, pos, output.replacement)
          let pos = pos + 3
          iso_2022_jp_loop(
            input,
            drop(rest, 3),
            next,
            True,
            pos,
            pos,
            acc,
            errors + 1,
          )
        }
        // Only the escape byte is consumed; the bytes after it are decoded
        // in the current state.
        Error(_), _ -> {
          let acc = output.push(acc, input, run, pos, output.replacement)
          iso_2022_jp_loop(
            input,
            tail,
            state,
            False,
            pos + 1,
            pos + 1,
            acc,
            errors + 1,
          )
        }
      }
    }
    <<b, tail:bytes>> -> {
      let step = case state, b {
        Ascii, _ | Roman, _ if b == 0x0E || b == 0x0F || b >= 0x80 ->
          Step(Error(Nil), 1)
        Roman, 0x5C -> Step(Ok(output.utf8(0xA5)), 1)
        Roman, 0x7E -> Step(Ok(output.utf8(0x203E)), 1)
        // Unchanged; extends the run.
        Ascii, _ | Roman, _ -> Step(Ok(<<>>), 0)
        Katakana, _ if b >= 0x21 && b <= 0x5F ->
          Step(Ok(output.utf8(0xFF61 - 0x21 + b)), 1)
        Katakana, _ -> Step(Error(Nil), 1)
        LeadByte, _ if b >= 0x21 && b <= 0x7E ->
          case tail {
            <<trail, _:bytes>> if trail >= 0x21 && trail <= 0x7E ->
              case index_jis0208.code_point({ b - 0x21 } * 94 + trail - 0x21) {
                0 -> Step(Error(Nil), 2)
                code_point -> Step(Ok(output.utf8(code_point)), 2)
              }
            // An escape byte is decoded next, as an escape sequence.
            <<0x1B, _:bytes>> -> Step(Error(Nil), 1)
            <<_, _:bytes>> -> Step(Error(Nil), 2)
            _ -> Step(Error(Nil), 1)
          }
        LeadByte, _ -> Step(Error(Nil), 1)
      }
      case step {
        Step(_, 0) ->
          iso_2022_jp_loop(input, tail, state, False, pos + 1, run, acc, errors)
        Step(result, consumed) -> {
          let #(chunk, errors) = chunk(Step(result, consumed), errors)
          let acc = output.push(acc, input, run, pos, chunk)
          let pos = pos + consumed
          iso_2022_jp_loop(
            input,
            drop(rest, consumed),
            state,
            False,
            pos,
            pos,
            acc,
            errors,
          )
        }
      }
    }
    _ -> #(output.finish(output.run(acc, input, run, pos)), errors)
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

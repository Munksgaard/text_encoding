//// The EUC-KR decoder.

import text_encoding/internal/index_euc_kr
import text_encoding/internal/output.{type Output}

pub fn euc_kr(input: BitArray) -> #(String, Int) {
  loop(input, input, 0, 0, [], 0)
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
    <<b, tail:bytes>> if b < 0x80 -> loop(input, tail, pos + 1, run, acc, errors)
    <<b, tail:bytes>> -> {
      let #(result, consumed) = case b >= 0x81 && b <= 0xFE, tail {
        True, <<byte, _:bytes>> -> sequence(b, byte)
        _, _ -> #(Error(Nil), 1)
      }
      let #(chunk, errors) = case result {
        Ok(chunk) -> #(chunk, errors)
        Error(_) -> #(output.replacement, errors + 1)
      }
      let acc = output.push(acc, input, run, pos, chunk)
      let pos = pos + consumed
      let rest = case consumed {
        1 -> tail
        _ -> drop_one(tail)
      }
      loop(input, rest, pos, pos, acc, errors)
    }
    _ -> #(output.finish(output.run(acc, input, run, pos)), errors)
  }
}

fn sequence(leading: Int, byte: Int) -> #(Result(BitArray, Nil), Int) {
  let code_point = case byte >= 0x41 && byte <= 0xFE {
    True -> index_euc_kr.code_point({ leading - 0x81 } * 190 + byte - 0x41)
    False -> 0
  }
  case code_point, byte < 0x80 {
    0, True -> #(Error(Nil), 1)
    0, False -> #(Error(Nil), 2)
    _, _ -> #(Ok(output.utf8(code_point)), 2)
  }
}

fn drop_one(bytes: BitArray) -> BitArray {
  case bytes {
    <<_, rest:bytes>> -> rest
    _ -> <<>>
  }
}

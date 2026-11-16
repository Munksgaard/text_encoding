//// The EUC-KR decoder.

import text_encoding/internal/index_euc_kr
import text_encoding/internal/output.{type Step, Invalid}

pub fn euc_kr(input: BitArray) -> #(String, Int) {
  output.decode(input, step)
}

fn step(leading: Int, tail: BitArray) -> Step {
  case tail {
    <<byte, _:bytes>> if leading >= 0x81 && leading <= 0xFE -> {
      let code_point = case byte >= 0x41 && byte <= 0xFE {
        True -> index_euc_kr.code_point({ leading - 0x81 } * 190 + byte - 0x41)
        False -> 0
      }
      output.lookup(code_point, byte, 2)
    }
    _ -> Invalid(1)
  }
}

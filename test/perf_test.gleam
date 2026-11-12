//// Doubling tests: each decoder is timed at size n and 8n. Linear work
//// grows about 8 times; quadratic work about 64 times. The threshold of 32
//// leaves room for garbage collection. Large inputs also catch stack
//// overflows on the JavaScript target.

import gleam/bit_array
import gleam/int
import gleam/list
import text_encoding.{type Encoding, KeepBom}

@external(erlang, "text_encoding_perf_ffi", "now_us")
@external(javascript, "./text_encoding_perf_ffi.mjs", "now_us")
fn now_us() -> Int

/// The best of three runs, in microseconds.
fn time(f: fn() -> a) -> Int {
  [1, 2, 3]
  |> list.map(fn(_) {
    let start = now_us()
    let _ = f()
    now_us() - start
  })
  |> list.fold(1_000_000_000, int.min)
}

fn repeat(chunk: BitArray, times: Int) -> BitArray {
  list.repeat(chunk, times) |> bit_array.concat
}

fn assert_linear(encoding: Encoding, chunk: BitArray) {
  let small = repeat(chunk, 20_000)
  let large = repeat(chunk, 160_000)
  let run = fn(input) { text_encoding.decode_with(input, encoding, KeepBom) }
  let t_small = int.max(time(fn() { run(small) }), 1000)
  let t_large = time(fn() { run(large) })
  let ratio = t_large / t_small
  case ratio < 32 {
    True -> Nil
    False ->
      panic as {
        text_encoding.name(encoding)
        <> ": growth ratio "
        <> int.to_string(ratio)
      }
  }
}

pub fn decoders_are_linear_test() {
  // Valid text, errors, and a mixture, for each family.
  [
    #(text_encoding.Utf8, <<"aé€😀":utf8>>),
    #(text_encoding.Utf8, <<0xF0, 0x80, 0x41, 0xFF>>),
    #(text_encoding.Utf16Le, <<0x41, 0, 0x3D, 0xD8, 0, 0xDE, 0, 0xDC>>),
    #(text_encoding.Windows1252, <<0x41, 0x80, 0x81, 0xE9>>),
    #(text_encoding.XUserDefined, <<0x41, 0x80>>),
    #(text_encoding.Gb18030, <<0x41, 0x81, 0x40, 0x81, 0x30, 0x81, 0x30, 0xFF>>),
    #(text_encoding.Big5, <<0x41, 0xA4, 0x40, 0x88, 0x62, 0x80>>),
    #(text_encoding.EucJp, <<0x41, 0xA4, 0xA2, 0x8E, 0xA1, 0x8F, 0xA2, 0xAF>>),
    #(text_encoding.ShiftJis, <<0x41, 0x82, 0xA0, 0xA1, 0xF0, 0x40, 0xFF>>),
    #(text_encoding.EucKr, <<0x41, 0xB0, 0xA1, 0x81, 0x20>>),
    #(text_encoding.Iso2022Jp, <<
      0x1B, 0x24, 0x42, 0x30, 0x21, 0x1B, 0x28, 0x42, 0x41, 0x1B, 0x28,
    >>),
  ]
  |> list.each(fn(case_) { assert_linear(case_.0, case_.1) })
}

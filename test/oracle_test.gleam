//// Differential tests against encoding_rs 0.8.35 (Firefox's
//// implementation of the standard). test/fixtures/oracle/sweeps.tsv holds
//// a hash of encoding_rs's results for each sweep of inputs; the inputs are
//// built here exactly as dev/oracle_vectors.py builds them, and the two
//// must stay in step. On a mismatch, `dev/oracle_vectors.py ORACLE --dump
//// ENCODING SWEEP` prints encoding_rs's result for each input.

import gleam/bit_array
import gleam/crypto
import gleam/int
import gleam/list
import gleam/string
import support
import text_encoding.{type Encoding, KeepBom}

const alphabet = [
  0x00, 0x0E, 0x0F, 0x1B, 0x20, 0x24, 0x28, 0x30, 0x39, 0x40, 0x41, 0x42, 0x49,
  0x4A, 0x5C, 0x7E, 0x7F, 0x80, 0x81, 0x8E, 0x8F, 0xA0, 0xA1, 0xBB, 0xBF, 0xC2,
  0xD8, 0xDC, 0xDF, 0xE0, 0xED, 0xEF, 0xF0, 0xF4, 0xFC, 0xFD, 0xFE, 0xFF,
]

const random_inputs = 2000

const modulus = 2_147_483_647

/// The integers from `from` to `to`, exclusive.
fn range(from: Int, to: Int) -> List(Int) {
  int.range(from, to, [], fn(acc, i) { [i, ..acc] }) |> list.reverse
}

fn single() -> List(BitArray) {
  list.map(range(0, 256), fn(b) { <<b>> })
}

fn pairs() -> List(BitArray) {
  list.map(range(0, 256), fn(lead) {
    range(0, 256)
    |> list.map(fn(trail) { <<lead, trail, 0x20>> })
    |> bit_array.concat
  })
}

fn euc_jp_triples() -> List(BitArray) {
  list.map(range(0, 256), fn(second) {
    range(0, 256)
    |> list.map(fn(third) { <<0x8F, second, third, 0x20>> })
    |> bit_array.concat
  })
}

fn gb18030_fours() -> List(BitArray) {
  list.map(range(0x81, 0xFF), fn(first) {
    list.flat_map(range(0x30, 0x3A), fn(second) {
      list.flat_map(range(0x81, 0xFF), fn(third) {
        list.map(range(0x30, 0x3A), fn(fourth) {
          <<first, second, third, fourth>>
        })
      })
    })
    |> bit_array.concat
  })
}

const escapes = [
  <<0x1B, 0x28, 0x42>>,
  <<0x1B, 0x28, 0x4A>>,
  <<0x1B, 0x28, 0x49>>,
  <<0x1B, 0x24, 0x40>>,
  <<0x1B, 0x24, 0x42>>,
]

fn iso_2022_jp_states() -> List(BitArray) {
  list.flat_map(escapes, fn(escape) {
    list.map(range(0, 256), fn(lead) {
      [escape, ..list.map(range(0, 256), fn(trail) { <<lead, trail>> })]
      |> bit_array.concat
    })
  })
}

fn random(encoding: Encoding) -> List(BitArray) {
  let assert Ok(#(_, index)) =
    text_encoding.encodings
    |> list.index_map(fn(e, i) { #(e, i) })
    |> list.find(fn(pair) { pair.0 == encoding })
  random_loop({ index + 1 } * 7919, random_inputs, [])
}

fn next(state: Int) -> Int {
  state * 48_271 % modulus
}

fn random_loop(state: Int, count: Int, acc: List(BitArray)) -> List(BitArray) {
  case count {
    0 -> list.reverse(acc)
    _ -> {
      let state = next(state)
      let #(state, bytes) = random_bytes(state, state % 25, [])
      random_loop(state, count - 1, [bytes, ..acc])
    }
  }
}

fn random_bytes(state: Int, length: Int, acc: List(Int)) -> #(Int, BitArray) {
  case length {
    0 -> #(
      state,
      acc |> list.reverse |> list.map(fn(b) { <<b>> }) |> bit_array.concat,
    )
    _ -> {
      let state = next(state)
      let byte = case state % 2 {
        0 -> {
          let assert Ok(b) =
            list.drop(alphabet, state / 2 % list.length(alphabet))
            |> list.first
          b
        }
        _ -> state / 2 % 256
      }
      random_bytes(state, length - 1, [byte, ..acc])
    }
  }
}

fn inputs(encoding: Encoding, sweep: String) -> List(BitArray) {
  case sweep {
    "single" -> single()
    "pairs" -> pairs()
    "random" -> random(encoding)
    "euc_jp_triples" -> euc_jp_triples()
    "gb18030_fours" -> gb18030_fours()
    "iso_2022_jp_states" -> iso_2022_jp_states()
    _ -> panic as { "unknown sweep " <> sweep }
  }
}

fn digest(encoding: Encoding, inputs: List(BitArray)) -> String {
  inputs
  |> list.map(fn(input) {
    let decoded = text_encoding.decode_with(input, encoding, KeepBom)
    let errors = case decoded.errors {
      0 -> 0
      _ -> 1
    }
    <<decoded.text:utf8, 0xFF, errors>>
  })
  |> bit_array.concat
  |> crypto.hash(crypto.Sha256, _)
  |> bit_array.base16_encode
  |> string.lowercase
}

fn encoding_named(name: String) -> Encoding {
  let assert Ok(encoding) =
    list.find(text_encoding.encodings, fn(e) { text_encoding.name(e) == name })
  encoding
}

pub fn sweeps_test() {
  let rows = support.fixture_lines("test/fixtures/oracle/sweeps.tsv")
  assert list.length(rows) == 124
  let failures =
    list.filter_map(rows, fn(fields) {
      let assert [name, sweep, count, expected] = fields
      let encoding = encoding_named(name)
      let inputs = inputs(encoding, sweep)
      assert int.to_string(list.length(inputs)) == count
      case digest(encoding, inputs) == expected {
        True -> Error(Nil)
        False -> Ok(#(name, sweep))
      }
    })
  assert failures == []
}

//// Helpers shared by the tests.

import gleam/bit_array
import gleam/list
import gleam/string
import simplifile

/// Decodes hexadecimal (an even number of digits).
pub fn hex(text: String) -> BitArray {
  let assert Ok(bytes) = bit_array.base16_decode(string.uppercase(text))
  bytes
}

/// The lines of a fixture file, without empty lines and `#` comments.
pub fn fixture_lines(path: String) -> List(List(String)) {
  let assert Ok(text) = simplifile.read(path)
  text
  |> string.split("\n")
  |> list.filter(fn(line) { line != "" && !string.starts_with(line, "#") })
  |> list.map(string.split(_, "\t"))
}

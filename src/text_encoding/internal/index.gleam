//// Lookups in the generated indexes (dev/generate.py). An index is a
//// BitArray of fixed-width entries; 0 marks a pointer without an entry.

/// The entry for `pointer` in an index of 16-bit entries, or 0.
pub fn lookup16(data: BitArray, pointer: Int) -> Int {
  let offset = pointer * 2
  case pointer >= 0, data {
    True, <<_:bytes-size(offset), code_point:16, _:bits>> -> code_point
    _, _ -> 0
  }
}

/// The entry for `pointer` in an index of 32-bit entries, or 0.
pub fn lookup32(data: BitArray, pointer: Int) -> Int {
  let offset = pointer * 4
  case pointer >= 0, data {
    True, <<_:bytes-size(offset), code_point:32, _:bits>> -> code_point
    _, _ -> 0
  }
}

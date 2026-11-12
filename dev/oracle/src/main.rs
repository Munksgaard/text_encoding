//! Decodes inputs with encoding_rs, for dev/oracle_vectors.py.
//!
//! Reads lines "<encoding name> <input as hex>" and writes lines
//! "<output UTF-8 as hex> <1 if there were errors, else 0>". Decoding is
//! without BOM handling, as the spec's decoders are.

use encoding_rs::*;
use std::io::{BufRead, Write};

static ENCODINGS: [&Encoding; 40] = [
    UTF_8, IBM866, ISO_8859_2, ISO_8859_3, ISO_8859_4, ISO_8859_5, ISO_8859_6,
    ISO_8859_7, ISO_8859_8, ISO_8859_8_I, ISO_8859_10, ISO_8859_13, ISO_8859_14,
    ISO_8859_15, ISO_8859_16, KOI8_R, KOI8_U, MACINTOSH, WINDOWS_874,
    WINDOWS_1250, WINDOWS_1251, WINDOWS_1252, WINDOWS_1253, WINDOWS_1254,
    WINDOWS_1255, WINDOWS_1256, WINDOWS_1257, WINDOWS_1258, X_MAC_CYRILLIC, GBK,
    GB18030, BIG5, EUC_JP, ISO_2022_JP, SHIFT_JIS, EUC_KR, REPLACEMENT,
    UTF_16BE, UTF_16LE, X_USER_DEFINED,
];

fn main() {
    let stdin = std::io::stdin();
    let mut out = std::io::BufWriter::new(std::io::stdout());
    for line in stdin.lock().lines() {
        let line = line.unwrap();
        let (name, hex) = line.split_once(' ').unwrap_or((&line, ""));
        let bytes: Vec<u8> = (0..hex.len() / 2)
            .map(|i| u8::from_str_radix(&hex[2 * i..2 * i + 2], 16).unwrap())
            .collect();
        let encoding = *ENCODINGS
            .iter()
            .find(|e| e.name() == name)
            .unwrap_or_else(|| panic!("unknown encoding {name}"));
        let (text, had_errors) = encoding.decode_without_bom_handling(&bytes);
        let output: String = text.as_bytes().iter().map(|b| format!("{:02x}", b)).collect();
        writeln!(out, "{} {}", output, had_errors as u8).unwrap();
    }
}

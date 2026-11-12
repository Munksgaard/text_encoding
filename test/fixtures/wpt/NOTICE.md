# web-platform-tests vectors

`vectors.tsv` is extracted by `dev/wpt_vectors.py` from the `encoding/`
directory of https://github.com/web-platform-tests/wpt at commit
`7482109050c502bfaffe0e65c783e63662ec012e`:

- `legacy-mb-schinese/gb18030/gb18030-decoder.any.js` (for gb18030 and GBK)
- `legacy-mb-schinese/gbk/gbk-decoder.any.js`
- `iso-2022-jp-decoder.any.js`
- `textdecoder-fatal.any.js`
- `textdecoder-utf16-surrogates.any.js`
- `textdecoder-eof.any.js` (the tests without streaming)

`test/wpt_test.gleam` also ports `textdecoder-byte-order-marks.any.js`,
`textdecoder-ignorebom.any.js`, `textdecoder-mistakes.any.js`,
`textdecoder-labels.any.js` and `api-invalid-label.any.js` by hand.

The web-platform-tests are licensed under the 3-Clause BSD License:

Copyright © web-platform-tests contributors

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice,
   this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.
3. Neither the name of the copyright holder nor the names of its
   contributors may be used to endorse or promote products derived from this
   software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
POSSIBILITY OF SUCH DAMAGE.

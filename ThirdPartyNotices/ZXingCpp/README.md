# ZXing-C++ reader, pinned v3.1.1

Upstream: https://github.com/zxing-cpp/zxing-cpp/tree/v3.1.1
Commit: 287c85df6f961c8efbfb5ffd736cd9457b8b890e
Codeload tag archive SHA-256: 7286b1e6ade66fe82b7c8208b4595deeb55d6486b410834fdc65702f46650542

Runtime is offline, QR Model 2 reader only. No writers, Zint, other barcode readers, camera wrapper or network fetch.
`Vendor/ToolboxQRReader/manifest.json` records included files. Upstream headers retain copyright notices.
ZXing and librscpp are Apache-2.0 (`LICENSE`). libzueci is BSD-3-Clause; embedded UTF-8 DFA also carries Bjoern Hoehrmann's permissive notice (see `libzueci-notice.c`).

Local modifications:
- Generated Version.h selects only QR readers, disables other families/writers.
- DecoderResult tracks successful Content construction separately from content length. BarcodeData no longer rejects an otherwise successful empty payload. This permits legitimate empty QR content; default/failed DecoderResult remains invalid and checksum/format errors remain failures. Regression fixtures independently encoded by Segno plus blank-image tests cover the distinction. No QR grammar/ECC change.
- ECI.h uses the existing charset mapping to reject reserved/unsupported assignments (e.g.127) as UnknownECI. Upstream’s numeric <=899 check otherwise allowed an empty or partial text interpretation. Unknown fallback and known encodings/binary remain supported; no bitstream grammar change.
- Length-aware Toolbox C ABI wrapper exposes bytes, text and metadata, catches exceptions; C++ objects never escape.

Build sources/selection and all local patches are documented here and in the local package README. No source or diagnostic payload logging.

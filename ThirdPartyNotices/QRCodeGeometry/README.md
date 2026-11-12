# QR function-module geometry reference

The alignment-center spacing formula in `QRCodeEncoder.functionMask` follows
Project Nayuki's QR Code generator reference (Python `qrcodegen.py`,
`_get_alignment_pattern_positions`), reviewed 2026-10-21:
https://github.com/nayuki/QR-Code-generator/blob/master/python/qrcodegen.py

Only the small geometry formula is used. No QR encoding/decoding, ECC, library
runtime or package dependency is included. Core Image generates the symbol;
Vision verifies it. Copyright and MIT permission are retained in LICENSE and
in the bundled ThirdPartyNotices.txt.

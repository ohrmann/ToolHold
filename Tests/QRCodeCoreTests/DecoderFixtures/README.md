# Decoder fixtures

Independent encoder: Segno 1.6.6, BSD-3-Clause (license alongside). Regenerate with `generate.py`; dependencies are development-only in a temporary directory, never application packages. PNGs/hash manifest are checked in; tests do not download/generate them with the decoder under test.

Fixtures cover numeric/alphanumeric, UTF-8 ECI, implicit Latin1 (Segno correctly omits default ECI3), CP1251, Kanji, binary0...255, embedded NUL, empty payload, structured append, mixed ECI segments. Additional generator hooks ask Segno to emit unsupported assignment127 and prepend FNC1-first-position mode for a GS1 fixture; all segment encoding/ECC/matrix generation remains in Segno. Expected bytes/text are independently specified in manifest.json, not derived from ZXing output. Structured append results remain separate.

Pillow generates two highly compressed images whose metadata exceeds side/pixel budgets. Tests reject them before decoding pixels. No real user data; all samples are synthetic. Source script, license and manifest are not app resources.
